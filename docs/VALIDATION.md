# Validation and remaining gates

## Executed

- Fork created: https://github.com/pipaandthebaskas/GetMoreRam
- Successful macOS build: https://github.com/pipaandthebaskas/GetMoreRam/actions/runs/36000078736
- Build source: `40f7664da746b4ecf5bededa1499320f2c5b8fbd` (clean checkout).
- Xcode 26.4.1, build 17E202: **ARCHIVE SUCCEEDED** for generic iOS/arm64.
- Swift XCTest: **10 tests passed**, covering response errors/redaction, capability
  preservation/idempotence/schema handling, Apple host allowlist, strict Boolean,
  exact profile instance/expiry and DER/BER CMS decoding/malformed data.
- Python unit tests: **10 passed**, covering host/team/profile/signature mismatches,
  expiry, missing/false/non-Boolean permission and unsafe ZIP paths.
- Downloaded build artifact digest matched GitHub's published SHA-256.
- Extracted IPA digest matched its build manifest:
  `7093c2d3128fce4d65a6573497c47e85bc990e1707ed32d4eaf2596b6fa20118`.
- IPA contains `Payload/GetMoreRam.app`, a 64-bit Mach-O executable, bundle ID
  `com.aigch.getMoreRam`, minimum iOS 16.0. It intentionally has no provisioning
  profile and is not developer signed; SideStore must sign it for installation.
- The temporary source-transfer workflow was successfully run and removed.

## Not yet executed

- Live Apple API requests using the user's account/local Anisette.
- Current free-account entitlement eligibility: unknown until Apple returns evidence.
- Real LiveContainer3 profile and final signed IPA checks: no such artifacts supplied.
- Device install/run and memory measurement on the user's iPhone.

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

1. Download the tested unsigned GetMoreRam artifact and sign/install it locally.
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
