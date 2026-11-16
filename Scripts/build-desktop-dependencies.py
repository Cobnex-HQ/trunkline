#!/usr/bin/env python3
"""Fetch pinned dependencies and build static macOS desktop libraries.

Outputs stay in .build. This never changes an installed application.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / '.build/desktop-dependencies'


@contextmanager
def source_lock(destination):
    """Serialize preparation shared by simultaneous architecture builds."""
    lock = destination.with_suffix('.lock')
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('a+') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def verified_archive(item):
    """Download atomically and verify the lockfile digest even on a cache hit."""
    archive = BASE / 'archives' / Path(urlparse(item['url']).path).name
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        with tempfile.TemporaryDirectory(dir=archive.parent) as directory:
            pending = Path(directory) / archive.name
            subprocess.run(['curl', '--fail', '--location', '--retry', '3',
                            '--connect-timeout', '30', '--max-time', '900',
                            '--output', str(pending), item['url']], check=True)
            verify_digest(pending, item['sha256'])
            pending.replace(archive)
    verify_digest(archive, item['sha256'])
    return archive


def verify_digest(path, expected):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f'Checksum mismatch: {path}; cache was left untouched.')


def extract_archive(archive, destination):
    """Reject links, devices and path escapes before extracting any member."""
    with tarfile.open(archive) as source:
        members = source.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                raise ValueError(f'Unsafe archive member: {member.name}')
        source.extractall(destination, members=members)


def prepare_sources(item):
    archive = verified_archive(item)
    # A dedicated digest-addressed tree avoids trusting another build's sources.
    destination = BASE / 'verified-sources' / item['sha256']
    marker = destination / '.complete'
    with source_lock(destination):
        if not marker.exists():
            with tempfile.TemporaryDirectory(dir=destination.parent) as directory:
                pending = Path(directory) / 'source'
                pending.mkdir()
                extract_archive(archive, pending)
                (pending / '.complete').write_text(item['sha256'])
                if destination.exists():
                    raise ValueError(f'Incomplete source tree exists: {destination}; inspect it before retrying.')
                pending.rename(destination)
    return destination


def patch_opus(source):
    patch = ROOT / 'Engines/Desktop/Patches/opus-presumed-neon.patch'
    command = ['git', '-C', str(source), 'apply']
    with source_lock(source.parent):
        if subprocess.run([*command, '--reverse', '--check', str(patch)],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            subprocess.run([*command, '--check', str(patch)], check=True)
            subprocess.run([*command, str(patch)], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('architecture', choices=['arm64', 'x86_64'])
    parser.add_argument('--only', choices=['openssl', 'opus', 'miniupnpc', 'ffmpeg'])
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    arch = args.architecture
    lock = json.loads((ROOT / 'Engines/Desktop/dependencies.json').read_text())
    minimum = lock['minimum_macos']
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    prefix = BASE / 'install' / arch
    env = os.environ.copy()
    env.update(MACOSX_DEPLOYMENT_TARGET=minimum, SDKROOT=sdk,
               CC='/usr/bin/clang', CXX='/usr/bin/clang++')
    for item in lock['dependencies']:
        name = item['name']
        if args.only and name != args.only:
            continue
        source = prepare_sources(item) / f"{name}-{item['version']}"
        if name == 'opus':
            patch_opus(source)
        build = ROOT / f'.build/cmake-build-desktop-static-{arch}' / name
        build.mkdir(parents=True, exist_ok=True)
        print(f'Building {name} for {arch}, macOS {minimum}', flush=True)
        if name == 'openssl':
            target = 'darwin64-arm64-cc' if arch == 'arm64' else 'darwin64-x86_64-cc'
            subprocess.run(['perl', str(source / 'Configure'), target, 'no-shared',
                            'no-tests', 'no-module', 'no-autoload-config', f'--prefix={prefix}',
                            f'-mmacosx-version-min={minimum}'], cwd=build, env=env, check=True)
            subprocess.run(['make', f'-j{args.jobs}'], cwd=build, env=env, check=True)
            subprocess.run(['make', 'install_sw'], cwd=build, env=env, check=True)
        else:
            flags = (['-DBUILD_SHARED_LIBS=OFF', '-DOPUS_BUILD_SHARED_LIBRARY=OFF',
                      '-DOPUS_BUILD_TESTING=OFF', '-DOPUS_BUILD_PROGRAMS=OFF'] if name == 'opus' else
                     ['-DUPNPC_BUILD_STATIC=ON', '-DUPNPC_BUILD_SHARED=OFF',
                      '-DUPNPC_BUILD_TESTS=OFF', '-DUPNPC_BUILD_SAMPLE=OFF'])
            if name == 'opus' and arch == 'arm64':
                flags += ['-DOPUS_MAY_HAVE_NEON=ON', '-DOPUS_PRESUME_NEON=ON']
            processor = 'aarch64' if arch == 'arm64' else arch
            subprocess.run(['cmake', '-S', str(source), '-B', str(build),
                            '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_SYSTEM_NAME=Darwin',
                            f'-DCMAKE_SYSTEM_PROCESSOR={processor}', f'-DCMAKE_INSTALL_PREFIX={prefix}',
                            f'-DCMAKE_OSX_ARCHITECTURES={arch}', f'-DCMAKE_OSX_DEPLOYMENT_TARGET={minimum}',
                            f'-DCMAKE_OSX_SYSROOT={sdk}', *flags], env=env, check=True)
            subprocess.run(['cmake', '--build', str(build), f'-j{args.jobs}'], env=env, check=True)
            subprocess.run(['cmake', '--install', str(build)], env=env, check=True)
    if args.only in (None, 'ffmpeg'):
        source = prepare_sources(lock['ffmpeg']['architectures'][arch]) / 'ffmpeg'
        destination = BASE / 'ffmpeg' / arch / 'ffmpeg'
        shutil.copytree(source, destination, dirs_exist_ok=True)
    print(f'Dependencies ready: {prefix}', flush=True)


if __name__ == '__main__':
    main()
