#!/usr/bin/env python3
"""Fail CI when the demo APK omits its native VNC/Swift/JNA libraries."""
from pathlib import Path
from zipfile import ZipFile

root = Path(__file__).resolve().parent.parent
project = root / 'Bindings/kotlin/RoyalVNCAndroidTest'
apks = list((project / 'app/build/outputs/apk/debug').glob('*.apk'))
if len(apks) != 1:
    raise SystemExit(f'Expected one debug APK, found {len(apks)}')
expected = {'libRoyalVNCKit.so', 'libjnidispatch.so'}
for module in ['royalvnc', 'swiftRuntime']:
    native = project / module / 'src/main/jniLibs/arm64-v8a'
    libraries = list(native.glob('*.so'))
    if not libraries:
        raise SystemExit(f'No native libraries staged for {module}')
    expected.update(path.name for path in libraries)
with ZipFile(apks[0]) as apk:
    packaged = {Path(name).name for name in apk.namelist() if name.startswith('lib/arm64-v8a/')}
    missing = expected - packaged
    if missing:
        raise SystemExit(f'APK missing arm64 native libraries: {sorted(missing)}')
    for library in expected:
        data = apk.read(f'lib/arm64-v8a/{library}')
        if (len(data) < 20 or data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1
                or int.from_bytes(data[18:20], 'little') != 183):
            raise SystemExit(f'APK has an invalid ELF64 AArch64 library: {library}')
    if 'AndroidManifest.xml' not in apk.namelist() or 'classes.dex' not in apk.namelist():
        raise SystemExit('APK missing manifest or app bytecode')
print(f'APK package verified: {apks[0]} ({len(expected)} arm64 native libraries)')
