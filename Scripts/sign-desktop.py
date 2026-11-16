#!/usr/bin/env python3
"""Sign nested Sunshine code from leaves to app bundle, before signing the outer app."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY') or os.environ.get('TRUNKLINE_SIGNING_IDENTITY')
if not identity:
    raise SystemExit('A signing identity is required to sign bundled Sunshine code.')
magic = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
flags = ['--force', '--sign', identity]
if identity != '-':
    timestamp = '--timestamp=none' if os.environ.get('EXPANDED_CODE_SIGN_IDENTITY_NAME', '').startswith('Apple Development:') else '--timestamp'
    flags += [timestamp, '--options', 'runtime']
for app in sorted(root.glob('*/TrunklineDesktop.app')):
    binaries = []
    for path in app.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as handle:
                if handle.read(4) in magic:
                    binaries.append(path)
    for path in sorted(binaries, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(['codesign', *flags, str(path)], check=True)
    for framework in sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
        subprocess.run(['codesign', *flags, str(framework)], check=True)
    subprocess.run(['codesign', *flags, str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
