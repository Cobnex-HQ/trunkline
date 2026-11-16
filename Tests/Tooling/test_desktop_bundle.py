import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]


class DesktopBundleTests(unittest.TestCase):
    def fixture(self, root):
        for runtime, version in [('Vendor/SunshineRuntime', '1.0.0'), ('candidate', '2026.1116.1')]:
            for arch in ['arm64', 'x86_64']:
                bundle = root / runtime / arch / 'Sunshine.app/Contents'
                (bundle / 'MacOS').mkdir(parents=True)
                (bundle / 'Resources/assets/web').mkdir(parents=True)
                executable = bundle / 'MacOS/Sunshine'
                executable.write_bytes(b'fixture executable'); executable.chmod(0o755)
                (bundle / 'Resources/assets/web/index.html').write_text('fixture UI')
                (bundle / 'Resources/assets/apps.json').write_text('{}')
                (bundle / 'Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleExecutable': 'Sunshine', 'CFBundleName': 'Sunshine',
                    'CFBundleIdentifier': 'dev.lizardbyte.app.Sunshine',
                    'CFBundleIconFile': 'sunshine.icns', 'CFBundleShortVersionString': version,
                    'CFBundleVersion': version,
                }))
        candidate = root / 'candidate'
        (candidate / 'ThirdParty').mkdir()
        (candidate / 'ThirdParty/NOTICES.txt').write_text('Fixture notices')
        files = {str(p.relative_to(candidate)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in candidate.rglob('*') if p.is_file()}
        (candidate / 'PROVENANCE.json').write_text(json.dumps({
            'schema': 1, 'kind': 'trunkline-desktop-candidate', 'version': '2026.1116.1', 'files': files,
        }))
        output = root / 'products/Trunkline.app/Contents'
        (output / 'Resources').mkdir(parents=True)
        (output / 'Resources/AppIcon.icns').write_bytes(b'fixture icon')
        (root / 'products/TrunklineDesktopSupervisor').write_text('fixture supervisor')
        return candidate, output

    def bundle(self, root, candidate, architectures=None):
        env = os.environ | {'SRCROOT': str(root), 'TARGET_BUILD_DIR': str(root / 'products'),
            'BUILT_PRODUCTS_DIR': str(root / 'products'), 'CONTENTS_FOLDER_PATH': 'Trunkline.app/Contents',
            'UNLOCALIZED_RESOURCES_FOLDER_PATH': 'Trunkline.app/Contents/Resources',
            'CODE_SIGNING_ALLOWED': 'NO'}
        if architectures: env['ARCHS'] = architectures
        env.pop('TRUNKLINE_DESKTOP_RUNTIME', None)
        if candidate is not None: env['TRUNKLINE_DESKTOP_RUNTIME'] = str(candidate)
        # The real script performs file copying/plist updates; no signing or app launch.
        return subprocess.run(['zsh', str(PROJECT / 'Scripts/bundle-desktop.sh')], env=env,
                              text=True, capture_output=True)

    def test_native_only_candidate_does_not_require_the_other_architecture(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); candidate, output = self.fixture(root)
            shutil.rmtree(candidate / 'x86_64')
            metadata = json.loads((candidate / 'PROVENANCE.json').read_text())
            metadata['architectures'] = ['arm64']
            metadata['files'] = {k:v for k,v in metadata['files'].items() if not k.startswith('x86_64/')}
            (candidate / 'PROVENANCE.json').write_text(json.dumps(metadata))
            result = self.bundle(root, candidate, 'arm64')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((output / 'Helpers/Desktop/arm64/TrunklineDesktop.app').exists())
            self.assertFalse((output / 'Helpers/Desktop/x86_64').exists())

    def test_explicit_candidate_is_used_and_provenance_is_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); candidate, output = self.fixture(root)
            result = self.bundle(root, candidate)
            self.assertEqual(result.returncode, 0, result.stderr)
            for arch in ['arm64', 'x86_64']:
                bundle = output / f'Helpers/Desktop/{arch}/TrunklineDesktop.app/Contents'
                info = plistlib.loads((bundle / 'Info.plist').read_bytes())
                self.assertEqual(info['CFBundleShortVersionString'], '2026.1116.1')
                self.assertEqual(info['CFBundleIdentifier'], 'dev.lizardbyte.app.Sunshine')
                self.assertEqual(info['CFBundleDisplayName'], 'Trunkline Desktop')
            self.assertEqual((output / 'Resources/ThirdParty/DesktopCandidate/PROVENANCE.json').read_bytes(),
                             (candidate / 'PROVENANCE.json').read_bytes())
            self.assertFalse((output / 'Helpers/Desktop/ThirdParty').exists())

    def test_invalid_candidate_cannot_fall_back_or_change_existing_payload(self):
        for damage in ['missing', 'changed', 'extra', 'symlink']:
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); candidate, output = self.fixture(root)
                target = output / 'Helpers/Desktop'; target.mkdir(parents=True)
                (target / 'sentinel').write_text('existing package')
                if damage == 'missing': (candidate / 'PROVENANCE.json').unlink()
                elif damage == 'changed': (candidate / 'arm64/Sunshine.app/Contents/MacOS/Sunshine').write_text('changed')
                elif damage == 'extra': (candidate / 'unlisted').write_text('unlisted')
                else: (candidate / 'escape').symlink_to('/etc/passwd')
                result = self.bundle(root, candidate)
                self.assertNotEqual(result.returncode, 0, 'Invalid override was silently accepted')
                self.assertEqual(list(target.iterdir()), [target / 'sentinel'])

    def test_returning_to_default_removes_candidate_identity_and_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); candidate, output = self.fixture(root)
            first = self.bundle(root, candidate)
            self.assertEqual(first.returncode, 0, first.stderr)
            second = self.bundle(root, None)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertFalse((output / 'Helpers/Desktop/PROVENANCE.json').exists())
            self.assertFalse((output / 'Resources/ThirdParty/DesktopCandidate').exists())


if __name__ == '__main__': unittest.main()
