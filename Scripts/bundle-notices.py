#!/usr/bin/env python3
"""Bundle original attribution, licenses and pinned dependency provenance."""
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(os.environ['SRCROOT'])
out = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['UNLOCALIZED_RESOURCES_FOLDER_PATH'] / 'ThirdParty'
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
entries = []

def copy_notices(source, label):
    for path in sorted(source.rglob('*')):
        if not path.is_file() or path.is_symlink(): continue
        if path.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE')):
            relative = Path(label) / path.relative_to(source)
            destination = out / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
            entries.append(str(relative))

copy_notices(root / 'Vendor', 'Vendor')
copy_notices(root / 'Apps/macOS/Resources', 'Trunkline')
shutil.copyfile(root / 'LICENSE', out / 'Trunkline-LICENSE.txt')
shutil.copyfile(root / 'docs/THIRD_PARTY.md', out / 'THIRD_PARTY.md')
# Include licenses of the locked Rust dependency graph in both app bundles.
metadata = json.loads(subprocess.check_output([
    os.environ.get('TRUNKLINE_CARGO') or shutil.which('cargo') or str(Path.home() / '.cargo/bin/cargo'), 'metadata', '--locked', '--offline', '--format-version', '1',
    '--manifest-path', str(root / 'Packages/Transport/Cargo.toml')]))
packages = []
for package in metadata['packages']:
    packages.append({k: package.get(k) for k in ('name', 'version', 'license', 'repository')})
    if package['source']:
        copy_notices(Path(package['manifest_path']).parent, 'Rust/' + package['name'] + '-' + package['version'])
(out / 'Rust-dependencies.json').write_text(json.dumps(packages, indent=2) + '\n')
(out / 'NOTICES.txt').write_text('Trunkline third-party notices\n\n'
    'Desktop engine: Sunshine (LizardByte), GPL-3.0.\n'
    'Streaming client: Moonlight iOS and moonlight-common-c, GPL-3.0.\n'
    'Other libraries retain the licenses below. See THIRD_PARTY.md for revisions and source information.\n\n'
    + '\n'.join(entries) + '\n')
print(f'Bundled {len(entries)} third-party notice files')
