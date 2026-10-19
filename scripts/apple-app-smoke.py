#!/usr/bin/env python3
"""Build an unsigned simulator app, verify its package, and launch it.

Usage: python3 scripts/apple-app-smoke.py ios|tvos|watchos [--skip-launch]
Each run saves its build log and a launch screenshot under .build/apple-smoke.
"""
import argparse
import json
from pathlib import Path
import plistlib
import platform
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
PLATFORMS = {
    'ios': ('iOSApp', 'RoyalVNCiOS', 'iphonesimulator', 'iOS', 'com.doctordurant.desktopondemand'),
    'tvos': ('TVApp', 'RoyalVNCTV', 'appletvsimulator', 'tvOS', 'com.royalapps.royalvnc.tv'),
    'watchos': ('WatchApp', 'RoyalVNCWatch', 'watchsimulator', 'watchOS', 'com.royalapps.royalvnc.watch'),
}


def run(*args, **kwargs):
    try:
        return subprocess.run(args, check=True, text=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, flush=True)
        if error.stderr:
            print(error.stderr, flush=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=PLATFORMS)
    parser.add_argument('--skip-launch', action='store_true', help='Verify the built package without starting a simulator')
    args = parser.parse_args()
    folder, scheme, sdk, runtime, bundle_id = PLATFORMS[args.platform]
    output = ROOT / '.build/apple-smoke' / args.platform
    output.mkdir(parents=True, exist_ok=True)
    run('xcodegen', 'generate', '--spec', str(ROOT / folder / 'project.yml'), cwd=ROOT)
    derived = output / 'DerivedData'
    log = output / 'build.log'
    with log.open('w') as stream:
        result = subprocess.run([
            'xcodebuild', '-project', str(ROOT / folder / f'{scheme}.xcodeproj'),
            '-scheme', scheme, '-sdk', sdk, '-configuration', 'Debug',
            '-destination', f'generic/platform={runtime} Simulator', f'ARCHS={platform.machine()}',
            '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'build',
        ], stdout=stream, stderr=subprocess.STDOUT, cwd=ROOT)
    if result.returncode:
        print('\n'.join(log.read_text().splitlines()[-100:]))
        raise SystemExit(f'{scheme} build failed; see {log}')
    app = derived / 'Build/Products' / f'Debug-{sdk}' / 'RoyalVNC.app'
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    with (ROOT / 'iOSApp/Info.plist').open('rb') as source:
        version = plistlib.load(source)
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        if info.get(key) != version[key]:
            raise SystemExit(f'{scheme}: {key} differs from version source: {info.get(key)!r} != {version[key]!r}')
    if info.get('CFBundleIdentifier') != bundle_id:
        raise SystemExit(f'Unexpected bundle identifier: {info.get("CFBundleIdentifier")}')
    executable = app / info['CFBundleExecutable']
    if not executable.is_file():
        raise SystemExit(f'{scheme}: missing app executable')
    app_binaries = [executable] + list(app.glob('*.dylib'))
    symbols = ''.join(run('nm', '-g', str(binary), capture_output=True).stdout for binary in app_binaries)
    if 'RoyalVNCKit' not in symbols or 'RoyalVNCClientCore' not in symbols:
        raise SystemExit(f'{scheme}: app executable is missing its linked VNC engine or shared client core')
    # The automatic ClientCore product links the engine statically into apps.
    # Still catch any future dynamic dependency missing from the final bundle.
    frameworks = list((app / 'Frameworks').glob('*.framework/*'))
    binaries = app_binaries + [path for path in frameworks if path.is_file() and path.name == path.parent.stem]
    for binary in binaries:
        links = run('otool', '-L', str(binary), capture_output=True).stdout
        for name in re.findall(r'@rpath/([^\s]+\.framework/[^\s]+)', links):
            if not (app / 'Frameworks' / name).is_file():
                raise SystemExit(f'{scheme}: unresolved embedded dependency {name}')
    run('ditto', '-c', '-k', '--keepParent', str(app), str(output / 'RoyalVNC-simulator.zip'))
    print(f'Package verified: {app} (version {info["CFBundleShortVersionString"]}, build {info["CFBundleVersion"]})', flush=True)
    if args.skip_launch:
        return
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j', capture_output=True).stdout)
    candidates = [d for key, values in devices['devices'].items()
                  if f'.{runtime}-' in key for d in values if d.get('isAvailable')]
    if not candidates:
        raise SystemExit(f'No available {runtime} simulator; install its runtime in Xcode')
    # Prefer an already initialized device to avoid first-boot migration costs.
    device = max(candidates, key=lambda item: (item['state'] == 'Booted', item.get('dataPathSize', 0)))
    udid = device['udid']
    booted_here = device['state'] != 'Booted'
    launched = False
    try:
        if booted_here:
            run('xcrun', 'simctl', 'boot', udid)
        run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=300)
        run('xcrun', 'simctl', 'install', udid, str(app), timeout=180)
        launch = run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, bundle_id, capture_output=True, timeout=90)
        print(launch.stdout, end='', flush=True)
        launched = True
        time.sleep(5)
        processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list', capture_output=True).stdout
        running = [line for line in processes.splitlines() if bundle_id in line and re.match(r'\d+\s', line)]
        if not running:
            raise SystemExit(f'{scheme} exited during launch smoke test')
        try:
            run('xcrun', 'simctl', 'io', udid, 'screenshot', str(output / 'launch.png'), timeout=30)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            print(f'Launch passed; optional screenshot unavailable: {error}', flush=True)
        print(f'Launch verified on {device["name"]}: {running[0]}')
    finally:
        cleanup = []
        if launched:
            cleanup.append(['xcrun', 'simctl', 'terminate', udid, bundle_id])
        if booted_here:
            cleanup.append(['xcrun', 'simctl', 'shutdown', udid])
        for command in cleanup:
            try:
                subprocess.run(command, capture_output=True, timeout=30)
            except subprocess.TimeoutExpired:
                print(f'Simulator cleanup timed out: {command}', flush=True)


if __name__ == '__main__':
    main()
