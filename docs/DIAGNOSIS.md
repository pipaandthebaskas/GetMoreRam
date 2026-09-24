# Investigation before implementation

Baseline GetMoreRam: `52f5e964cf262dd1b8f4a1b93cde22b79a1fdd3f`.
Pinned StosSign: `01dd7bc4f5084ade9e2ebbc7e338dc2e3f454d77`.

## Confirmed defects

1. `AppID.init` sets `entitlements = []`; the response initializer never reads entitlements. `AppleAPI.updateAppID` PATCHes Apple's v1 bundle ID endpoint but returns its unchanged input. `AppIDModel` prints that stale object. An empty array is therefore not evidence that Apple rejected this capability.
2. The request helpers discard HTTP status and do not centrally reject JSON:API `errors` or nonzero legacy `resultCode`. The mutation checks only for a `data` dictionary. No readback occurs.
3. The update supplies only the requested capability and overwrites unrelated bundle metadata. Existing capability relationships/settings are not read or preserved.
4. GetMoreRam has no profile generation, IPA import, or IPA signing call. SideStore/AltStore must subsequently obtain a profile and sign the actual LiveContainer host. GetMoreRam cannot change an installed signature.
5. The unused StosSign provisioning model treats an encoded CMS profile as a plain plist in one initializer and treats outer API metadata as the profile payload in another. Expiry uses `dateExpire` instead of `ExpirationDate`. It is not reliable evidence of signed profile entitlements.
6. Anisette helper logs raw headers, identifiers and responses. V3 POST sends `identifier` and `adi_pb` to the configured server; provisioning also exchanges `spim`, `cpim`, `ptm`, `tk`. Public Anisette is incompatible with the requested strict session-data privacy boundary.
7. Keychain uses `kSecAttrSynchronizable = true` and ignores write failures. Settings URL changes are not propagated after initialization. One UTC-labelled timestamp actually uses local time. Imported passwords are trimmed. Authentication can recurse through 2FA indefinitely.
8. Existing CI builds an unsigned binary and fakesigns using an unpinned latest ldid download; that is not developer signing or verification of LiveContainer.

## End-to-end trace

Local Anisette provisioning -> Apple GSA SRP / 2FA -> Xcode auth token -> selected team -> legacy App ID list -> v1 capability update/readback for the exact registered bundle ID -> downloadTeamProvisioningProfile -> decode its CMS payload -> require the Boolean increased-memory-limit and matching application identifier -> SideStore signs/reinstalls the same host -> inspect the final host executable's signature and embedded profile independently.

Every LiveContainer instance needs its own exact registered bundle identifier and team. A display name such as LiveContainer3 is insufficient; do not infer an identifier or apply a guest app's entitlements to the host.

## What the reported symptoms establish

Authentication presumably reached App ID listing, but there is no captured stage evidence. The empty array is explained by a client bug. The installed signature lacking the entitlement establishes that the installed host does not request it. It does NOT distinguish capability denial, stale/wrong profile, wrong instance, or signer stripping. A free account restriction must be reported only when Apple rejects the request or the issued profile omits permission; missing permission alone is not proof of a paid-account requirement.

Apple documents this as a Boolean entitlement, and extra memory remains device-dependent:
https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit

## Audit scope and environment

Reviewed all first-party Swift files, plist, project/package configuration and workflow; traced the pinned StosSign auth/API/common models, Anisette and signing paths. The app links API/Auth/Common only, not StosSign's signer or its Anisette implementation. CryptoSwift, swift-crypto, swift-srp/big-num implement cryptography; OpenSSL and swift-certificates are declared by the package. This is an integration/security review, not a cryptographic implementation or binary-supply-chain certification. No Apple account requests were made and no private credentials were requested.

The current host is Linux, with no Swift/Xcode/iOS SDK or GitHub CLI. A local clone is not a GitHub fork. A macOS CI run and account/device verification remain necessary before claiming a working IPA or resolving this specific account's eligibility.
