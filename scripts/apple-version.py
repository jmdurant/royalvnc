#!/usr/bin/env python3
"""Keep all Apple app versions aligned with the preserved iOS Info.plist."""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parent.parent
with (root / 'iOSApp/Info.plist').open('rb') as source:
    info = plistlib.load(source)
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
if not re.fullmatch(r'\d+(?:\.\d+){0,2}', version):
    raise SystemExit(f'Invalid marketing version: {version!r}')
if not re.fullmatch(r'\d+(?:\.\d+){0,2}', build):
    raise SystemExit(f'Invalid build number: {build!r}')
destination = root / '.build/apple-version.xcconfig'
destination.parent.mkdir(exist_ok=True)
destination.write_text(
    '// Generated from iOSApp/Info.plist by scripts/apple-version.py.\n'
    f'MARKETING_VERSION = {version}\nCURRENT_PROJECT_VERSION = {build}\n'
)
