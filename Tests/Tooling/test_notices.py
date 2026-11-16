"""Exercise actual notice bundling with files and an isolated Cargo metadata response."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / 'Scripts/bundle-notices.py'


class NoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write('LICENSE', 'Project licence\n')
        self.write('docs/THIRD_PARTY.md', 'Credits\n')
        self.write('Dependencies/required-notices.json', '[]')
        self.out = self.root / 'build/Resources/ThirdParty'

    def write(self, name, contents):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def bundle(self, packages=None):
        env = {'SRCROOT': str(self.root), 'TARGET_BUILD_DIR': str(self.root / 'build'),
               'UNLOCALIZED_RESOURCES_FOLDER_PATH': 'Resources'}
        # Cargo is an external process; all notice discovery/copying is real.
        with patch.dict(os.environ, env), patch('subprocess.check_output', return_value=json.dumps({'packages': packages or []}).encode()):
            runpy.run_path(str(SCRIPT), run_name='__main__')

    def test_prefixed_and_embedded_license_files_are_preserved(self):
        self.write('Apps/macOS/Resources/macowl-LICENSE.txt', 'Original MacOwl grant\n')
        self.write('Vendor/SDL/include/SDL_copying.h', 'Original SDL grant\n')
        self.bundle()
        self.assertEqual((self.out / 'Trunkline/macowl-LICENSE.txt').read_text(), 'Original MacOwl grant\n')
        self.assertEqual((self.out / 'Vendor/SDL/include/SDL_copying.h').read_text(), 'Original SDL grant\n')

    def test_space_separated_license_name_is_preserved(self):
        self.write('Vendor/Component/LICENSE MIT.md', 'Original MIT grant\n')
        self.bundle()
        self.assertEqual((self.out / 'Vendor/Component/LICENSE MIT.md').read_text(), 'Original MIT grant\n')

    def test_required_notice_missing_or_modified_stops_bundle(self):
        self.write('Dependencies/required-notices.json', json.dumps([
            {'path': 'Licenses/Component/LICENSE', 'sha256': hashlib.sha256(b'Original grant\n').hexdigest()}]))
        for contents in [None, 'Changed grant\n']:
            with self.subTest(contents=contents):
                if contents is not None:
                    self.write('Licenses/Component/LICENSE', contents)
                with self.assertRaises((ValueError, FileNotFoundError)):
                    self.bundle()

    def test_required_notice_copied_with_unchanged_bytes(self):
        path = self.write('Licenses/Component/terms.txt', 'Original grant\n')
        self.write('Dependencies/required-notices.json', json.dumps([
            {'path': 'Licenses/Component/terms.txt', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}]))
        self.bundle()
        self.assertEqual((self.out / 'Licenses/Component/terms.txt').read_bytes(), path.read_bytes())

    def test_rust_package_without_notice_is_reported(self):
        manifest = self.write('crate/Cargo.toml', '[package]\n')
        self.bundle([{'name': 'fixture', 'version': '1.0.0', 'license': 'MIT',
                      'repository': 'https://example.org/fixture', 'source': 'registry+fixture',
                      'manifest_path': str(manifest), 'license_file': None}])
        inventory = json.loads((self.out / 'Rust-dependencies.json').read_text())
        self.assertEqual(inventory[0]['notice_status'], 'review-required')
        self.assertEqual(inventory[0]['notice_files'], [])
        self.assertIn('fixture', (self.out / 'NOTICE-REVIEW.json').read_text())

    def test_cargo_declared_license_file_is_retained(self):
        manifest = self.write('crate/Cargo.toml', '[package]\n')
        self.write('crate/legal/terms.txt', 'Custom upstream grant\n')
        self.bundle([{'name': 'fixture', 'version': '1.0.0', 'license': None,
                      'repository': None, 'source': 'registry+fixture',
                      'manifest_path': str(manifest), 'license_file': 'legal/terms.txt'}])
        self.assertEqual((self.out / 'Rust/fixture-1.0.0/legal/terms.txt').read_text(), 'Custom upstream grant\n')


if __name__ == '__main__':
    unittest.main()
