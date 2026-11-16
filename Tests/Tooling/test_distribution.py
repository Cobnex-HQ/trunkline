import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

spec = importlib.util.spec_from_file_location('distribution', Path(__file__).parents[2] / 'Scripts' / 'distribution.py')
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)

class DistributionTests(unittest.TestCase):
    def test_export_excludes_private_state_and_builds_but_keeps_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['README.md', 'Config/Build.xcconfig', 'Config/Local.xcconfig',
                         'Packages/Transport/src/lib.rs', 'Packages/Transport/Private/mac.json',
                         'Packages/Transport/target/release/binary', 'Apps/iOS/Resources/Info.plist',
                         'Engines/Desktop/dependencies.json', 'Engines/Desktop/Patches/input.patch',
                         'Apps/iOS/identity.p12', 'Trunkline.xcodeproj/xcuserdata/me.xcuserdatad/state',
                         'Vendor/Runtime/framework/Versions/A/Info.plist']:
                file = root / name; file.parent.mkdir(parents=True, exist_ok=True); file.write_text('fixture')
            files = set(str(p.relative_to(root)) for p in distribution.source_files(root))
            self.assertEqual(files, {'README.md', 'Config/Build.xcconfig', 'Packages/Transport/src/lib.rs',
                                     'Apps/iOS/Resources/Info.plist', 'Vendor/Runtime/framework/Versions/A/Info.plist',
                                     'Engines/Desktop/dependencies.json', 'Engines/Desktop/Patches/input.patch'})

    def test_universal_macho_headers_are_not_runtime_dependencies(self):
        output = "/build/Trunkline (architecture x86_64):\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n/build/Trunkline (architecture arm64):\n\t@rpath/Core.framework/Core (compatibility version 1.0.0)\n"
        self.assertEqual(distribution.dependencies(output), ['/usr/lib/libSystem.B.dylib', '@rpath/Core.framework/Core'])

    @unittest.skipUnless(sys.platform == 'darwin', 'Requires the macOS compiler and Mach-O inspection tools')
    def test_binary_deployment_target_cannot_exceed_package_minimum(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'fixture.c'
            source.write_text('int fixture(void) { return 42; }\n')
            compatible = root / 'compatible.dylib'
            newer = root / 'newer.dylib'
            for target, output in [('14.0', compatible), ('15.0', newer)]:
                subprocess.run(['xcrun', 'clang', '-dynamiclib', '-arch', 'arm64',
                                '-mmacosx-version-min=' + target, str(source), '-o', str(output)], check=True)
            distribution.verify_macos_deployment(compatible, '14.0')
            with self.assertRaisesRegex(ValueError, 'requires macOS 15.0'):
                distribution.verify_macos_deployment(newer, '14.0')

    def test_export_rejects_symlink_outside_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / 'Apps/iOS').mkdir(parents=True)
            (root / 'Apps/iOS' / 'escape').symlink_to('/etc/passwd')
            with self.assertRaises(ValueError):
                list(distribution.source_files(root))

if __name__ == '__main__': unittest.main()
