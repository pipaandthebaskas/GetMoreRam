# GetMoreRam diagnostic fork

Based on upstream, with targeted fixes. **The iOS archive and 20 tests passed in
[GitHub Actions](https://github.com/pipaandthebaskas/GetMoreRam/actions/runs/36000078736).**
Download the `GetMoreRam-unsigned` artifact from that run and sign it with SideStore.
Account-specific entitlement approval and the final LiveContainer3 signature remain
unverified. See [technical diagnosis](docs/DIAGNOSIS.md) and
[test results / remaining gates](docs/VALIDATION.md).

This app enables an Apple App ID capability and checks the downloaded provisioning
profile. It does not sign or modify other installed apps. `entitlements: []` from
the old UI was a stale model, not a profile/signature inspection.

## Privacy

Apple authentication goes only to allowlisted Apple HTTPS hosts, with redirects
blocked. V3 Anisette sends provisioning secrets, so public servers are blocked.
Configure a V3 service on numeric loopback (`http://127.0.0.1:6969`) or a loopback
tunnel to a computer you control. No local Anisette server is bundled. This is an
intentional privacy constraint, not a plug-and-play replacement for public Anisette.
A SideStore account import alone does not remove this requirement.

Credentials and Anisette provisioning state use non-synchronizing,
WhenUnlockedThisDeviceOnly Keychain items. Old synchronized entries are removed;
expect to sign in/import again after upgrading. Apple sessions remain in memory.
Logs show stages and safe errors, not raw responses, headers, passwords, tokens,
identifiers or profile dumps. No analytics/upload endpoint is included.

## Use with multiple LiveContainer instances

Sign in locally, select your signing team, and refresh App IDs. Select each exact
registered host bundle ID separately. Do not infer it from a name like LiveContainer3.
Tap **Enable and Verify Profile**. Readback and the profile check are separate stages.
A profile must have the Boolean `com.apple.developer.kernel.increased-memory-limit`
set to `true`, match the selected identifier/team, and be unexpired. Apple rejection
is an error; an omitted entitlement is not treated as success or automatically
interpreted as a paid-account requirement.

Reinstall the same host through SideStore with a newly obtained profile. Keep your
other instances' identifiers unchanged. Check the actual final signed IPA on macOS:

```sh
python3 scripts/verify_ipa.py /path/to/FINAL-SIGNED.ipa \
  --bundle-id YOUR_EXACT_SIGNED_HOST_ID --team-id YOUR_TEAM_ID
```

The verifier checks both the profile and every architecture's signed entitlements,
signature integrity and signer-certificate membership. It never uploads the IPA.
It does not claim to inspect the copy already installed on the iPhone.

## Build and tests

On macOS with Xcode 26.4.1 (17E202):

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.4.1.app/Contents/Developer
bash scripts/build_ipa.sh
```

GitHub Actions runs the same script on `macos-26`, with pinned action commits and
locked cryptographic dependencies. The artifact is **GetMoreRam-unsigned.ipa**, for
subsequent SideStore signing. CI receives no Apple credentials and cannot produce
an account-provisioned LiveContainer IPA. The recipe pins source/toolchain versions;
GitHub hosted images themselves change, so byte-identical compiler output is not promised.

The API/Auth/Common portion of StosSign is vendored at its original pinned revision
with focused patches; upstream notices are retained. Unused OpenSSL/certificate/signer
targets are not linked. The historical OpenSSL submodule is retained but is not needed
for this build. See [dependency provenance](Vendor/StosSign/UPSTREAM.md).

---

## Original upstream README

# Get More Ram
A simple [StosSign](https://github.com/stossy11/StosSign) wrapper app that allows you to enable "Increased Memory Limit" for your sideloaded apps without using Xcode.

# How to use
1. Sideload this app
2. Go to settings, sign in your account that you used to sign the app you want to enable "Increased Memory Limit"
3. Go to "App IDs" page
4. Tap Refresh
5. Tap the app you want to enable "Increased Memory Limit"
6. Tap "Add Increased Memory Limit"
7. Reinstall the app from SideStore/AltStore
8. Check if you have "Increased Memory Limit"

# Credits
Stossy11 - For StosSign.
SideStore - Anisette Data fetching codes are stolen from SideStore
