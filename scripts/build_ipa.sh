#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null; then
  echo 'Build requires macOS and Xcode 26.4.1 (17E202); no IPA was produced.' >&2
  exit 1
fi
version=$(xcodebuild -version)
if [[ "$version" != $'Xcode 26.4.1\nBuild version 17E202' ]]; then
  echo 'Select Xcode 26.4.1 (17E202) for this reproducible build recipe.' >&2
  exit 1
fi
mkdir -p build
python3 -m unittest discover -s tests -v
swift test --package-path Vendor/StosSign --disable-automatic-resolution
xcodebuild -resolvePackageDependencies -project GetMoreRam.xcodeproj -scheme GetMoreRam \
  -onlyUseVersionsFromResolvedFile
xcodebuild archive -project GetMoreRam.xcodeproj -scheme GetMoreRam \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/GetMoreRam.xcarchive -derivedDataPath build/DerivedData \
  -disableAutomaticPackageResolution -onlyUseVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
python3 scripts/package_ipa.py
