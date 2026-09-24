# Validation and remaining gates

## Executed in this workspace

- Python unit tests: 10 passed (exact host/team, profile expiry, strict Boolean,
  signer stripping, signature mismatch, archive traversal/duplicate paths).
- Shell build script syntax check passed.
- `git diff --check` passed.
- Swift syntax parser reviewed added files; it is not a Swift compiler. The parser
  also reports constructs in unchanged upstream code, so this is not a build result.
- Attempted `bash scripts/build_ipa.sh`: stopped at the platform preflight because
  this Linux host has no Xcode/iOS SDK. No IPA was produced.
- GitHub fork page redirected to sign-in. No authenticated GitHub session/CLI was
  available, so no remote fork, push, or Actions run has happened.

## Not yet executed

- Swift XCTest suite and iOS archive: require macOS/Xcode.
- Live Apple API requests: require the user's local authentication and local Anisette.
- Current account entitlement eligibility: unknown until Apple returns evidence.
- Real profile payload and final signed IPA checks: no such artifacts were supplied.
- Device install/run and memory measurement on the user's iPhone: not performed.

The capability endpoint is Apple's private Xcode developer service, not the public
App Store Connect API. Readback schema support covers capability relationships and
bundle-prefixed capability resource IDs. Unrecognized or paginated responses stop
before writing. The request adapter has not been validated against a live account.
No switch to paid-account JWT/App Store Connect auth is made.

The in-app CMS reader validates the downloaded Apple HTTPS response's payload,
identifier, expiry and entitlement; it does not independently validate the CMS
certificate chain. The macOS IPA tool decodes the embedded profile, checks all
executable architectures, checks codesign integrity and requires the signer leaf
certificate to occur in DeveloperCertificates. This does not prove Apple profile
trust, device authorization, successful installation, or the installed copy's hash.

## Required real-world checks

1. Run the workflow on a fork and inspect the Swift tests and iOS archive result.
2. Configure local-only Anisette. Log in on-device; never put Apple credentials in CI.
3. Select the team and the exact registered bundle identifier of LiveContainer3.
4. Enable and verify the profile. A missing Boolean or rejected request is failure.
5. Have SideStore sign/reinstall that exact instance with a newly obtained profile.
6. Obtain the actual final signed IPA from that signing run. A source IPA downloaded
   from a release is not evidence of what SideStore installed.
7. On macOS run `python3 scripts/verify_ipa.py FINAL.ipa --bundle-id EXACT_ID --team-id TEAM`.
8. Verify the corresponding installed host, then repeat independently for other instances.

Source comparison:
- SideStore/AltSign `35b68f1aafaa038fd012b11d5acb71e6394c9c25`:
  capability constants and team profile download; SideStore's resign operation uses
  its selected provisioning profiles. This is not proof of the user's Nightly build.
- https://github.com/fastlane/fastlane/blob/master/spaceship/lib/spaceship/connect_api/provisioning/provisioning.rb
  separates private portal relationship updates from public capability-resource APIs.
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md
  lists Xcode 26.4.1, build 17E202, used by this workflow.
