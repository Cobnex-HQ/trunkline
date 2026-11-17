import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parents[2] / 'Scripts/release.py'


class ReleaseTests(unittest.TestCase):
    def release(self):
        self.assertTrue(SCRIPT.exists(), 'A separate public-release workflow is required')
        spec = importlib.util.spec_from_file_location('release', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        sys.path.insert(0, str(SCRIPT.parent))
        try:
            spec.loader.exec_module(module)
        finally:
            sys.path.pop(0)
        return module

    def test_export_options_produce_local_app_store_export_without_upload(self):
        release = self.release()
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'ExportOptions.plist'
            release.write_export_options(path, 'ABCDEFGHIJ')
            options = plistlib.loads(path.read_bytes())
            self.assertEqual(options['method'], 'app-store-connect')
            self.assertEqual(options['destination'], 'export')
            self.assertEqual(options['teamID'], 'ABCDEFGHIJ')
            self.assertFalse(options['manageAppVersionAndBuildNumber'])
            self.assertNotIn('provisioningProfiles', options)

    def test_unsigned_ios_archive_cannot_be_exported_as_a_store_build(self):
        release = self.release()
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'Companion.xcarchive'
            app = archive / 'Products/Applications/Trunkline.app'
            app.mkdir(parents=True)
            info = {'ApplicationProperties': {'ApplicationPath': 'Applications/Trunkline.app'}}
            (archive / 'Info.plist').write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError, 'signed archive'):
                release.archive_app(archive, require_signed=True)
            info['ApplicationProperties']['SigningIdentity'] = 'Apple Development: Fixture'
            (archive / 'Info.plist').write_bytes(plistlib.dumps(info))
            self.assertEqual(release.archive_app(archive, require_signed=True), app.resolve())

    def test_archive_cannot_reference_an_app_outside_its_products(self):
        release = self.release()
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'Host.xcarchive'; archive.mkdir()
            outside = Path(temporary) / 'Outside.app'; outside.mkdir()
            for path in [str(outside), '../../Outside.app']:
                (archive / 'Info.plist').write_bytes(plistlib.dumps({
                    'ApplicationProperties': {'ApplicationPath': path, 'SigningIdentity': 'Fixture'}}))
                with self.assertRaisesRegex(ValueError, 'inside.*Products'):
                    release.archive_app(archive, require_signed=True)

    def test_upload_or_pending_status_is_not_notarization_acceptance(self):
        release = self.release()
        accepted = {'id': '00000000-0000-4000-8000-000000000001', 'status': 'Accepted'}
        self.assertEqual(release.accepted_notarization(accepted), accepted['id'])
        for result in [{}, {'status': 'Accepted'}, dict(accepted, status='Invalid'),
                       dict(accepted, status='In Progress'), dict(accepted, id='not-an-id')]:
            with self.assertRaises(ValueError):
                release.accepted_notarization(result)

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires Mach-O inspection')
    def test_ios_preflight_blocks_an_archive_with_missing_privacy_and_notices(self):
        release = self.release()
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / 'Fixture.xcarchive'
            app = archive / 'Products/Applications/Trunkline.app'
            app.mkdir(parents=True)
            (archive / 'Info.plist').write_bytes(plistlib.dumps({
                'ApplicationProperties': {'ApplicationPath': 'Applications/Trunkline.app'}}))
            (app / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleExecutable': 'Trunkline', 'CFBundleSupportedPlatforms': ['iPhoneOS']}))
            source = Path(temporary) / 'fixture.c'
            source.write_text('int main(void) { return 0; }\n')
            subprocess.run(['xcrun', 'clang', str(source), '-o', str(app / 'Trunkline')], check=True)
            with self.assertRaisesRegex(ValueError, 'missing-manifest.*notice-review-missing'):
                release.ios_preflight(archive)

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires real macOS signing tools')
    def test_public_mac_gate_rejects_real_ad_hoc_signature(self):
        release = self.release()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'fixture.c'; source.write_text('int main(void) { return 0; }\n')
            binary = root / 'fixture'
            subprocess.run(['xcrun', 'clang', str(source), '-o', str(binary)], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            with self.assertRaisesRegex(ValueError, 'Developer ID') as rejection:
                release.verify_developer_id(binary)
            self.assertNotIn('invalid requirement specification', str(rejection.exception.__cause__.output))


if __name__ == '__main__':
    unittest.main()
