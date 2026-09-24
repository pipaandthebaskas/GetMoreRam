#!/usr/bin/env python3
"""Deterministically package the unsigned build; no fake developer signing."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
app = root / 'build/GetMoreRam.xcarchive/Products/Applications/GetMoreRam.app'
assert app.is_dir(), 'Archive app missing'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.aigch.getMoreRam'
assert (app / info['CFBundleExecutable']).is_file()
ipa = root / 'build/GetMoreRam-unsigned.ipa'
with zipfile.ZipFile(ipa, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted(app.rglob('*')):
        assert not file.is_symlink(), 'Unexpected symlink in iOS archive'
        if file.is_file():
            entry = zipfile.ZipInfo('Payload/GetMoreRam.app/' + file.relative_to(app).as_posix(), (2020, 1, 1, 0, 0, 0))
            entry.external_attr = (file.stat().st_mode & 0xffff) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(entry, file.read_bytes())
manifest = {'artifact': ipa.name, 'developer_signed': False,
            'livecontainer_verified': False,
            'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
            'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
            'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True)),
            'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()}
(root / 'build/build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Created unsigned GetMoreRam IPA for SideStore signing. This does not verify LiveContainer.')
