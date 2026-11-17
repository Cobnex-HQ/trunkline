#!/usr/bin/env python3
"""Prepare App Store archives and notarized direct-download Mac releases.

No App Store upload or GitHub publication is performed. Credentials stay in Xcode
or a notarytool Keychain profile. The installed application is never modified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid

from distribution import verify_mac

ROOT = Path(__file__).resolve().parent.parent
MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
         b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
DEVELOPER_ID = 'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists'


def capture(*args):
    return subprocess.check_output([str(a) for a in args], text=True, stderr=subprocess.STDOUT)


def call(*args):
    subprocess.run([str(a) for a in args], check=True, cwd=ROOT)


def team_id(value):
    if not re.fullmatch(r'[A-Z0-9]{10}', value or ''):
        raise ValueError('Provide your ten-character Apple developer team ID with --team.')
    return value


def new_destination(path):
    if path.exists():
        raise ValueError(f'Refusing to replace existing output: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)


def archive_app(archive, require_signed=False):
    properties = plistlib.loads((archive / 'Info.plist').read_bytes()).get('ApplicationProperties', {})
    relative = Path(properties.get('ApplicationPath', ''))
    products = (archive / 'Products').resolve()
    app = (products / relative).resolve()
    if relative.is_absolute() or not app.is_relative_to(products) or app == products:
        raise ValueError('Archived app must remain inside the archive Products directory.')
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('Archive contains no application product.')
    if require_signed and properties.get('SigningIdentity', '') in ('', '-', 'Sign to Run Locally'):
        raise ValueError('A signed archive is required; unsigned validation archives cannot be distributed.')
    return app


def write_export_options(path, team):
    options = {'method': 'app-store-connect', 'destination': 'export', 'teamID': team_id(team),
               'signingStyle': 'automatic', 'uploadSymbols': True,
               'manageAppVersionAndBuildNumber': False}
    path.write_bytes(plistlib.dumps(options))


def build_archive(args):
    new_destination(args.output)
    command = ['xcodebuild', '-project', 'Trunkline.xcodeproj', '-scheme',
               'Trunkline' if args.platform == 'ios' else 'TrunklineHost',
               '-configuration', 'Release', '-destination',
               'generic/platform=iOS' if args.platform == 'ios' else 'generic/platform=macOS',
               '-archivePath', args.output, '-derivedDataPath', ROOT / '.build' / ('release-' + args.platform),
               'archive', 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO']
    if args.unsigned:
        command += ['CODE_SIGNING_ALLOWED=NO']
    else:
        command += ['DEVELOPMENT_TEAM=' + team_id(args.team), '-allowProvisioningUpdates']
        if args.platform == 'mac':
            if not (args.identity or '').startswith('Developer ID Application:'):
                raise ValueError('Mac distribution requires --identity "Developer ID Application: …".')
            command += ['CODE_SIGN_STYLE=Manual', 'CODE_SIGN_IDENTITY=' + args.identity]
        else:
            command += ['CODE_SIGN_STYLE=Automatic']
    if args.platform == 'mac':
        command += ['ARCHS=' + args.arch, 'ONLY_ACTIVE_ARCH=YES']
    call(*command)
    app = archive_app(args.output, require_signed=not args.unsigned)
    print(('Unsigned validation archive (not installable): ' if args.unsigned else 'Release archive: ') + str(app))


def ios_preflight(archive):
    result = subprocess.run([sys.executable, str(ROOT / 'Scripts/audit-ios.py'), '--archive', str(archive)],
                            capture_output=True, text=True)
    if result.returncode:
        try:
            findings = json.loads(result.stdout)['findings']
            detail = ', '.join(item['bundle'] + ': ' + item['code'] for item in findings)
        except (ValueError, KeyError):
            detail = result.stderr.strip() or 'Audit did not produce a report'
        raise ValueError('iOS export blocked by preflight: ' + detail)


def export_ios(archive, output, team):
    app = archive_app(archive, require_signed=True)
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('App Store companion export requires an iOS device archive.')
    ios_preflight(archive)
    new_destination(output)
    with tempfile.TemporaryDirectory(prefix='trunkline-export-') as temporary:
        options = Path(temporary) / 'ExportOptions.plist'
        write_export_options(options, team)
        call('xcodebuild', '-exportArchive', '-archivePath', archive, '-exportPath', output,
             '-exportOptionsPlist', options, '-allowProvisioningUpdates')
    print('Exported locally. Validate and upload using Xcode Organizer or Transporter after release review.')


def verify_developer_id(path):
    try:
        capture('codesign', '--verify', '--strict', '-R', '=' + DEVELOPER_ID, path)
    except subprocess.CalledProcessError as error:
        raise ValueError(f'Developer ID Application signature required: {path.name}') from error
    details = capture('codesign', '-d', '--verbose=4', path)
    team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', details, re.MULTILINE)
    if not team or not re.search(r'^Timestamp=.+', details, re.MULTILINE):
        raise ValueError(f'Developer ID team and secure timestamp required: {path.name}')
    executable = re.search(r'^Executable=(.+)$', details, re.MULTILINE)
    binary = executable.group(1) if executable else str(path)
    if 'EXECUTE' in capture('otool', '-hv', binary) and '(runtime)' not in details:
        raise ValueError(f'Hardened Runtime required: {path.name}')
    raw = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(path)], stderr=subprocess.DEVNULL)
    entitlements = plistlib.loads(raw) if raw.strip() else {}
    if entitlements.get('com.apple.security.get-task-allow') or entitlements.get('get-task-allow'):
        raise ValueError(f'Debugger entitlement is not allowed in a public release: {path.name}')
    return team.group(1)


def verify_public_mac(app):
    if list((app / 'Contents/MacOS').glob('*.debug.dylib')):
        raise ValueError('Use a Release archive; a Debug app cannot become a public release.')
    team = verify_developer_id(app)
    metadata = verify_mac(app)
    for path in app.rglob('*'):
        if not path.is_file() or path.is_symlink():
            continue
        with path.open('rb') as handle:
            magic = handle.read(4)
        if magic in MACHO and verify_developer_id(path) != team:
            raise ValueError(f'Nested code uses a different signing team: {path.name}')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', metadata['version']):
        raise ValueError('Release version must contain one to three numeric components.')
    return metadata


def accepted_notarization(result):
    if result.get('status') != 'Accepted':
        raise ValueError('Notarization has not been Accepted: ' + str(result.get('status', 'missing status')))
    try:
        identifier = str(uuid.UUID(result['id']))
    except (KeyError, ValueError, TypeError, AttributeError) as error:
        raise ValueError('Notarization response has no valid submission ID.') from error
    return identifier


def notarize(artifact, profile):
    result = subprocess.run(['xcrun', 'notarytool', 'submit', str(artifact), '--keychain-profile', profile,
                             '--wait', '--timeout', '20m', '--output-format', 'json'], capture_output=True, text=True)
    response = json.loads(result.stdout or '{}')
    reports = ROOT / '.build/notarization'; reports.mkdir(parents=True, exist_ok=True)
    report = reports / (str(uuid.uuid4()) + '.json')
    report.write_text(json.dumps(response, indent=2) + '\n')
    if response.get('id'):
        identifier = str(uuid.UUID(response['id']))
        log = capture('xcrun', 'notarytool', 'log', identifier, '--keychain-profile', profile)
        (reports / (identifier + '.log')).write_text(log)
        issues = json.loads(log).get('issues') or []
        print(f'Notary report: {reports / (identifier + ".log")} ({len(issues)} issues; review before publishing)')
    if result.returncode:
        raise ValueError(f'Notary submission failed; inspect {report} and your Keychain profile. {result.stderr.strip()}')
    return accepted_notarization(response)


def package_public_mac(archive, output, identity, profile):
    if not identity.startswith('Developer ID Application:'):
        raise ValueError('A Developer ID Application identity is required for the disk image.')
    app = archive_app(archive, require_signed=True)
    metadata = verify_public_mac(app)
    name = 'Trunkline-' + metadata['version'] + '-' + '-'.join(metadata['architectures'])
    destination = output / name
    new_destination(destination)
    with tempfile.TemporaryDirectory(prefix='.' + name + '-', dir=output) as temporary:
        stage = Path(temporary); payload = stage / 'Payload'; payload.mkdir()
        copied = payload / 'Trunkline.app'
        call('ditto', app, copied)
        zipped = stage / 'Trunkline.zip'
        call('ditto', '-c', '-k', '--keepParent', copied, zipped)
        metadata['app_notarization'] = notarize(zipped, profile)
        call('xcrun', 'stapler', 'staple', copied)
        call('xcrun', 'stapler', 'validate', copied)
        call('spctl', '--assess', '--type', 'execute', '--verbose=2', copied)
        (payload / 'Applications').symlink_to('/Applications')
        (payload / 'Read Me.txt').write_text(
            'Trunkline for Mac\n\nQuit Trunkline, then drag Trunkline.app into Applications.\n'
            'The desktop and connection engines are bundled.\n'
            'Install the companion separately through its App Store or TestFlight listing.\n'
            'Enable Screen Recording and Device Control and Data Access (Accessibility on earlier macOS).\n'
            'Open the Mac app and scan its pairing QR code from the companion.\n'
            'Test access locally before leaving the Mac unattended.\n'
            'Source and support: https://github.com/Cobnex-HQ/trunkline\n')
        ready = stage / 'Ready'; ready.mkdir()
        dmg = ready / (name + '.dmg')
        call('hdiutil', 'create', '-quiet', '-volname', 'Trunkline', '-srcfolder', payload, '-format', 'UDZO', dmg)
        call('codesign', '--force', '--sign', identity, '--timestamp', dmg)
        metadata['dmg_notarization'] = notarize(dmg, profile)
        call('xcrun', 'stapler', 'staple', dmg)
        call('xcrun', 'stapler', 'validate', dmg)
        call('hdiutil', 'verify', dmg)
        call('spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', dmg)
        metadata['sha256'] = hashlib.sha256(dmg.read_bytes()).hexdigest()
        metadata['distribution'] = 'Developer ID; notarized and stapled; release review still required'
        (ready / (name + '.json')).write_text(json.dumps(metadata, indent=2) + '\n')
        ready.rename(destination)
    print(destination / (name + '.dmg'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('archive'); p.add_argument('platform', choices=['ios', 'mac'])
    p.add_argument('--output', type=Path, required=True); p.add_argument('--team'); p.add_argument('--identity')
    p.add_argument('--unsigned', action='store_true', help='Compile-only validation; cannot be distributed')
    p.add_argument('--arch', choices=['arm64', 'x86_64'], default='arm64', help='Mac release architecture')
    p = sub.add_parser('ios-export'); p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True); p.add_argument('--team', required=True)
    p = sub.add_parser('mac'); p.add_argument('--archive', type=Path, required=True)
    p.add_argument('--output', type=Path, default=Path('dist')); p.add_argument('--identity', required=True)
    p.add_argument('--notary-profile', required=True, help='Existing notarytool Keychain profile; never a password')
    p = sub.add_parser('verify-mac'); p.add_argument('--app', type=Path, required=True)
    args = parser.parse_args()
    for key in ['output', 'archive', 'app']:
        if hasattr(args, key): setattr(args, key, getattr(args, key).resolve())
    try:
        if args.command == 'verify-mac': print(json.dumps(verify_public_mac(args.app)))
        elif args.command == 'archive': build_archive(args)
        elif args.command == 'ios-export': export_ios(args.archive, args.output, args.team)
        else: package_public_mac(args.archive, args.output, args.identity, args.notary_profile)
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
