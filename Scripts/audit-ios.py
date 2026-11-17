#!/usr/bin/env python3
"""Audit a built iOS archive. Passing these checks does not guarantee App Review approval."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess


def finding(code, detail, bundle='App'):
    return {'severity': 'blocker', 'code': code, 'bundle': bundle, 'detail': detail}


def configuration_findings(info):
    results = []
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        results.append(finding('device-archive', 'Use an iOS device Release archive.'))
    if not {1, 2}.issubset(info.get('UIDeviceFamily', [])):
        results.append(finding('device-families', 'The companion must support iPhone and iPad.'))
    required = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
    if not required.issubset(info.get('UISupportedInterfaceOrientations', [])):
        results.append(finding('iphone-orientation', 'Declare portrait and both landscape orientations.'))
    if not (required | {'UIInterfaceOrientationPortraitUpsideDown'}).issubset(info.get('UISupportedInterfaceOrientations~ipad', [])):
        results.append(finding('ipad-orientation', 'Declare all four iPad orientations.'))
    if info.get('UIRequiresFullScreen'):
        results.append(finding('ipad-multitasking', 'The companion must support resizable iPad windows.'))
    ats = info.get('NSAppTransportSecurity', {})
    if ats.get('NSAllowsArbitraryLoads'):
        results.append(finding('global-ats', 'Remove the global ATS exception. Keep only justified local networking access.'))
    for key in ['NSCameraUsageDescription', 'NSLocalNetworkUsageDescription', 'NSFaceIDUsageDescription']:
        if not str(info.get(key, '')).strip():
            results.append(finding('permission-' + key, 'Provide a clear purpose string.'))
    if not isinstance(info.get('ITSAppUsesNonExemptEncryption'), bool):
        results.append(finding('encryption', 'Complete the encryption declaration based on the shipped cryptography.'))
    for key in ['CFBundleShortVersionString', 'CFBundleVersion']:
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', str(info.get(key, ''))):
            results.append(finding('version-' + key, 'Provide a numeric version/build value.'))
    return results


# This detects imported symbols, not all runtime behaviour or every required API.
# Review reasons against source use. Adding an arbitrary reason is not a fix.
SYMBOLS = {
    'FileTimestamp': {'_stat', '_fstat', '_lstat', '_fstatat', '_getattrlist', '_getattrlistbulk', '_fgetattrlist'},
    'SystemBootTime': {'_mach_absolute_time'},
    'DiskSpace': {'_statfs', '_fstatfs', '_statvfs', '_fstatvfs'},
    'UserDefaults': {'_OBJC_CLASS_$_NSUserDefaults'},
}


def privacy_findings(bundle, manifest, symbol_text):
    imported = {line.split()[-1] for line in symbol_text.splitlines() if line.split()}
    declarations = {item.get('NSPrivacyAccessedAPIType'): item.get('NSPrivacyAccessedAPITypeReasons', [])
                    for item in manifest.get('NSPrivacyAccessedAPITypes', [])}
    results = []
    for category, symbols in SYMBOLS.items():
        if imported & symbols and not declarations.get('NSPrivacyAccessedAPICategory' + category):
            results.append(finding('missing-reason-' + category,
                'Imported APIs need a reason in this bundle: ' + ', '.join(sorted(imported & symbols)), bundle))
    return results


def audit_archive(archive):
    archive_info = plistlib.loads((archive / 'Info.plist').read_bytes())
    products = (archive / 'Products').resolve()
    app = (products / archive_info['ApplicationProperties']['ApplicationPath']).resolve()
    if not app.is_relative_to(products) or app.suffix != '.app':
        raise ValueError('Archive application must be inside Products')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    results = configuration_findings(info)
    bundles = [app, *sorted((app / 'Frameworks').glob('*.framework'))]
    for bundle in bundles:
        label = bundle.name
        path = bundle / 'PrivacyInfo.xcprivacy'
        manifest = plistlib.loads(path.read_bytes()) if path.exists() else {}
        if bundle == app and not path.exists():
            results.append(finding('missing-manifest', 'Include the app privacy manifest.', label))
        bundle_info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        binary = bundle / bundle_info['CFBundleExecutable']
        symbols = subprocess.check_output(['nm', '-u', str(binary)], text=True, stderr=subprocess.DEVNULL)
        results += privacy_findings(label, manifest, symbols)
        if bundle.name == 'OpenSSL.framework' and not path.exists():
            results.append(finding('sdk-manifest', 'OpenSSL requires its own SDK privacy manifest.', label))
    notices = app / 'ThirdParty/NOTICE-REVIEW.json'
    if not notices.exists():
        results.append(finding('notice-review-missing', 'Generate the dependency notice review inventory.'))
    else:
        pending = json.loads(notices.read_text())
        if pending:
            results.append(finding('notice-review-open', f'{len(pending)} locked dependencies need notice review and target reconciliation.'))
    return {'archive': archive.name, 'version': info.get('CFBundleShortVersionString'),
            'build': info.get('CFBundleVersion'), 'findings': results,
            'scope': 'Static configuration and selected imported APIs only. Signing, SDK provenance, source licensing, privacy answers, hardware behaviour and reviewer access require separate checks.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    report = audit_archive(args.archive)
    output = json.dumps(report, indent=2) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output)
    print(output)
    raise SystemExit(1 if report['findings'] else 0)


if __name__ == '__main__':
    main()
