import importlib.util
from pathlib import Path
import unittest

SCRIPT = Path(__file__).parents[2] / 'Scripts/audit-ios.py'


class IOSAuditTests(unittest.TestCase):
    def load(self):
        self.assertTrue(SCRIPT.exists(), 'Provide a repeatable archive audit')
        spec = importlib.util.spec_from_file_location('ios_audit', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def info(self):
        return {'CFBundleSupportedPlatforms': ['iPhoneOS'], 'UIDeviceFamily': [1, 2],
                'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '3',
                'NSCameraUsageDescription': 'Scan your Mac pairing code.',
                'NSLocalNetworkUsageDescription': 'Connect to your Mac.',
                'NSFaceIDUsageDescription': 'Unlock your saved connection.',
                'ITSAppUsesNonExemptEncryption': True,
                'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
                'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']}

    def test_rejects_global_network_exception_and_missing_tablet_rotation(self):
        audit = self.load()
        info = self.info()
        self.assertEqual(audit.configuration_findings(info), [])
        info['NSAppTransportSecurity'] = {'NSAllowsArbitraryLoads': True}
        info['UISupportedInterfaceOrientations~ipad'].pop()
        codes = {f['code'] for f in audit.configuration_findings(info)}
        self.assertIn('global-ats', codes)
        self.assertIn('ipad-orientation', codes)

    def test_missing_permission_purpose_and_simulator_archive_fail(self):
        audit = self.load()
        info = self.info()
        info['NSCameraUsageDescription'] = ''
        info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        codes = {f['code'] for f in audit.configuration_findings(info)}
        self.assertIn('permission-NSCameraUsageDescription', codes)
        self.assertIn('device-archive', codes)

    def test_each_binary_needs_its_own_required_reason_declarations(self):
        audit = self.load()
        symbols = '                 U _stat\n                 U _mach_absolute_time\n'
        findings = audit.privacy_findings('Example.framework', {'NSPrivacyAccessedAPITypes': []}, symbols)
        self.assertEqual({f['code'] for f in findings}, {'missing-reason-FileTimestamp', 'missing-reason-SystemBootTime'})
        manifest = {'NSPrivacyAccessedAPITypes': [
            {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp', 'NSPrivacyAccessedAPITypeReasons': ['C617.1']},
            {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategorySystemBootTime', 'NSPrivacyAccessedAPITypeReasons': ['35F9.1']} ]}
        self.assertEqual(audit.privacy_findings('Example.framework', manifest, symbols), [])

    def test_empty_reason_array_does_not_count_as_declared(self):
        audit = self.load()
        manifest = {'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp', 'NSPrivacyAccessedAPITypeReasons': []}]}
        self.assertEqual(audit.privacy_findings('App', manifest, 'U _fstat\n')[0]['code'], 'missing-reason-FileTimestamp')


if __name__ == '__main__':
    unittest.main()
