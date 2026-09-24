"""Authorized Debug APK/XAPK builder for the XsGPS Android AAR."""
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
from pathlib import Path
from xml.etree import ElementTree as ET

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, HTMLResponse

HERE = Path(__file__).resolve().parent
WORK = Path(os.getenv("JOB_ROOT", "/tmp/xsgps-builder"))
LIB_DEX = Path(os.getenv("XSGPS_DEX", "/opt/xsgps/classes.dex"))
LIB_MAP = Path(os.getenv("XSGPS_MAP", "/opt/xsgps/xsgps_map.html"))
TOOLS = Path(os.getenv("ANDROID_HOME", "/opt/android-sdk")) / "build-tools" / "35.0.0"
MAX_BYTES = {"apk": 140 * 1024 * 1024, "xapk": 512 * 1024 * 1024}
TTL = 3600
KEY = os.getenv("BUILDER_PASSWORD", "")
STORE_PASSWORD = os.getenv("SIGNING_PASSWORD", "android")
STORE_ALIAS = os.getenv("SIGNING_ALIAS", "xsgpsdebug")
STORE = WORK / "signing.jks"
ANDROID = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID)
app = FastAPI(title="XsGPS Builder", docs_url=None, redoc_url=None, openapi_url=None)
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
    p = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if p.returncode:
        raise ValueError("فشل البناء: " + (p.stderr or p.stdout).strip()[-1500:])
    return p.stdout


def signing_key():
    if not STORE.exists():
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
                   if time.time() - v["created"] > TTL and v["state"] in ("done", "failed")]
        for k in expired:
            shutil.rmtree(jobs.pop(k)["directory"], ignore_errors=True)


def safe_unpack(source, target):
    """Prevent traversal, symlinks, encrypted ZIP entries and zip bombs."""
    uncompressed = 0
    with zipfile.ZipFile(source) as z:
        if len(z.infolist()) > 1000:
            raise ValueError("ملفات XAPK أكثر من الحد")
        for member in z.infolist():
            name = member.filename.replace("\\", "/")
            rel = Path(name)
            if (not name or name.startswith("/") or ".." in rel.parts or
                ":" in rel.parts[0] or member.flag_bits & 1 or
                ((member.external_attr >> 16) & 0o170000) == 0o120000):
                raise ValueError("حزمة XAPK تحتوي ملفًا أو مسارًا غير آمن")
            destination = (target / rel).resolve()
            if not destination.is_relative_to(target.resolve()):
                raise ValueError("مسار XAPK غير صالح")
            uncompressed += member.file_size
            if uncompressed > 1200 * 1024 * 1024:
                raise ValueError("حجم ملفات XAPK المفكوكة أكبر من الحد")
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


def find_launch_activity(xml):
    package = xml.get("package", "")
    application = xml.find("application")
    if application is None:
        raise ValueError("AndroidManifest لا يحتوي application")
    for child in application:
        if child.tag not in ("activity", "activity-alias"):
            continue
        for flt in child.findall("intent-filter"):
            actions = {x.get("{" + ANDROID + "}name") for x in flt.findall("action")}
            categories = {x.get("{" + ANDROID + "}name") for x in flt.findall("category")}
            if ("android.intent.action.MAIN" in actions and
                "android.intent.category.LAUNCHER" in categories):
                attr = "targetActivity" if child.tag == "activity-alias" else "name"
                name = child.get("{" + ANDROID + "}" + attr)
                if name:
                    return package + name if name.startswith(".") else (
                        package + "." + name if "." not in name else name)
    raise ValueError("لم يُعثر على شاشة تشغيل التطبيق")


def insert_overlay(decoded, activity):
    rel = Path(*activity.split(".")).with_suffix(".smali")
    path = next((root / rel for root in sorted(decoded.glob("smali*"))
                 if (root / rel).is_file()), None)
    if not path:
        raise ValueError("تعذّر العثور على كود شاشة التشغيل، ولا يمكن دمجه تلقائيًا")
    code = path.read_text(encoding="utf-8")
    call = "    invoke-static {p0}, Lcom/xsgps/embed/XsGpsOverlay;->attach(Landroid/app/Activity;)V"
    if call.strip() in code:
        return
    method = re.search(r"(?ms)^\.method[^\n]*\bonResume\(\)V[^\n]*\n.*?^\.end method", code)
    if method:
        part = method.group()
        supercall = re.search(r"(?m)^[ \t]*invoke-super(?:/range)? [^\n]*->onResume\(\)V[^\n]*$", part)
        if not supercall:
            raise ValueError("تعذّر تحديد موقع onResume الآمن للدمج")
        at = supercall.end()
        code = code[:method.start()] + part[:at] + "\n" + call + part[at:] + code[method.end():]
    else:
        parent = re.search(r"(?m)^\.super (L[^;]+;)", code)
        if not parent:
            raise ValueError("تعذّر تحديد الصنف الأب لشاشة التشغيل")
        code += ("\n.method protected onResume()V\n"
                 "    .locals 0\n"
                 "    invoke-super {p0}, " + parent.group(1) + "->onResume()V\n" +
                 call + "\n    return-void\n.end method\n")
    path.write_text(code, encoding="utf-8")


def sign(unsigned, signed, work):
    aligned = work / ("aligned_" + secrets.token_hex(6) + ".apk")
    run(TOOLS / "zipalign", "-f", "4", unsigned, aligned, timeout=90)
    run(TOOLS / "apksigner", "sign", "--ks", signing_key(),
        "--ks-key-alias", STORE_ALIAS, "--ks-pass", "pass:" + STORE_PASSWORD,
        "--key-pass", "pass:" + STORE_PASSWORD, "--out", signed, aligned, timeout=120)
    run(TOOLS / "apksigner", "verify", signed, timeout=60)
    aligned.unlink(missing_ok=True)


def integrate(base, output, work):
    decoded = work / "decoded"
    built = work / "built.apk"
    run("apktool", "d", "-f", base, "-o", decoded, timeout=210)
    manifest_file = decoded / "AndroidManifest.xml"
    doc = ET.parse(manifest_file)
    root = doc.getroot()
    application = root.find("application")
    if application is None or application.get("{" + ANDROID + "}debuggable", "false").lower() != "true":
        raise ValueError("الدمج متاح فقط لنسخة Debug: android:debuggable=true")
    insert_overlay(decoded, find_launch_activity(root))
    for perm in ("INTERNET", "ACCESS_FINE_LOCATION", "ACCESS_COARSE_LOCATION",
                 "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_LOCATION", "POST_NOTIFICATIONS"):
        full = "android.permission." + perm
        if not any(e.get("{" + ANDROID + "}name") == full for e in root.findall("uses-permission")):
            ET.SubElement(root, "uses-permission", {"{" + ANDROID + "}name": full})
    if not any(x.get("{" + ANDROID + "}name") == "com.xsgps.embed.XsGpsLocationService"
               for x in application.findall("service")):
        ET.SubElement(application, "service", {
            "{" + ANDROID + "}name": "com.xsgps.embed.XsGpsLocationService",
            "{" + ANDROID + "}exported": "false",
            "{" + ANDROID + "}foregroundServiceType": "location"})
    doc.write(manifest_file, encoding="utf-8", xml_declaration=True)
    (decoded / "assets").mkdir(exist_ok=True)
    shutil.copyfile(LIB_MAP, decoded / "assets" / "xsgps_map.html")
    run("apktool", "b", decoded, "-o", built, timeout=240)
    with zipfile.ZipFile(built, "a") as z:
        nums = [int(m.group(1) or 1) for name in z.namelist()
                if (m := re.fullmatch(r"classes(\d*)\.dex", name))]
        z.write(LIB_DEX, "classes" + str(max(nums, default=0) + 1) + ".dex",
                compress_type=zipfile.ZIP_STORED)
    sign(built, output, work)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def process_xapk(source, output, work):
    unpacked = work / "xapk"
    unpacked.mkdir()
    safe_unpack(source, unpacked)
    apks = sorted(p for p in unpacked.rglob("*") if p.is_file() and p.suffix.lower() == ".apk")
    if not apks or len(apks) > 50:
        raise ValueError("ملفات APK داخل XAPK مفقودة أو أكثر من الحد")
    information = {p: apk_info(p) for p in apks}
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
        (integrate if path == base else sign)(path, target, work)
        replacements[path.relative_to(unpacked).as_posix()] = target
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(output, "w", allowZip64=True) as result:
        for member in original.infolist():
            if member.is_dir():
                continue
            name = member.filename.replace("\\", "/")
            replacement = replacements.get(name)
            if replacement:
                result.write(replacement, name, compress_type=zipfile.ZIP_DEFLATED, compresslevel=1)
            elif name.endswith("manifest.json"):
                manifest = json.loads(original.read(member))
                if not isinstance(manifest, dict):
                    raise ValueError("manifest.json في XAPK غير صالح")
                for item in manifest.get("split_apks", []):
                    if isinstance(item, dict) and item.get("file") in replacements:
                        file = replacements[item["file"]]
                        if "file_size" in item:
                            item["file_size"] = file.stat().st_size
                        if "sha256" in item:
                            item["sha256"] = sha256(file)
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
        output = work / ("XsGPS-integrated-debug." + fmt)
        if fmt == "apk":
            integrate(uploaded, output, work)
        else:
            process_xapk(uploaded, output, work)
        digest = sha256(output)
        uploaded.unlink(missing_ok=True)
        status_set(job, "done", "اكتمل الدمج والتوقيع التجريبي", sha256=digest,
                   output_name=output.name)
    except Exception as exc:
        uploaded.unlink(missing_ok=True)
        status_set(job, "failed", str(exc)[:1700])
    cleanup()


@app.get("/", response_class=HTMLResponse)
def homepage():
    return (HERE / "index.html").read_text(encoding="utf-8")


@app.get("/health")
def health():
    ok = LIB_DEX.is_file() and LIB_MAP.is_file()
    return {"ok": ok, "formats": ["apk", "xapk"]}


@app.post("/api/build")
async def build(file: UploadFile = File(...), authorized: bool = Form(False),
                x_builder_key: str | None = Header(None)):
    authorize(x_builder_key)
    if not authorized:
        raise HTTPException(400, "أكّد ملكيتك أو تصريحك لتعديل نسخة Debug")
    fmt = Path(file.filename or "").suffix.lower().lstrip(".")
    if fmt not in MAX_BYTES:
        raise HTTPException(400, "الملفات المدعومة APK وXAPK فقط")
    cleanup()
    with mutex:
        busy = sum(x["state"] in ("queued", "running") for x in jobs.values())
    if busy >= 2:
        raise HTTPException(429, "السيرفر مشغول بمهمتين؛ حاول لاحقًا")
    job = secrets.token_urlsafe(18)
    folder = WORK / job
    folder.mkdir(mode=0o700)
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
    except Exception:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    finally:
        await file.close()
    with mutex:
        jobs[job] = {"state": "queued", "message": "في قائمة البناء", "created": time.time(),
                     "directory": folder}
    pool.submit(process, job, upload, fmt)
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
def download(job: str, x_builder_key: str | None = Header(None)):
    authorize(x_builder_key)
    cleanup()
    with mutex:
        current = jobs.get(job)
        if not current or current["state"] != "done":
            raise HTTPException(404, "الملف غير متاح")
        file = current["directory"] / current["output_name"]
    return FileResponse(file, filename=file.name,
                        media_type="application/zip" if file.suffix == ".xapk" else "application/vnd.android.package-archive")
