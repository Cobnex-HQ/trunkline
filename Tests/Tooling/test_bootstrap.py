import importlib.util
from pathlib import Path
import io
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).parents[2] / 'Scripts/bootstrap.py')
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)

class BootstrapTests(unittest.TestCase):
    def test_source_archive_rejects_escape_and_links_before_extracting(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('source/link', tarfile.SYMTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory); archive = root / 'source.tar.gz'; out = root / 'out'; out.mkdir()
                with tarfile.open(archive, 'w:gz') as tar:
                    member = tarfile.TarInfo(name); member.type = kind; member.linkname = '/etc/passwd'
                    tar.addfile(member, io.BytesIO())
                with self.assertRaises(ValueError): bootstrap.extract_source(archive, out)
                self.assertEqual(list(out.iterdir()), [])
    def test_checksum_mismatch_leaves_existing_download_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'archive'; file.write_bytes(b'wrong')
            with self.assertRaises(ValueError): bootstrap.verify_sha256(file, '0' * 64)
            self.assertEqual(file.read_bytes(), b'wrong')
    def test_manifest_verifies_modified_and_missing_source_files(self):
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); file = root / 'Source.swift'; file.write_bytes(b'original')
            entries = [{'path':'Source.swift', 'sha':hashlib.sha1(b'blob 8\0original').hexdigest()}]
            bootstrap.verify_git_files(root, entries)
            file.write_bytes(b'changed')
            with self.assertRaises(ValueError): bootstrap.verify_git_files(root, entries)
            file.unlink()
            with self.assertRaises((ValueError, FileNotFoundError)): bootstrap.verify_git_files(root, entries)
