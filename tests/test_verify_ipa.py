import datetime as dt
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('verify_ipa', Path(__file__).parents[1] / 'scripts/verify_ipa.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

class VerificationTests(unittest.TestCase):
    def profile(self):
        return {'TeamIdentifier': ['TEAM'], 'ApplicationIdentifierPrefix': ['PREFIX'],
                'ExpirationDate': dt.datetime(2099, 1, 1),
                'Entitlements': {'application-identifier': 'PREFIX.com.example.LiveContainer3',
                                 'com.apple.developer.team-identifier': 'TEAM', v.KEY: True}}
    def test_valid_separate_app_prefix(self):
        v.validate_profile(self.profile(), 'com.example.LiveContainer3', 'TEAM')
    def test_wrong_instance(self):
        with self.assertRaises(v.VerificationError):
            v.validate_profile(self.profile(), 'com.example.LiveContainer2', 'TEAM')
    def test_wrong_team(self):
        with self.assertRaises(v.VerificationError):
            v.validate_profile(self.profile(), 'com.example.LiveContainer3', 'OTHER')
    def test_profile_missing_false_and_non_boolean(self):
        for value in (None, False, 1, 'true', [], {}):
            profile = self.profile(); profile['Entitlements'][v.KEY] = value
            with self.subTest(value=value), self.assertRaises(v.VerificationError):
                v.validate_profile(profile, 'com.example.LiveContainer3', 'TEAM')
    def test_expired(self):
        profile = self.profile(); profile['ExpirationDate'] = dt.datetime(2000, 1, 1)
        with self.assertRaises(v.VerificationError):
            v.validate_profile(profile, 'com.example.LiveContainer3', 'TEAM')
    def test_signer_stripped_entitlement(self):
        ent = self.profile()['Entitlements']; stripped = dict(ent); stripped.pop(v.KEY)
        with self.assertRaises(v.VerificationError): v.validate_signature(stripped, ent)
    def test_signature_wrong_instance(self):
        ent = self.profile()['Entitlements']; wrong = dict(ent); wrong['application-identifier'] += '2'
        with self.assertRaises(v.VerificationError): v.validate_signature(wrong, ent)
    def test_signature_valid(self):
        ent = self.profile()['Entitlements']; v.validate_signature(ent, ent)
    def test_archive_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.ipa'
            with zipfile.ZipFile(path, 'w') as archive: archive.writestr('../escape', 'bad')
            with self.assertRaises(v.VerificationError): v.safe_extract(path, Path(tmp) / 'extract')
    def test_archive_duplicate(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.ipa'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/App.app/Info.plist', 'a')
                archive.writestr('payload/app.app/info.plist', 'b')
            with self.assertRaises(v.VerificationError): v.safe_extract(path, Path(tmp) / 'extract')

if __name__ == '__main__': unittest.main()
