Subset of https://github.com/stossy11/StosSign at
01dd7bc4f5084ade9e2ebbc7e338dc2e3f454d77 (API, Auth, Common).
Original author notices retained. Upstream snapshot has no LICENSE file.
Local patches: Apple-only transport/redirect rejection, checked API responses,
bounded 2FA, removal of raw logging, capability read/merge/write/readback,
CMS payload decoding and strict profile validation. No cryptographic algorithm rewrite.
Unused signing/certificate/Anisette targets are excluded; GetMoreRam delegates
installation/signing to SideStore. Only the already-used cryptographic packages remain.
