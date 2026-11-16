#!/usr/bin/env python3
"""Stage audited local engine builds without changing Vendor or installed apps.

This produces a development candidate, not a public release or a claim of complete
corresponding source. Pass its path explicitly to the Xcode build for validation.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from desktop_candidate import digest, payload_files, validate


def notices(source, output):
    count = 0
    for path in sorted(source.rglob('*')):
        if any(part in {'.git', 'node_modules', '__pycache__'} for part in path.relative_to(source).parts):
            continue
        if path.is_file() and not path.is_symlink() and path.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')):
            target = output / path.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            count += 1
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arm64-log', type=Path)
    parser.add_argument('--x86_64-log', type=Path)
    parser.add_argument('--architectures', nargs='+', choices=['arm64', 'x86_64'], default=['arm64', 'x86_64'])
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    destination = args.output.absolute()
    if destination.exists():
        raise ValueError(f'Refusing to replace existing candidate: {destination}')
    release = json.loads((root / 'Engines/Desktop/release.json').read_text())
    lock = json.loads((root / 'Engines/Desktop/dependencies.json').read_text())
    source = root / '.build/upstream/sunshine'
    sources = [('engine', source, release['upstream_revision']),
               ('input', source / 'third-party/libvirtualhid', release['input_revision'])]
    for name, tree, revision in sources:
        actual = subprocess.check_output(['git', '-C', str(tree), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != revision:
            raise ValueError(f'{name} source revision differs from the release manifest')
    audits = {}
    for arch in args.architectures:
        supplied_log = getattr(args, arch + '_log')
        if supplied_log is None: parser.error(f'--{arch}-log is required for {arch}')
        log = supplied_log.absolute()
        audits[arch] = json.loads(subprocess.check_output([
            'python3', str(root / 'Scripts/audit-desktop-release.py'), arch, '--log', str(log)], text=True))
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='desktop-stage-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'runtime'; stage.mkdir()
        third_party = stage / 'ThirdParty'; third_party.mkdir()
        for arch in args.architectures:
            build = root / f'.build/cmake-build-desktop-release-{arch}'
            bundle = stage / arch / 'Sunshine.app'
            shutil.copytree(build / 'Sunshine.app', bundle)
            # CMake's post-link copy may predate the separately generated Web UI.
            shutil.copytree(build / 'assets', bundle / 'Contents/Resources/assets', dirs_exist_ok=True)
            # CMake installs platform defaults separately from the compiled bundle.
            shutil.copytree(source / 'src_assets/macos/assets', bundle / 'Contents/Resources/assets', dirs_exist_ok=True)
            if digest(bundle / 'Contents/MacOS/Sunshine') != audits[arch]['binary_sha256']:
                raise ValueError('Engine changed during staging')
            (third_party / f'{arch}-audit.json').write_text(json.dumps(audits[arch], indent=2) + '\n')
        notice_counts = {'engine': notices(source, third_party / 'Engine')}
        for item in lock['dependencies']:
            tree = root / '.build/desktop-dependencies/verified-sources' / item['sha256']
            count = notices(tree, third_party / item['name'])
            if not count: raise ValueError(f'Missing notices for {item["name"]}')
            notice_counts[item['name']] = count
        for name in ['boost', 'json']:
            tree = root / f'.build/cmake-build-desktop-release-{args.architectures[0]}/_deps/{name}-src'
            count = notices(tree, third_party / name)
            if not count: raise ValueError(f'Missing notices for {name}')
            notice_counts[name] = count
        shutil.copytree(root / 'Engines/Desktop', third_party / 'BuildRecipe')
        for name, tree, _ in sources:
            # Preserve actual local changes, including anything not represented
            # by a named patch. This is evidence, not a source-completeness claim.
            diff = subprocess.check_output(['git', '-C', str(tree), 'diff', '--binary', '--ignore-submodules=all', 'HEAD'])
            (third_party / f'{name}-source-changes.patch').write_bytes(diff)
        (third_party / 'NOTICES.txt').write_text(
            'Trunkline Desktop local development candidate\n\n'
            'Based on Sunshine (LizardByte), GPL-3.0, with modified macOS capture/input.\n'
            'Original notices and exact local source changes accompany this candidate.\n'
            'OpenSSL, Opus, miniupnpc, Boost and nlohmann/json notices match the prepared source trees.\n'
            'This is not approved for public distribution. Codec corresponding-source and notices,\n'
            'public-release attribution and physical streaming validation remain release gates.\n')
        metadata = {'schema': 1, 'kind': 'trunkline-desktop-candidate', **release,
                    'dependencies': lock, 'notice_counts': notice_counts,
                    'audits': audits, 'architectures': args.architectures, 'files': payload_files(stage)}
        (stage / 'PROVENANCE.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
        validate(stage)
        stage.rename(destination)
    print(destination)


if __name__ == '__main__':
    main()
