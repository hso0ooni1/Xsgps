"""Command-line entry point; uses the same engine as the upload website."""
import argparse
import json
import shutil
import tempfile
from pathlib import Path
from server import integrate, process_xapk, inspect_archive, sha256, MAX_BYTES


def main():
    p = argparse.ArgumentParser(description='Embed the XS GPS Android library in APK/XAPK')
    p.add_argument('input', type=Path)
    p.add_argument('-o', '--output', required=True, type=Path)
    args = p.parse_args()
    fmt = args.input.suffix.lower().lstrip('.')
    if fmt not in MAX_BYTES or args.output.suffix.lower() != '.' + fmt:
        p.error('Input and output must use the same APK or XAPK extension')
    if args.input.resolve() == args.output.resolve() or args.output.exists():
        p.error('Choose a new output path; existing files are never overwritten')
    inspect_archive(args.input, fmt)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='xsgps-cli-') as directory:
        work = Path(directory)
        result = work / ('result.' + fmt)
        (integrate if fmt == 'apk' else process_xapk)(args.input.resolve(), result, work)
        shutil.copyfile(result, args.output)
    print(json.dumps({'file': str(args.output), 'sha256': sha256(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
