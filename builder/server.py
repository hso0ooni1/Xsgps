"""APK/XAPK packager for the existing XS GPS Android library."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
import asyncio
from pathlib import Path
from xml.etree import ElementTree as ET

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

HERE = Path(__file__).resolve().parent
WORK = Path(os.getenv("JOB_ROOT", "/tmp/xsgps-builder"))
LIB_DEX = Path(os.getenv("XSGPS_DEX", "/opt/xsgps/classes.dex"))
LIB_MAP = Path(os.getenv("XSGPS_MAP", "/opt/xsgps/xsgps_map.html"))
TOOLS = Path(os.getenv("ANDROID_HOME", "/opt/android-sdk")) / "build-tools" / "35.0.0"
MAX_BYTES = {"apk": 140 * 1024 * 1024, "xapk": 512 * 1024 * 1024}
TTL = 3600
KEY = os.getenv("BUILDER_PASSWORD") or os.getenv("BUILDER_TOKEN", "")
STORE_PASSWORD = os.getenv("SIGNING_PASSWORD", "android")
STORE_ALIAS = os.getenv("SIGNING_ALIAS", "xsgpsdebug")
STORE = Path(os.getenv("SIGNING_STORE", str(WORK / "signing.jks")))
ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)
@asynccontextmanager
async def lifespan(app):
    async def sweep():
        while True:
            await asyncio.sleep(60)
            cleanup()
    task = asyncio.create_task(sweep())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass

app = FastAPI(title="XsGPS Builder", lifespan=lifespan,
              docs_url=None, redoc_url=None, openapi_url=None)
WORK.mkdir(parents=True, exist_ok=True)
jobs = {}
mutex = threading.Lock()
pool = ThreadPoolExecutor(max_workers=1)


def authorize(key):
    if not KEY:
        raise HTTPException(503, "BUILDER_PASSWORD is not configured")
    if not key or not secrets.compare_digest(key, KEY):
        raise HTTPException(401, "رمز البناء غير صحيح")


def run(*args, timeout=240):
    try:
        p = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise ValueError("انتهت مهلة أداة البناء؛ جرّب حزمة أصغر") from exc
    except OSError as exc:
        raise ValueError("إحدى أدوات البناء غير متاحة على السيرفر") from exc
    if p.returncode:
        message = (p.stderr or p.stdout).strip()[-1500:]
        if STORE_PASSWORD:
            message = message.replace(STORE_PASSWORD, "[redacted]")
        raise ValueError("فشل البناء: " + message)
    return p.stdout


def signing_key():
    if not STORE.exists():
        STORE.parent.mkdir(parents=True, exist_ok=True)
        encoded = os.getenv("SIGNING_KEYSTORE_B64")
        if encoded:
            STORE.write_bytes(base64.b64decode(encoded, validate=True))
        else:
            run("keytool", "-genkeypair", "-noprompt", "-keystore", STORE,
                "-storepass", STORE_PASSWORD, "-keypass", STORE_PASSWORD,
                "-alias", STORE_ALIAS, "-keyalg", "RSA", "-keysize", "3072",
                "-validity", "3650", "-dname", "CN=XsGPS Debug,O=Developer", timeout=60)
        STORE.chmod(0o600)
    return STORE


def status_set(job, state, message, **fields):
    with mutex:
        jobs[job].update(state=state, message=message, **fields)


def cleanup():
    with mutex:
        expired = [k for k, v in jobs.items()
                   if time.time() - v.get("finished", v["created"]) > TTL and v["state"] in ("done", "failed")]
        for k in expired:
            shutil.rmtree(jobs.pop(k)["directory"], ignore_errors=True)


def archive_members(z, limit=1200 * 1024 * 1024):
    infos = z.infolist()
    if len(infos) > 50000:
        raise ValueError("عدد الملفات الداخلية يتجاوز الحد")
    total, seen = 0, set()
    for member in infos:
        name = member.filename.replace("\\", "/")
        rel = Path(name)
        if (not rel.parts or name.startswith("/") or ".." in rel.parts or
            ":" in rel.parts[0] or member.flag_bits & 1 or
            ((member.external_attr >> 16) & 0o170000) == 0o120000):
            raise ValueError("الحزمة تحتوي مسارًا أو ملفًا غير آمن")
        canonical = rel.as_posix()
        if canonical != name.rstrip("/") or canonical in seen:
            raise ValueError("الحزمة تحتوي مسارات مكررة")
        seen.add(canonical)
        total += member.file_size
        if total > limit:
            raise ValueError("حجم الملفات المفكوكة يتجاوز الحد")
    return infos


def inspect_archive(path, fmt):
    if not path.is_file() or path.stat().st_size > MAX_BYTES[fmt]:
        raise ValueError("حجم الملف يتجاوز الحد")
    if not zipfile.is_zipfile(path):
        raise ValueError("الملف ليس APK/XAPK صالحًا")
    with zipfile.ZipFile(path) as z:
        archive_members(z)
        if fmt == "apk":
            if "AndroidManifest.xml" not in z.namelist():
                raise ValueError("APK لا يحتوي AndroidManifest.xml")
            if any(n.startswith("assets/lspatch/") for n in z.namelist()):
                raise ValueError("الملف مدمج مسبقًا؛ استخدم النسخة الأصلية")
            for name in z.namelist():
                if re.fullmatch(r"classes(?:[2-9]|[1-9][0-9]+)?\.dex", name):
                    if b"Lcom/xsgps/embed/XsGpsOverlay;" in z.read(name):
                        raise ValueError("XS GPS موجودة مسبقًا؛ استخدم النسخة الأصلية")
        elif not any(n.lower().endswith('.apk') for n in z.namelist()):
            raise ValueError("هذا الملف ليس XAPK؛ لا توجد ملفات APK داخله")


def safe_unpack(source, target):
    with zipfile.ZipFile(source) as z:
        for member in archive_members(z):
            destination = target / Path(member.filename.replace("\\", "/"))
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                with z.open(member) as reader, destination.open("wb") as writer:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)


def apk_info(filename):
    output = run(TOOLS / "aapt", "dump", "badging", filename, timeout=65)
    first = next((s for s in output.splitlines() if s.startswith("package:")), "")
    pkg = re.search(r"\bname='([^']+)'", first)
    split = re.search(r"\bsplit='([^']+)'", first)
    version = re.search(r"\bversionCode='([^']+)'", first)
    if not pkg:
        raise ValueError("تعذّرت قراءة هوية APK")
    return pkg.group(1), split.group(1) if split else None, version.group(1) if version else ""


def configure_manifest(decoded):
    manifest = decoded / "AndroidManifest.xml"
    doc = ET.parse(manifest)
    root = doc.getroot()
    application = root.find("application")
    if application is None:
        raise ValueError("لا توجد عقدة application في التطبيق")
    package = root.get("package", "")
    if not re.fullmatch(r"[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)+", package):
        raise ValueError("اسم حزمة غير صالح")
    a = "{" + ANDROID + "}"
    service = "com.xsgps.embed.XsGpsLocationService"
    provider = "com.xsgps.embed.XsGpsInitProvider"
    if any(c.get(a + "name") in (service, provider) for c in application):
        raise ValueError("XS GPS مدمجة مسبقًا")
    if application.get(a + "hasCode") == "false":
        application.set(a + "hasCode", "true")
    for perm in ("INTERNET", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION",
                 "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_LOCATION", "POST_NOTIFICATIONS"):
        full = "android.permission." + perm
        existing = next((e for e in root.findall("uses-permission") if e.get(a + "name") == full), None)
        if existing is None:
            root.insert(list(root).index(application), ET.Element("uses-permission", {a + "name": full}))
        else:
            existing.attrib.pop(a + "maxSdkVersion", None)
    ET.SubElement(application, "service", {
        a + "name": service, a + "exported": "false", a + "foregroundServiceType": "location"})
    ET.SubElement(application, "provider", {
        a + "name": provider, a + "authorities": package + ".xsgps.init." + secrets.token_hex(4),
        a + "exported": "false", a + "initOrder": "100"})
    # APKTool stores SDK metadata in YAML. Keep both representations in sync.
    sdk = root.find("uses-sdk")
    if sdk is not None:
        value = sdk.get(a + "minSdkVersion", "1")
        if not value.isdigit():
            raise ValueError("minSdkVersion غير رقمي؛ هذه الحزمة غير مدعومة")
        sdk.set(a + "minSdkVersion", str(max(26, int(value))))
    config = decoded / "apktool.yml"
    yml = config.read_text()
    match = re.search(r"(?m)^(\s*)minSdkVersion:\s*['\"]?(\d+)['\"]?\s*$", yml)
    if match:
        yml = yml[:match.start()] + match.group(1) + "minSdkVersion: " + str(max(26, int(match.group(2)))) + yml[match.end():]
    elif "sdkInfo:" not in yml:
        yml += "\nsdkInfo:\n  minSdkVersion: 26\n"
    else:
        yml = re.sub(r"(?m)^sdkInfo:.*$", "sdkInfo:\n  minSdkVersion: 26", yml)
    config.write_text(yml)
    doc.write(manifest, encoding="utf-8", xml_declaration=True)


def sign(unsigned, signed, work):
    aligned = work / ("aligned_" + secrets.token_hex(6) + ".apk")
    run(TOOLS / "zipalign", "-P", "16", "-f", "4", unsigned, aligned, timeout=90)
    run(TOOLS / "apksigner", "sign", "--ks", signing_key(),
        "--ks-key-alias", STORE_ALIAS, "--ks-pass", "pass:" + STORE_PASSWORD,
        "--key-pass", "pass:" + STORE_PASSWORD, "--out", signed, aligned, timeout=120)
    run(TOOLS / "apksigner", "verify", signed, timeout=60)
    aligned.unlink(missing_ok=True)


def integrate(base, output, work):
    inspect_archive(base, "apk")
    if not LIB_DEX.is_file() or not LIB_MAP.is_file():
        raise ValueError("مكتبة XS GPS غير جاهزة على السيرفر")
    if apk_info(base)[1]:
        raise ValueError("هذا Split APK؛ ارفع حزمة XAPK الكاملة")
    decoded, built = work / "decoded", work / "built.apk"
    # Keep host DEX byte-for-byte; only decode resources and manifest.
    run("java", "-jar", "/opt/apktool.jar", "d", "-f", "-s", base, "-o", decoded, timeout=240)
    configure_manifest(decoded)
    (decoded / "assets").mkdir(exist_ok=True)
    shutil.copyfile(LIB_MAP, decoded / "assets" / "xsgps_map.html")
    run("java", "-jar", "/opt/apktool.jar", "b", decoded, "-o", built, timeout=300)
    with zipfile.ZipFile(built, "a") as z:
        nums = [int(m.group(1) or 1) for name in z.namelist()
                if (m := re.fullmatch(r"classes(\d*)\.dex", name))]
        name = "classes.dex" if not nums else "classes" + str(max(nums) + 1) + ".dex"
        z.write(LIB_DEX, name, compress_type=zipfile.ZIP_STORED)
    sign(built, output, work)
    if apk_info(base) != apk_info(output):
        raise ValueError("هوية التطبيق تغيرت أثناء البناء")


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def process_xapk(source, output, work):
    inspect_archive(source, "xapk")
    unpacked = work / "xapk"
    unpacked.mkdir()
    safe_unpack(source, unpacked)
    apks = sorted(p for p in unpacked.rglob("*") if p.is_file() and p.suffix.lower() == ".apk")
    if not apks or len(apks) > 50:
        raise ValueError("ملفات APK داخل XAPK مفقودة أو أكثر من الحد")
    information = {p: apk_info(p) for p in apks}
    if len({data[1] for data in information.values()}) != len(information):
        raise ValueError("أسماء Split APK مكررة")
    bases = [p for p, data in information.items() if not data[1]]
    if len(bases) != 1:
        raise ValueError("XAPK يحتاج ملف APK أساسيًا واحدًا وملفات split متوافقة")
    base = bases[0]
    package, _, version = information[base]
    if any(pkg != package or v != version for pkg, _, v in information.values()):
        raise ValueError("ملفات Split APK ليست من التطبيق والإصدار نفسه")
    signed = work / "signed"
    signed.mkdir()
    replacements = {}
    for index, path in enumerate(apks):
        target = signed / (str(index) + ".apk")
        inspect_archive(path, "apk")
        (integrate if path == base else sign)(path, target, work)
        if apk_info(target) != information[path]:
            raise ValueError("هوية أحد ملفات Split APK تغيرت")
        replacements[path.relative_to(unpacked).as_posix()] = target
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(output, "w", allowZip64=True) as result:
        for member in original.infolist():
            if member.is_dir():
                continue
            name = member.filename.replace("\\", "/")
            replacement = replacements.get(name)
            if replacement:
                result.write(replacement, name, compress_type=zipfile.ZIP_DEFLATED, compresslevel=1)
            elif name == "manifest.json":
                manifest = json.loads(original.read(member))
                if not isinstance(manifest, dict):
                    raise ValueError("manifest.json في XAPK غير صالح")
                entries = manifest.get("split_apks", [])
                if not isinstance(entries, list):
                    raise ValueError("split_apks في manifest.json غير صالح")
                for item in entries:
                    if isinstance(item, dict) and item.get("file") in replacements:
                        file = replacements[item["file"]]
                        if "file_size" in item:
                            item["file_size"] = file.stat().st_size
                        if "sha256" in item:
                            item["sha256"] = sha256(file)
                        if "md5" in item:
                            with file.open("rb") as stream:
                                item["md5"] = hashlib.file_digest(stream, "md5").hexdigest()
                if "total_size" in manifest:
                    manifest["total_size"] = sum(
                        replacements[m.filename.replace("\\", "/")].stat().st_size
                        if m.filename.replace("\\", "/") in replacements else m.file_size
                        for m in original.infolist() if not m.is_dir() and m.filename != "manifest.json")
                result.writestr(name, json.dumps(manifest, ensure_ascii=False).encode("utf-8"))
            else:
                with original.open(member) as src, result.open(member, "w", force_zip64=True) as dst:
                    shutil.copyfileobj(src, dst, 1024 * 1024)


def process(job, uploaded, fmt):
    work = uploaded.parent
    try:
        status_set(job, "running", "جارٍ فحص الحزمة ودمج XsGPS…")
        if not zipfile.is_zipfile(uploaded):
            raise ValueError("الملف ليس APK/XAPK صالحًا")
        output = work / ("XS-GPS-integrated." + fmt)
        if fmt == "apk":
            integrate(uploaded, output, work)
        else:
            process_xapk(uploaded, output, work)
        digest = sha256(output)
        status_set(job, "done", "اكتمل الدمج والتوقيع", finished=time.time(), download_ticket=secrets.token_urlsafe(32), sha256=digest,
                   output_name=output.name)
    except Exception as exc:
        status_set(job, "failed", str(exc)[:1700], finished=time.time())
    finally:
        keep = jobs[job].get("output_name") if jobs[job]["state"] == "done" else None
        for path in work.iterdir():
            if path.name == keep:
                continue
            if path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
            else:
                path.unlink(missing_ok=True)
    cleanup()


@app.get("/", response_class=HTMLResponse)
def homepage():
    return (HERE / "index.html").read_text(encoding="utf-8")


@app.get("/health")
@app.get("/api/health")
def health():
    ok = (LIB_DEX.is_file() and LIB_MAP.is_file() and Path("/opt/apktool.jar").is_file()
          and all((TOOLS / name).is_file() for name in ("aapt", "zipalign", "apksigner")))
    return JSONResponse({"ok": ok, "formats": ["apk", "xapk"], "version": "2.0"},
                        status_code=200 if ok else 503)


@app.post("/api/build")
async def build(file: UploadFile = File(...), x_builder_key: str | None = Header(None)):
    authorize(x_builder_key)
    fmt = Path(file.filename or "").suffix.lower().lstrip(".")
    if fmt not in MAX_BYTES:
        await file.close()
        raise HTTPException(400, "الملفات المدعومة APK وXAPK فقط")
    cleanup()
    job = secrets.token_urlsafe(18)
    folder = WORK / job
    # Reserve the slot before awaiting upload; concurrent requests cannot bypass it.
    with mutex:
        busy = sum(x["state"] in ("uploading", "queued", "running") for x in jobs.values())
        if busy >= 2:
            raise HTTPException(429, "السيرفر مشغول؛ حاول لاحقًا")
        folder.mkdir(mode=0o700)
        jobs[job] = {"state": "uploading", "message": "جارٍ الرفع", "created": time.time(),
                     "directory": folder}
    upload = folder / ("upload." + fmt)
    size = 0
    try:
        with upload.open("wb") as sink:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_BYTES[fmt]:
                    raise HTTPException(413, "حجم الملف تجاوز الحد المسموح")
                sink.write(chunk)
        if size < 1024:
            raise HTTPException(400, "الملف فارغ أو غير صالح")
        status_set(job, "queued", "في قائمة البناء")
        pool.submit(process, job, upload, fmt)
    except BaseException:
        with mutex:
            jobs.pop(job, None)
        shutil.rmtree(folder, ignore_errors=True)
        raise
    finally:
        await file.close()
    return {"job": job}


@app.get("/api/status/{job}")
def status(job: str, x_builder_key: str | None = Header(None)):
    authorize(x_builder_key)
    cleanup()
    with mutex:
        current = jobs.get(job)
        if not current:
            raise HTTPException(404, "المهمة غير موجودة أو انتهت صلاحيتها")
        return {k: v for k, v in current.items() if k != "directory"}


@app.get("/api/download/{job}")
def download(job: str, ticket: str | None = None, x_builder_key: str | None = Header(None)):
    with mutex:
        expected = jobs.get(job, {}).get("download_ticket")
    if not (expected and ticket and secrets.compare_digest(ticket, expected)):
        authorize(x_builder_key)
    cleanup()
    with mutex:
        current = jobs.get(job)
        if not current or current["state"] != "done":
            raise HTTPException(404, "الملف غير متاح")
        file = current["directory"] / current["output_name"]
    return FileResponse(file, filename=file.name,
                        media_type="application/zip" if file.suffix == ".xapk" else "application/vnd.android.package-archive")
