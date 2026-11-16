#!/usr/bin/env python3
"""Bundle original attribution and report gaps; this is not release clearance."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

root = Path(os.environ['SRCROOT'])
out = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH'] / 'ThirdParty'
required = json.loads((root / 'Dependencies/required-notices.json').read_text())
# Check mandatory originals before replacing any existing notice collection.
for item in required:
    path = root / item['path']
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Required notice must be inside the checkout')
    if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
        raise ValueError(f'Required notice changed: {item["path"]}; review its upstream terms before updating the manifest.')
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
entries = set()


def copy_file(path, relative):
    destination = out / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
    entries.add(str(relative))
    return str(relative)


def copy_notices(source, label):
    copied = []
    for path in sorted(source.rglob('*')):
        if not path.is_file() or path.is_symlink(): continue
        if any(part in {'.git', 'node_modules', '__pycache__', 'target'} for part in path.relative_to(source).parts): continue
        # Covers LICENSE-MIT, macowl-LICENSE.txt and SDL_copying.h.
        if re.search(r'(^|[._\s-])(LICENSE|LICENCE|COPYING|NOTICE)([._\s-]|$)', path.name.upper()):
            copied.append(copy_file(path, Path(label) / path.relative_to(source)))
    return copied


copy_notices(root / 'Vendor', 'Vendor')
copy_notices(root / 'Apps/macOS/Resources', 'Trunkline')
copy_notices(root / 'Apps/iOS/Resources', 'Trunkline-iOS')
copy_notices(root / 'Licenses', 'Licenses')
for item in required:
    copy_file(root / item['path'], Path(item['path']))
copy_file(root / 'LICENSE', Path('Trunkline-LICENSE.txt'))
copy_file(root / 'docs/THIRD_PARTY.md', Path('THIRD_PARTY.md'))
copy_file(root / 'Dependencies/required-notices.json', Path('required-notices.json'))
# This is the full locked graph, including build and other-platform dependencies,
# not a claim that every crate is linked into each target.
metadata = json.loads(subprocess.check_output([
    os.environ.get('TRUNKLINE_CARGO') or shutil.which('cargo') or str(Path.home() / '.cargo/bin/cargo'), 'metadata', '--locked', '--offline', '--format-version', '1',
    '--manifest-path', str(root / 'Packages/Transport/Cargo.toml')]))
packages = []
review = []
for package in metadata['packages']:
    record = {k: package.get(k) for k in ('name', 'version', 'license', 'repository')}
    if package['source']:
        source = Path(package['manifest_path']).parent
        label = 'Rust/' + package['name'] + '-' + package['version']
        files = copy_notices(source, label)
        if package.get('license_file'):
            path = (source / package['license_file']).resolve()
            if not path.is_relative_to(source.resolve()):
                raise ValueError(f'Cargo licence file outside package: {package["name"]}')
            files.append(copy_file(path, Path(label) / path.relative_to(source.resolve())))
        record['notice_files'] = sorted(set(files))
        record['notice_status'] = 'files-collected' if files else 'review-required'
        if not files or not (package.get('license') or package.get('license_file')):
            review.append({'name': package['name'], 'version': package['version'],
                           'reason': 'Missing standalone notice or licence metadata; inspect exact upstream source/headers and target usage.'})
    packages.append(record)
(out / 'Rust-dependencies.json').write_text(json.dumps(packages, indent=2) + '\n')
(out / 'NOTICE-REVIEW.json').write_text(json.dumps(review, indent=2) + '\n')
(out / 'NOTICES.txt').write_text('Trunkline third-party notices\n\n'
    'Desktop engine: Sunshine contributors (including LizardByte), GPL-3.0.\n'
    'Streaming client: Moonlight iOS and moonlight-common-c contributors, GPL-3.0 with the retained App Store exception.\n'
    'Other libraries retain the licences below. See THIRD_PARTY.md for revisions and source information.\n'
    'NOTICE-REVIEW.json lists unresolved Cargo notice collection. Files collected does not mean licence compliance verified.\n'
    'The inventory covers the full locked graph, not only target-linked code.\n\n'
    + '\n'.join(sorted(entries)) + '\n')
print(f'Bundled {len(entries)} third-party notice files; {len(review)} Rust packages need notice review')
