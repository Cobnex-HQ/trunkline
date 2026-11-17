#!/usr/bin/env python3
"""Fetch checksum-pinned build inputs. Never overwrite an existing dependency tree."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def verify_sha256(path, expected):
    if digest(path) != expected:
        raise ValueError(f'Checksum mismatch: {path}. Inspect the cache; nothing was overwritten.')


def verify_sdk_signature(framework, team):
    """Require the pinned publisher's Apple signature without modifying SDK bytes."""
    import re
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Invalid SDK signing team')
    requirement = f'anchor apple generic and certificate leaf[subject.OU] = "{team}"'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '-R', '=' + requirement,
                    str(framework)], check=True, capture_output=True)


def verify_git_files(root, entries):
    for item in entries:
        data = (root / item['path']).read_bytes()
        actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if actual != item['sha']:
            raise ValueError(f'Pinned source changed: {root / item["path"]}')


def verify_files(root, files):
    for relative, expected in files.items():
        verify_sha256(root / relative, expected)


def download(root, url, sha):
    cache = root / '.build/downloads'
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / sha
    if not path.exists():
        print(f'Downloading {url}', flush=True)
        with tempfile.TemporaryDirectory(dir=cache) as temporary:
            pending = Path(temporary) / 'download'
            subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--connect-timeout', '30',
                            '--max-time', '900', '--output', str(pending), url], check=True)
            verify_sha256(pending, sha)
            pending.replace(path)
    verify_sha256(path, sha)
    return path


def extract_source(archive, destination):
    with tarfile.open(archive) as source:
        members = source.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                raise ValueError(f'Unsafe source archive member: {member.name}')
        source.extractall(destination, members=members)


def source_tree(root, repository, revision, sha, destination):
    if destination.exists():
        return
    archive = download(root, f'https://api.github.com/repos/{repository}/tarball/{revision}', sha)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        extract_source(archive, Path(temporary))
        entries = list(Path(temporary).iterdir())
        if len(entries) != 1 or not entries[0].is_dir():
            raise ValueError('Expected a single source root')
        entries[0].rename(destination)


def bootstrap(root, check=False):
    records = root / 'Dependencies'
    sources = json.loads((records / 'streaming-sources.json').read_text())
    hashes = sources['downloadedArchives']
    vendor = root / 'Vendor'
    client = vendor / 'MoonlightSource'
    if not check:
        # Stage complete source trees before making them visible to Xcode.
        if not client.exists():
            vendor.mkdir(exist_ok=True)
            with tempfile.TemporaryDirectory(prefix='client-', dir=vendor) as temporary:
                tree = Path(temporary) / 'source'
                source_tree(root, 'moonlight-stream/moonlight-ios', sources['moonlightIOS']['revision'], hashes['moonlight-ios'], tree)
                core = tree / 'moonlight-common/moonlight-common-c'
                core.mkdir(parents=True, exist_ok=True)
                shutil.copytree(vendor / 'MoonlightCore', core, dirs_exist_ok=True)
                x1 = tree / 'X1Kit'
                if x1.exists() and not any(x1.iterdir()): x1.rmdir()
                source_tree(root, 'cgutman/X1Kit', sources['moonlightIOS']['submodules']['X1Kit'], hashes['moonlight-x1kit'], x1)
                verify_files(tree, json.loads((records / 'client-files.json').read_text()))
                tree.rename(client)
        source_tree(root, sources['sunshine']['repository'].removeprefix('https://github.com/'), sources['sunshine']['revision'], hashes['sunshine'], vendor / 'SunshineSource')
    verify_git_files(vendor / 'MoonlightCore', sources['moonlightCore']['files'])
    verify_files(vendor / 'SwiftTerm', json.loads((records / 'swiftterm-files.json').read_text()))
    verify_files(client, json.loads((records / 'client-files.json').read_text()))
    openssl = json.loads((records / 'openssl.json').read_text())
    destination = vendor / 'OpenSSL'
    if not check and not destination.exists():
        archive = download(root, openssl['url'], openssl['sha256'])
        # ditto preserves framework symlinks; validate member paths before invoking it.
        with zipfile.ZipFile(archive) as zipped:
            for entry in zipped.infolist():
                name = PurePosixPath(entry.filename)
                if name.is_absolute() or '..' in name.parts:
                    raise ValueError('Unsafe XCFramework archive path')
                if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    link = PurePosixPath(zipped.read(entry).decode())
                    if link.is_absolute() or '..' in link.parts:
                        raise ValueError('Unsafe XCFramework symlink')
        with tempfile.TemporaryDirectory(prefix='openssl-', dir=vendor) as temporary:
            pending = Path(temporary) / 'payload'; pending.mkdir()
            subprocess.run(['ditto', '-x', '-k', str(archive), str(pending)], check=True)
            framework = pending / 'OpenSSL.xcframework'
            verify_sdk_signature(framework, openssl['signingTeam'])
            verify_files(pending, openssl['files'])
            shutil.copyfile(records / 'openssl.json', pending / 'PROVENANCE.json')
            pending.rename(destination)
    verify_files(destination, openssl['files'])
    verify_sdk_signature(destination / 'OpenSSL.xcframework', openssl['signingTeam'])
    print('Verified pinned client sources, libraries, terminal and crypto framework.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify without downloading')
    parser.add_argument('--root', type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try: bootstrap(args.root.resolve(), args.check)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Dependency preparation failed: {error}')
