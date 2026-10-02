# Brainstorm: authenticity of the synced data files

Security review finding #1. Status: open, for discussion.

## Problem
The app fetches `manifest.json`, `verbs.json`, `grammar.json` and `furigana.json` from
`raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/`
(`GitHubVerbFetcher.githubMain`). Each data file is checked against the SHA-256 in the
manifest, but the manifest comes from the same host and branch. The hash catches
corruption, not tampering. Anyone who can write to `main` changes what every user sees on
their next sync. Impact is content tampering or malformed input; no data is executed or
rendered as markdown/HTML. The size cap (5 MB) and strict decoding already limit the blast radius.

## Threat model
In scope: compromised maintainer account or token, a malicious or mistaken merged PR,
a compromised GitHub CDN path. Out of scope: TLS interception (HTTPS, no ATS exceptions),
device compromise.

## Options

| # | Option | Stops | Cost | Notes |
|---|--------|-------|------|-------|
| A | Branch protection on `main`: required reviews, signed commits, no force push, restrict who can push | Direct pushes, stolen token without admin | Free, no code | Does not help if an admin account is compromised. Do regardless. |
| B | Fetch from an immutable ref (release tag or commit SHA) instead of `main` | Silent edits after release; makes rollback explicit | Release step per data update; app needs to learn the new ref (chicken and egg: a hardcoded tag never updates) | Needs a small mutable "pointer" which brings back the original problem unless that pointer is signed. Better paired with C. |
| C | Sign the manifest (Ed25519 or ECDSA); app embeds the public key and verifies via CryptoKit before trusting hashes | Compromise of GitHub account or repo | Key generation and storage, a signing step in `scripts/update_data.py`, verification code and tests, key rotation plan | Strongest. The private key must live off the repo (offline, hardware key, or CI secret with environment protection). |
| D | Ship a bundled snapshot and only accept newer `version` values | Rollback attacks | Small code change | Complements C; prevents replaying an old signed manifest. |
| E | Do nothing beyond A | n/a | n/a | Acceptable if the data is low value and the repo is well protected. |

## Open questions
1. How sensitive is tampered content for this app? Wrong lessons only, or something you
   would be embarrassed by in a store review?
2. Who can push to `main` today, and is 2FA/passkey enforced? Is the repo public?
3. Is a manual release step per data update acceptable, or should contributors' merged
   verb additions go live automatically?
4. Where could a signing key safely live (offline, YubiKey, GitHub Actions environment secret)?
5. Do we need a key rotation story before the first release? (Embed two keys?)
6. Should unsigned or invalid data fail closed (keep cached data) or fall back? Suggested: fail closed, keep last good cache.

## Suggested path
1. Now: option A (settings only).
2. Before release: option C with D's version check, keeping `main` hosting. This works without per-update releases because the signature, not the ref, carries the trust.
3. Skip B unless you want release gating for editorial reasons.

## If we pick C: sketch
- Manifest gains `signature` (base64) over the canonical bytes of `{version, sha256, grammar, furigana}`.
- `scripts/update_data.py` signs; `scripts/test_update_data.py` covers it.
- `VerbManifest` verification in VerbKit using `Curve25519.Signing.PublicKey`; fetcher returns raw manifest bytes so the signature covers exactly what was served.
- Tests: valid, tampered data, tampered manifest, wrong key, missing signature, downgraded version.
