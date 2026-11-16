#!/usr/bin/env python3
"""Fail if tracked files include private/generated data or oversized artifacts."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
files = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode().split('\0')
forbidden = {'.build', 'target', 'Private', 'Local', 'Applications', 'dist', 'node_modules', 'xcuserdata', '__pycache__'}
failures = []
for name in filter(None, files):
    path = root / name
    if forbidden.intersection(Path(name).parts) or name in {'Config/Local.xcconfig', 'Config/Generated.xcconfig'}:
        failures.append(f'Private/generated file: {name}')
    if path.suffix in {'.p12', '.pem', '.mobileprovision', '.log', '.pyc'}:
        failures.append(f'Private/build artifact: {name}')
    if path.is_symlink():
        if not path.resolve().is_relative_to(root.resolve()): failures.append(f'External symlink: {name}')
    elif path.stat().st_size > 10 * 1024 * 1024:
        failures.append(f'File exceeds 10 MiB source limit: {name}')
if failures:
    sys.exit('\n'.join(failures))
print(f'Public source policy passed for {len(files) - 1} tracked files.')
