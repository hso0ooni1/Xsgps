"""LSPatch proof of concept limited to the XsGPS-owned demo package.

No signature spoofing, location-API interception, or integrity-check bypass.
Users must separately install the XsGPS test module and enable Android's
official Mock Location setting. Keeps XAPK splits and OBB files together.
"""
import json
import os
import shutil
import zipfile
from pathlib import Path

MODULE = Path(os.getenv("XSGPS_MODULE_PATH", "/opt/xsgps/module.apk"))
PATCHER = Path(os.getenv("LSPATCH_PATH", "/opt/lspatch.jar"))
SAMPLE_PACKAGE = "com.xsgps.android"


def patch_demo(upload: Path, fmt: str, work: Path) -> Path:
    from server import apk_info, run, signing_key, STORE_PASSWORD, STORE_ALIAS
    from server import TOOLS, safe_unpack, sha256

    if not MODULE.is_file() or not PATCHER.is_file():
        raise ValueError("ملفات موديول الاختبار غير جاهزة على السيرفر")
    if fmt == "apk":
        originals = [upload]
        root = work
    elif fmt == "xapk":
        root = work / "xapk-input"
        root.mkdir()
        safe_unpack(upload, root)
        originals = sorted(p for p in root.rglob("*.apk") if p.is_file())
        if not originals or len(originals) > 50:
            raise ValueError("ملفات APK داخل XAPK غير صالحة")
    else:
        raise ValueError("اختر ملف APK أو XAPK")

    meta = {p: apk_info(p) for p in originals}
    bases = [p for p, (_, split, _) in meta.items() if not split]
    if len(bases) != 1:
        raise ValueError("يجب أن تحتوي الحزمة على APK أساسي واحد")
    base = bases[0]
    package, _, version = meta[base]
    if package != SAMPLE_PACKAGE:
        raise ValueError("نسخة LSPatch التجريبية مخصصة فقط لتطبيق XsGPS Demo")
    if any(pkg != package or ver != version for pkg, _, ver in meta.values()):
        raise ValueError("ملفات Split APK لا تطابق التطبيق الأساسي")

    inputs = work / "patch-input"
    outputs = work / "patch-output"
    inputs.mkdir()
    outputs.mkdir()
    staged = {}
    for number, original in enumerate(originals):
        filename = "base.apk" if original == base else f"split_{number:02d}.apk"
        target = inputs / filename
        shutil.copyfile(original, target)
        staged[original] = target

    run(
        "java", "-jar", PATCHER, "--force", "--output", outputs,
        "--sigbypasslv", "0", "--embed", MODULE,
        "--keystore", signing_key(), STORE_PASSWORD, STORE_ALIAS, STORE_PASSWORD,
        *staged.values(), timeout=750,
    )

    replacements = {}
    for original, stage in staged.items():
        generated = list(outputs.glob(stage.stem + "-*-lspatched.apk"))
        if len(generated) != 1:
            raise ValueError("تعذّر تحديد APK الناتج للملف " + stage.name)
        result = generated[0]
        run(TOOLS / "apksigner", "verify", "--verbose", result, timeout=60)
        pkg, split, _ = apk_info(result)
        if pkg != package or split != meta[original][1]:
            raise ValueError("هوية APK الناتج لا تطابق الملف الأصلي")
        replacements[original] = result

    if fmt == "apk":
        result = work / "XsGPS-demo-lspatched.apk"
        shutil.copyfile(replacements[base], result)
        return result

    result = work / "XsGPS-demo-lspatched.xapk"
    relative = {p.relative_to(root).as_posix(): v for p, v in replacements.items()}
    with zipfile.ZipFile(upload) as source, zipfile.ZipFile(
        result, "w", allowZip64=True
    ) as target:
        for member in source.infolist():
            if member.is_dir():
                continue
            name = member.filename.replace("\\", "/")
            if name in relative:
                target.write(relative[name], name, compress_type=zipfile.ZIP_DEFLATED)
            elif name.endswith("manifest.json"):
                manifest = json.loads(source.read(member))
                if not isinstance(manifest, dict):
                    raise ValueError("manifest.json غير صالح")
                for entry in manifest.get("split_apks", []):
                    if isinstance(entry, dict) and entry.get("file") in relative:
                        patched = relative[entry["file"]]
                        if "file_size" in entry:
                            entry["file_size"] = patched.stat().st_size
                        if "sha256" in entry:
                            entry["sha256"] = sha256(patched)
                target.writestr(name, json.dumps(manifest, ensure_ascii=False))
            else:
                with source.open(member) as reader, target.open(member, "w") as writer:
                    shutil.copyfileobj(reader, writer, 1024 * 1024)
    return result
