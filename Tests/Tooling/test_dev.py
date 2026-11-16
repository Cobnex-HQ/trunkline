import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('dev', Path(__file__).resolve().parents[2] / 'Scripts/dev.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)

class InstallTests(unittest.TestCase):
    def test_running_app_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'built.app'; source.mkdir()
            target = root / 'Trunkline.app'; target.mkdir()
            (target / 'sentinel').write_text('original')
            with self.assertRaisesRegex(RuntimeError, 'Quit'):
                dev.install_app(source, target, processes=f'123 {target}/Contents/MacOS/TrunklineHost')
            self.assertEqual((target / 'sentinel').read_text(), 'original')

    def test_copy_failure_preserves_existing_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / 'Trunkline.app'; target.mkdir()
            (target / 'sentinel').write_text('original')
            with self.assertRaises(FileNotFoundError):
                dev.install_app(root / 'absent.app', target, processes='')
            self.assertEqual((target / 'sentinel').read_text(), 'original')

    def test_replacement_preserves_previous_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'built.app'; source.mkdir(); (source / 'new').touch()
            target = root / 'Trunkline.app'; target.mkdir(); (target / 'old').touch()
            dev.install_app(source, target, processes='')
            self.assertTrue((target / 'new').exists())
            self.assertTrue((root / 'Trunkline.previous.app/old').exists())
