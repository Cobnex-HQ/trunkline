#!/usr/bin/env python3
"""Prepare a pinned experimental engine checkout; never modify bundled runtimes."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / '.build/upstream/sunshine'
REVISION = '63d35f702ee9e362e43263742981836ec0710384'
INPUT_REVISION = '53e1a949fc0784af716b782ddfa6c647cafd1f05'

def git(path, *args, capture=False):
    return subprocess.run(['git', '-C', str(path), *args], check=True,
                          text=True, stdout=subprocess.PIPE if capture else None)

def apply_patch(path, name):
    patch = ROOT / 'Engines/Desktop/Patches' / name
    reverse = subprocess.run(['git', '-C', str(path), 'apply', '--reverse', '--check', str(patch)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if reverse.returncode == 0:
        print(f'Already applied: {name}', flush=True)
        return
    git(path, 'apply', '--check', str(patch))
    git(path, 'apply', str(patch))

if not (SOURCE / '.git').exists():
    if SOURCE.exists():
        raise SystemExit(f'Refusing to overwrite non-checkout directory: {SOURCE}')
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'clone', '--filter=blob:none', '--no-checkout',
                    'https://github.com/SunshineStream/Sunshine.git', str(SOURCE)], check=True)
    git(SOURCE, 'checkout', '--detach', REVISION)
if git(SOURCE, 'rev-parse', 'HEAD', capture=True).stdout.strip() != REVISION:
    raise SystemExit('Engine checkout is at another revision; leaving it untouched.')

# The build-deps lock selects downloadable FFmpeg binaries. Do not recursively
# fetch its unrelated codec source trees. The desktop build disables tray UI.
git(SOURCE, 'submodule', 'update', '--init', 'third-party/build-deps')
git(SOURCE, 'submodule', 'update', '--init', '--recursive',
    'third-party/libvirtualhid', 'third-party/libdisplaydevice',
    'third-party/lizardbyte-common', 'third-party/moonlight-common-c',
    'third-party/Simple-Web-Server', 'third-party/TPCircularBuffer')
input_source = SOURCE / 'third-party/libvirtualhid'
if git(input_source, 'rev-parse', 'HEAD', capture=True).stdout.strip() != INPUT_REVISION:
    raise SystemExit('Input dependency revision does not match the reviewed patch.')
apply_patch(input_source, 'macos-pointer.patch')
apply_patch(SOURCE, 'macos-capture-geometry.patch')
apply_patch(SOURCE, 'macos-display-selection.patch')
apply_patch(SOURCE, 'macos-adaptive-quality.patch')
apply_patch(SOURCE, 'macos-geometry-tests.patch')
apply_patch(SOURCE, 'macos-dependency-linking.patch')
print(f'Prepared experimental source: {SOURCE}\nInstalled apps and Vendor runtimes are unchanged.')
