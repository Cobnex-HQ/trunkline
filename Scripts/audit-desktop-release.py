#!/usr/bin/env python3
"""Audit an experimental engine binary and its complete build log before staging."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re

from distribution import dependencies, run, verify_macos_deployment


def audit_link_warnings(log, architecture, codec_directory):
    """Allow only missing platform metadata in the pinned Intel codec archives.

    NASM objects in that upstream artifact have no deployment load command.
    A newer deployment target, wrong architecture, missing symbol or any other
    linker warning must not be accepted as another instance of that exception.
    """
    accepted = []
    libraries = '(?:libavcodec|libavutil|libswscale|libx264|libx265|libSvtAv1Enc)'
    allowed = (r"ld: warning: no platform load command found in '" + re.escape(str(codec_directory)) +
               '/' + libraries + r"\.a\[\d+\]\([^\n']+\.o\)', assuming: macOS")
    for line in log.splitlines():
        if 'ld: warning:' not in line:
            continue
        if architecture != 'x86_64' or not re.fullmatch(allowed, line):
            raise ValueError(f'Unreviewed linker warning: {line}')
        accepted.append(line)
    return accepted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('architecture', choices=['arm64', 'x86_64'])
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    lock = json.loads((root / 'Engines/Desktop/dependencies.json').read_text())
    arch = args.architecture
    build = root / f'.build/cmake-build-desktop-release-{arch}'
    binary = build / 'Sunshine.app/Contents/MacOS/Sunshine'
    release = json.loads((root / 'Engines/Desktop/release.json').read_text())
    info = plistlib.loads((build / 'Sunshine.app/Contents/Info.plist').read_bytes())
    if info.get('CFBundleShortVersionString') != release['version']:
        raise ValueError('Engine bundle does not have the configured Trunkline release version')
    if binary.stat().st_mtime_ns > args.log.stat().st_mtime_ns:
        raise ValueError('Binary is newer than its build log; build evidence is stale')
    log = args.log.read_text()
    if 'Built target sunshine' not in log or re.search(r'(?m)^.*(?:error:|\*\*\* .*Error \d)', log):
        raise ValueError('Build log is incomplete or reports a failed build; refusing a potentially stale binary')
    warnings = audit_link_warnings(log, arch,
                                  root / '.build/desktop-dependencies/ffmpeg' / arch / 'ffmpeg/lib')
    if set(run('lipo', '-archs', str(binary)).split()) != {arch}:
        raise ValueError('Engine architecture does not match its package directory')
    verify_macos_deployment(binary, lock['minimum_macos'])
    linked = dependencies(run('otool', '-L', str(binary)))
    for dependency in linked:
        if not dependency.startswith(('/usr/lib/', '/System/Library/')):
            raise ValueError(f'Unbundled or unexpected runtime dependency: {dependency}')
    print(json.dumps({
        'architecture': arch,
        'version': release['version'],
        'minimum_macos': lock['minimum_macos'],
        'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'system_dependencies': linked,
        'intel_codec_objects_without_platform_metadata': len(warnings),
        'scope': 'Binary and link-log audit; not signing, physical streaming or macOS 15 runtime validation',
    }, indent=2))


if __name__ == '__main__':
    main()
