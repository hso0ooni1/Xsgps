"""Safe LSPatch proof of concept for the XsGPS Android demo application only.

This build targets the owned sample package and runs with signature bypass OFF.
Its module provides a visible shortcut to the separately installed XsGPS test app;
Android's official mock-location consent remains required.
"""
from pathlib import Path
import os
import shutil

MODULE = Path(os.getenv("XSGPS_MODULE_PATH", "/opt/xsgps/module.apk"))
PATCHER = Path(os.getenv("LSPATCH_PATH", "/opt/lspatch.jar"))
SAMPLE_PACKAGE = "com.xsgps.android"


def patch_demo(apk: Path, output_dir: Path) -> Path:
    from server import apk_info, run, signing_key, STORE_PASSWORD, STORE_ALIAS, TOOLS
    if apk_info(apk)[0] != SAMPLE_PACKAGE:
        raise ValueError("النسخة التجريبية تقبل تطبيق XsGPS Demo فقط")
    if not MODULE.is_file() or not PATCHER.is_file():
        raise ValueError("ملفات موديول الاختبار غير جاهزة")
    output_dir.mkdir(parents=True, exist_ok=True)
    run("java", "-jar", PATCHER, "--force", "--output", output_dir,
        "--sigbypasslv", "0", "--embed", MODULE,
        "--keystore", signing_key(), STORE_PASSWORD, STORE_ALIAS, STORE_PASSWORD,
        apk, timeout=600)
    matches = list(output_dir.glob("*-lspatched.apk"))
    if len(matches) != 1:
        raise ValueError("لم ينتج ملف APK متوقع")
    output = matches[0]
    run(TOOLS / "apksigner", "verify", output)
    return output
