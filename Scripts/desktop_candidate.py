"""Integrity checks for explicitly selected local desktop runtime candidates.

Checksums detect stale/mixed build payloads; they are not a publisher signature.
The staging command separately audits Mach-O binaries before generating the manifest.
"""
import hashlib
import json
from pathlib import Path
import plistlib
import sys


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def payload_files(root):
    files = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError(f'Symlink in desktop candidate: {path.relative_to(root)}')
        if path.is_file() and path != root / 'PROVENANCE.json':
            files[str(path.relative_to(root))] = digest(path)
    return files


def validate(root):
    root = Path(root)
    if root.is_symlink() or (root / 'PROVENANCE.json').is_symlink():
        raise ValueError('Desktop candidate directory or manifest cannot be a symlink')
    metadata = json.loads((root / 'PROVENANCE.json').read_text())
    if metadata.get('schema') != 1 or metadata.get('kind') != 'trunkline-desktop-candidate':
        raise ValueError('Unsupported desktop candidate manifest')
    if not metadata.get('version') or metadata['version'] == '0.0.0':
        raise ValueError('Desktop candidate has no release version')
    if metadata.get('files') != payload_files(root):
        raise ValueError('Desktop candidate files do not match their provenance manifest')
    if not (root / 'ThirdParty/NOTICES.txt').is_file():
        raise ValueError('Desktop candidate notices are missing')
    architectures = metadata.get('architectures', ['arm64', 'x86_64'])
    if not architectures or not set(architectures) <= {'arm64', 'x86_64'}:
        raise ValueError('Invalid desktop candidate architectures')
    for arch in architectures:
        bundle = root / arch / 'Sunshine.app/Contents'
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        if info.get('CFBundleShortVersionString') != metadata['version']:
            raise ValueError(f'{arch} engine version differs from its provenance')
        for relative in ['MacOS/Sunshine', 'Resources/assets/apps.json', 'Resources/assets/web/index.html']:
            if not (bundle / relative).is_file():
                raise ValueError(f'Incomplete {arch} engine bundle: {relative}')
    return metadata


if __name__ == '__main__':
    try:
        validate(Path(sys.argv[1]))
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'Desktop candidate rejected: {error}')
