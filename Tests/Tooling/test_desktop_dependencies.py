import hashlib
import importlib.util
import io
import multiprocessing
from pathlib import Path
import tarfile
import tempfile
import time
import unittest


spec = importlib.util.spec_from_file_location('desktop_dependencies',
                                             Path(__file__).parents[2] / 'Scripts' / 'build-desktop-dependencies.py')
dependencies = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dependencies)


class DesktopDependenciesTests(unittest.TestCase):
    def test_simultaneous_architectures_share_one_complete_source_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            original_base = dependencies.BASE
            original_extract = dependencies.extract_archive
            dependencies.BASE = Path(directory)
            archive = Path(directory) / 'archives/source.tar.gz'
            archive.parent.mkdir()
            with tarfile.open(archive, 'w:gz') as target:
                member = tarfile.TarInfo('source/input.c')
                content = b'int source = 1;\n'
                member.size = len(content)
                target.addfile(member, io.BytesIO(content))
            item = {'url': 'https://invalid.example/source.tar.gz',
                    'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
            context = multiprocessing.get_context('fork')
            ready = context.Barrier(2)
            results = context.Queue()

            def slow_extract(*args):
                original_extract(*args)
                time.sleep(0.15)  # Expose the former check/extract/rename race.

            def prepare():
                try:
                    ready.wait(timeout=5)
                    tree = dependencies.prepare_sources(item)
                    results.put((tree / 'source/input.c').read_bytes())
                except Exception as error:
                    results.put(repr(error))

            dependencies.extract_archive = slow_extract
            workers = [context.Process(target=prepare) for _ in range(2)]
            try:
                for worker in workers:
                    worker.start()
                for worker in workers:
                    worker.join(timeout=10)
                self.assertEqual([worker.exitcode for worker in workers], [0, 0])
                self.assertEqual([results.get(timeout=2) for _ in workers], [content, content])
            finally:
                for worker in workers:
                    if worker.is_alive():
                        worker.terminate()
                        worker.join()
                dependencies.BASE = original_base
                dependencies.extract_archive = original_extract

    def test_unsafe_archive_is_rejected_before_writing_any_member(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                           ('link', tarfile.SYMTYPE), ('hardlink', tarfile.LNKTYPE)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / 'bad.tar'
                with tarfile.open(archive, 'w') as target:
                    safe = tarfile.TarInfo('safe'); target.addfile(safe)
                    bad = tarfile.TarInfo(name); bad.type = kind; bad.linkname = '../escape'
                    target.addfile(bad)
                destination = root / 'output'; destination.mkdir()
                with self.assertRaises(ValueError):
                    dependencies.extract_archive(archive, destination)
                self.assertEqual(list(destination.iterdir()), [])

    def test_cached_download_must_match_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'cached.tar'
            archive.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError, 'Checksum mismatch'):
                dependencies.verify_digest(archive, hashlib.sha256(b'original').hexdigest())


if __name__ == '__main__':
    unittest.main()
