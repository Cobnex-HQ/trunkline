#!/usr/bin/env python3
"""Configure an isolated desktop engine using prepared, macOS 15 dependencies.

This does not replace the installed host or its bundled runtime.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('architecture', choices=['arm64', 'x86_64'])
    parser.add_argument('--tests', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    base = root / '.build/desktop-dependencies'
    prefix = base / 'install' / args.architecture
    lock = json.loads((root / 'Engines/Desktop/dependencies.json').read_text())
    release = json.loads((root / 'Engines/Desktop/release.json').read_text())
    minimum = lock['minimum_macos']
    sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip())
    for library in ['libssl.a', 'libcrypto.a', 'libopus.a', 'libminiupnpc.a']:
        if not (prefix / 'lib' / library).is_file():
            raise SystemExit(f'Missing prepared dependency: {prefix / "lib" / library}')

    # pkg-config must resolve Apple's curl, not a package manager's copy.
    pc = base / 'system-pkgconfig'
    pc.mkdir(parents=True, exist_ok=True)
    version = re.search(r'#define LIBCURL_VERSION "([^"]+)"',
                        (sdk / 'usr/include/curl/curlver.h').read_text()).group(1)
    (pc / 'libcurl.pc').write_text(
        f'Name: libcurl\nDescription: Apple SDK curl\nVersion: {version}\n'
        f'Libs: -L{sdk}/usr/lib -lcurl\nCflags:\n')
    env = os.environ.copy()
    env.update(PKG_CONFIG_PATH='', PKG_CONFIG_LIBDIR=f'{prefix}/lib/pkgconfig:{pc}',
               MACOSX_DEPLOYMENT_TARGET=minimum, SDKROOT=str(sdk),
               BRANCH='trunkline', BUILD_VERSION=release['version'],
               COMMIT=release['upstream_revision'], CLONE_URL=release['upstream_repository'], TAG='')
    build = root / f'.build/cmake-build-desktop-release-{args.architecture}'
    flags = {
        'CMAKE_BUILD_TYPE': 'Release',
        'CMAKE_SYSTEM_NAME': 'Darwin',
        'CMAKE_SYSTEM_PROCESSOR': args.architecture,
        'CMAKE_OSX_ARCHITECTURES': args.architecture,
        'CMAKE_OSX_DEPLOYMENT_TARGET': minimum,
        'CMAKE_OSX_SYSROOT': sdk,
        'CMAKE_PREFIX_PATH': prefix,
        'CMAKE_IGNORE_PREFIX_PATH': '/opt/homebrew;/opt/local;/usr/local',
        'CMAKE_C_COMPILER': '/usr/bin/clang',
        'CMAKE_CXX_COMPILER': '/usr/bin/clang++',
        # Intel's pinned NASM codec objects omit platform load commands. Keep
        # their diagnostics visible and audit the build log before packaging.
        'CMAKE_EXE_LINKER_FLAGS': ('-Wl,-no_warn_duplicate_libraries,-fatal_warnings'
                                 if args.architecture == 'arm64' else '-Wl,-no_warn_duplicate_libraries'),
        'BUILD_DOCS': 'OFF',
        'BUILD_TESTS': 'ON' if args.tests else 'OFF',
        'SUNSHINE_ENABLE_TRAY': 'OFF',
        'BOOST_USE_STATIC': 'ON',
        'OPENSSL_USE_STATIC_LIBS': 'TRUE',
        'OPENSSL_ROOT_DIR': prefix,
        'OPENSSL_SSL_LIBRARY': prefix / 'lib/libssl.a',
        'OPENSSL_CRYPTO_LIBRARY': prefix / 'lib/libcrypto.a',
        'OPENSSL_INCLUDE_DIR': prefix / 'include',
        'Opus_ROOT_DIR': prefix,
        'Opus_LIBRARY': prefix / 'lib/libopus.a',
        'Opus_INCLUDE_DIR': prefix / 'include',
        'FFMPEG_PREPARED_BINARIES': base / 'ffmpeg' / args.architecture / 'ffmpeg',
    }
    subprocess.run(['cmake', '-S', str(root / '.build/upstream/sunshine'), '-B', str(build),
                    *[f'-D{key}={value}' for key, value in flags.items()]], env=env, check=True)
    print(f'Configured {build}. Build targets sunshine and, if enabled, test_sunshine.')


if __name__ == '__main__':
    main()
