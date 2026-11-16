#!/usr/bin/env python3
"""Local distribution tools. No publishing, signing changes, or credential access."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tarfile
import tempfile

ROOTS = {'README.md', '.gitleaks.toml', 'LICENSE', 'COPYRIGHT', '.gitignore', '.gitattributes', '.editorconfig',
         'project.yml', 'Brewfile', 'Makefile', 'CONTRIBUTING.md', 'SECURITY.md', 'CODE_OF_CONDUCT.md',
         'CHANGELOG.md', 'AGENTS.md', '.github', 'Config', 'docs', 'Assets', 'Apps', 'Services',
         'Packages', 'Scripts', 'Tests', 'Dependencies', 'Engines', 'Vendor'}
EXCLUDED = {'.git', '.build', 'target', 'Private', '__pycache__', 'node_modules',
            'xcuserdata', '.DS_Store', 'Local.xcconfig', 'Generated.xcconfig', 'Toolchain.xcconfig', '.env'}


def source_files(root):
    root = root.absolute()
    if (root / '.git').exists():
        tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
        for name in filter(None, tracked):
            path = root / name
            if path.is_symlink() and not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'External symlink refused: {name}')
            yield path
        return
    for base, dirs, files in os.walk(root, followlinks=False):
        current = Path(base)
        dirs[:] = sorted(d for d in dirs if d not in EXCLUDED and (current != root or d in ROOTS))
        # Preserve framework symlinks, never follow them or export external data.
        for name in sorted(files + [d for d in dirs if (current / d).is_symlink()]):
            path = current / name
            if name in EXCLUDED or (current == root and name not in ROOTS): continue
            if path.suffix.lower() in {'.p12', '.pem', '.log', '.mobileprovision', '.xcuserstate', '.pyc'}: continue
            if path.is_symlink() and not path.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'External symlink refused: {path.relative_to(root)}')
            yield path


def export_source(root, destination):
    files = list(source_files(root))  # Validate everything before producing an archive.
    with tarfile.open(destination, 'x:gz', dereference=False) as archive:
        for path in files:
            info = archive.gettarinfo(str(path), arcname='Trunkline/' + str(path.relative_to(root)))
            info.uid = info.gid = 0; info.uname = info.gname = ''
            if info.isfile():
                with path.open('rb') as handle: archive.addfile(info, handle)
            else: archive.addfile(info)
    return len(files)


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def dependencies(output):
    return [line.strip().split(' (', 1)[0] for line in output.splitlines() if line[:1].isspace()]


def verify_macos_deployment(binary, minimum):
    """Check every Mach-O architecture's actual load command, not only Info.plist."""
    def version(value):
        parts = tuple(int(part) for part in value.split('.'))
        return parts + (0,) * (3 - len(parts))
    found = 0
    for command in run('xcrun', 'vtool', '-show-build', str(binary)).split('Load command')[1:]:
        if re.search(r'cmd LC_BUILD_VERSION\b', command):
            platform = re.search(r'platform (\w+)', command)
            if not platform or platform.group(1) != 'MACOS':
                raise ValueError(f'Non-macOS binary in host bundle: {binary}')
            deployment = re.search(r'\bminos ([0-9.]+)', command)
        elif re.search(r'cmd LC_VERSION_MIN_MACOSX\b', command):
            deployment = re.search(r'\bversion ([0-9.]+)', command)
        else:
            continue
        if not deployment:
            raise ValueError(f'Missing deployment version: {binary}')
        found += 1
        actual = deployment.group(1)
        if version(actual) > version(minimum):
            raise ValueError(f'{binary.name} requires macOS {actual}, above package minimum {minimum}')
    if found == 0:
        raise ValueError(f'No macOS deployment target found: {binary}')


def verify_mac(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    main = app / 'Contents/MacOS' / info['CFBundleExecutable']
    arches = set(run('lipo', '-archs', str(main)).split())
    helper = app / 'Contents/Helpers/TrunklineRemote'
    supervisor = app / 'Contents/Helpers/TrunklineDesktopSupervisor'
    for binary in (helper, supervisor):
        if not binary.is_file(): raise ValueError(f'Missing bundled helper: {binary.name}')
        if not arches <= set(run('lipo', '-archs', str(binary)).split()):
            raise ValueError(f'{binary.name} does not support all host architectures')
    for arch in arches:
        desktop = app / f'Contents/Helpers/Desktop/{arch}/TrunklineDesktop.app'
        metadata = plistlib.loads((desktop / 'Contents/Info.plist').read_bytes())
        if metadata.get('CFBundleDisplayName') != 'Trunkline Desktop':
            raise ValueError('Desktop helper is missing Trunkline branding')
        if not (desktop / 'Contents/MacOS' / metadata['CFBundleExecutable']).is_file():
            raise ValueError('Missing desktop engine')
        candidate = app / 'Contents/Resources/ThirdParty/DesktopCandidate/PROVENANCE.json'
        if candidate.is_file():
            provenance = json.loads(candidate.read_text())
            if metadata.get('CFBundleShortVersionString') != provenance.get('version'):
                raise ValueError('Bundled desktop candidate version differs from its provenance')
            if not (candidate.parent / 'NOTICES.txt').is_file():
                raise ValueError('Desktop candidate notices were not bundled')
    if not (app / 'Contents/Resources/ThirdParty/NOTICES.txt').is_file():
        raise ValueError('Third-party notices are missing')
    run('codesign', '--verify', '--deep', '--strict', str(app))
    magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
             b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink(): continue
        with path.open('rb') as file: header = file.read(4)
        if header not in magic: continue
        verify_macos_deployment(path, info['LSMinimumSystemVersion'])
        for dependency in dependencies(run('otool', '-L', str(path))):
            if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                raise ValueError(f'External runtime dependency in {path.name}: {dependency}')
    return {'version': info['CFBundleShortVersionString'], 'architectures': sorted(arches),
            'minimum_macos': info['LSMinimumSystemVersion']}


def package_mac(app, output):
    metadata = verify_mac(app)
    output.mkdir(parents=True, exist_ok=True)
    name = 'Trunkline-' + metadata['version'] + '-' + '-'.join(metadata['architectures']) + '-local'
    destination = output / (name + '.dmg')
    if destination.exists(): raise ValueError(f'Refusing to replace {destination}')
    with tempfile.TemporaryDirectory(prefix='trunkline-package-') as staging:
        stage = Path(staging)
        run('ditto', str(app), str(stage / 'Trunkline.app'))
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'Read Me.txt').write_text(
            'Trunkline\n\nQuit Trunkline, then drag Trunkline.app into Applications.\n'
            'All Mac engines are included. No separate engine installation is needed.\n'
            'Install the Trunkline iPhone/iPad app separately through Xcode.\n'
            'Complete macOS Screen Recording and Accessibility setup before leaving home.\n\n'
            'This local development package is not notarized for public distribution.\n'
            'Third-party licenses are inside Trunkline.app/Contents/Resources/ThirdParty.\n')
        run('hdiutil', 'create', '-quiet', '-volname', 'Trunkline', '-srcfolder', str(stage),
            '-format', 'UDZO', str(destination))
    run('hdiutil', 'verify', str(destination))
    metadata['sha256'] = hashlib.sha256(destination.read_bytes()).hexdigest()
    metadata['distribution'] = 'local development; not notarized'
    destination.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('mac'); p.add_argument('--app', type=Path, required=True); p.add_argument('--output', type=Path, default=Path('dist'))
    p = sub.add_parser('source'); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('verify'); p.add_argument('--app', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'mac': package_mac(args.app.resolve(), args.output.resolve())
        elif args.command == 'verify': print(json.dumps(verify_mac(args.app.resolve())))
        else: print(f'Exported {export_source(Path(__file__).resolve().parent.parent, args.output)} files to {args.output}')
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')
