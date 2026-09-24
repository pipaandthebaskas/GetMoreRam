#!/usr/bin/env python3
"""Local macOS check of the FINAL signed host IPA, never an unsigned source IPA.
No network calls; raw profiles, certificate data and tool stderr stay private.
Checks entitlement presence and signature integrity, not Apple install eligibility.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import subprocess
import sys
import tempfile
import zipfile

KEY = 'com.apple.developer.kernel.increased-memory-limit'

class VerificationError(Exception):
    pass

def require(condition, message):
    if not condition:
        raise VerificationError(message)

def validate_profile(profile, bundle_id, team_id, now=None):
    ent = profile.get('Entitlements', {})
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    require(team_id in profile.get('TeamIdentifier', []), 'profile: wrong team')
    require(ent.get('application-identifier') in [p + '.' + bundle_id for p in prefixes],
            'profile: wrong instance or wildcard App ID')
    expiry = profile.get('ExpirationDate')
    require(isinstance(expiry, dt.datetime), 'profile: missing expiry')
    expiry = expiry.replace(tzinfo=dt.timezone.utc) if expiry.tzinfo is None else expiry
    require(expiry > (now or dt.datetime.now(dt.timezone.utc)), 'profile: expired')
    require(ent.get(KEY) is True, 'profile: entitlement missing/false; stale profile or account restriction possible')
    return ent

def validate_signature(ent, profile_ent):
    require(ent.get(KEY) is True, 'signature: Increased Memory Limit missing/false; signer did not preserve it')
    require(ent.get('application-identifier') == profile_ent.get('application-identifier'),
            'signature: application identifier differs from profile')
    require(ent.get('com.apple.developer.team-identifier') == profile_ent.get('com.apple.developer.team-identifier'),
            'signature: team differs from profile')

def safe_extract(ipa, target):
    with zipfile.ZipFile(ipa) as archive:
        require(len(archive.infolist()) <= 100000, 'archive: too many members')
        require(sum(i.file_size for i in archive.infolist()) <= 8 * 1024**3, 'archive: too large')
        seen = set()
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            require(not path.is_absolute() and '..' not in path.parts and '\\' not in item.filename,
                    'archive: unsafe path')
            require(not stat.S_ISLNK(item.external_attr >> 16), 'archive: symlink unsupported')
            normalized = str(path).casefold()
            require(normalized not in seen, 'archive: duplicate path')
            seen.add(normalized)
        archive.extractall(target)

def run(*args):
    result = subprocess.run(args, capture_output=True, check=False)
    require(result.returncode == 0, f'{Path(args[0]).name}: validation failed; raw output withheld')
    return result.stdout

def verify(ipa, bundle_id, team_id):
    require(sys.platform == 'darwin', 'Final signature verification requires macOS security/codesign/lipo.')
    with tempfile.TemporaryDirectory(prefix='getmoreram-verify-') as scratch:
        root = Path(scratch)
        safe_extract(ipa, root)
        apps = list((root / 'Payload').glob('*.app'))
        require(len(apps) == 1, 'archive: expected one top-level host app')
        app = apps[0]
        info = plistlib.loads((app / 'Info.plist').read_bytes())
        require(info.get('CFBundleIdentifier') == bundle_id, 'IPA: wrong LiveContainer instance')
        profile = plistlib.loads(run('/usr/bin/security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')))
        profile_ent = validate_profile(profile, bundle_id, team_id)
        require(profile_ent.get('com.apple.developer.team-identifier') == team_id, 'profile: entitlement team mismatch')
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app))
        exe = info.get('CFBundleExecutable', '')
        require(isinstance(exe, str) and exe and Path(exe).name == exe, 'IPA: invalid executable name')
        architectures = run('/usr/bin/lipo', '-archs', str(app / exe)).decode().split()
        require(bool(architectures), 'signature: missing architectures')
        for arch in architectures:
            ent = plistlib.loads(run('/usr/bin/codesign', '-d', '--arch', arch, '--entitlements', ':-', '--xml', str(app)))
            validate_signature(ent, profile_ent)
            cert_prefix = str(root / ('signer-' + arch))
            run('/usr/bin/codesign', '-d', '--arch', arch, '--extract-certificates', cert_prefix, str(app))
            leaf = Path(cert_prefix + '0')
            require(leaf.is_file(), 'signature: ad-hoc/unsigned; developer certificate required')
            require(leaf.read_bytes() in profile.get('DeveloperCertificates', []),
                    'signature: certificate not authorized by embedded profile')
        return {'profile_entitlement': True, 'signature_entitlement_all_architectures': True,
                'signature_integrity': True, 'certificate_in_profile': True,
                'ipa_sha256': hashlib.sha256(Path(ipa).read_bytes()).hexdigest(),
                'installed_copy_verified': False,
                'note': 'Local payload/integrity verification; device installation and Apple profile trust are separate checks.'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--bundle-id', required=True, help='Exact signed host identifier, not display name')
    parser.add_argument('--team-id', required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.ipa, args.bundle_id, args.team_id), indent=2))
    except (VerificationError, OSError, ValueError, plistlib.InvalidFileException, zipfile.BadZipFile) as error:
        message = str(error) if isinstance(error, VerificationError) else 'Malformed or unreadable artifact; sensitive details withheld.'
        print('FAILED: ' + message, file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
