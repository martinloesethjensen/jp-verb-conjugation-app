# Signed data releases

How the app decides to trust the files in `data/`. Decided in the security review
(see `data-authenticity-brainstorm.md` for the options that were weighed).

## What the app checks

1. **Signature (C).** It fetches `manifest.json` and `manifest.sig` from `main` and verifies
   an Ed25519 signature over the manifest's exact bytes against the public key compiled into the
   app (`ManifestSignatureVerifier.production`). No valid signature means nothing is read from the
   manifest and the sync fails closed (`VerbSyncError.untrusted`); the cached data stays in use.
2. **Hashes.** Each data file must match the SHA-256 in the (now trusted) manifest, so the
   signature covers the data too.
3. **Pinned tag (B).** A manifest entry may carry `"ref": "data-v7"`. The app then fetches that
   file from the tag, not from `main`, so a later push to `main` cannot alter what the signed
   manifest points at. Refs are limited to `[A-Za-z0-9._-]`, max 64 characters.
4. **No rollback (D).** The app remembers the highest version it ever accepted per file (it survives
   app updates) and refuses an older manifest, so an old, validly signed manifest cannot be replayed.
   Versions only go up: never lower one by hand.

Anyone who can push to `main` but does not hold the signing key can still change `data/`, but
the app will reject it. They cannot sign a manifest.

## First-time setup (the app syncs nothing until this is done)

The public key in the app starts empty, so every sync fails closed. Once:

```
pip install cryptography
python3 scripts/sign_manifest.py keygen
```

- The private key is written to `~/.config/verbtable/manifest-signing.key` (mode 0600). **Back it
  up offline** (password manager, encrypted drive). If it is lost the app can only be re-keyed by
  shipping a new build. Never commit it (`*.key` is gitignored).
- Paste the printed public key line into `ManifestSignatureVerifier.production` in
  `Packages/VerbKit/Sources/VerbKit/Data/ManifestSignatureVerifier.swift`.
- `python3 scripts/sign_manifest.py sign`, then commit `data/manifest.sig` with the key change.
  Push these together, and only ship an app build once `main` has the signed manifest.

## Releasing a data update

```
# 1. edit data/*.json, then regenerate and commit (do not push yet)
python3 scripts/update_data.py
git commit -am "data: <what changed>"

# 2. tag that commit with a NEW name (never move or reuse a tag) and push only the tag
git tag data-v8 && git push origin data-v8

# 3. point the manifest at the tag, sign it, push main
python3 scripts/update_data.py --ref data-v8
python3 scripts/sign_manifest.py sign
git commit -am "data: release data-v8" && git push
```

`update_data.py` only keeps an old `ref` while that file is unchanged; an edited file loses its
stale tag, and the app then reads it from `main` (still signed and hash-checked). Before pushing,
`python3 scripts/sign_manifest.py verify` confirms the signature matches the manifest and the key
in the app. An unsigned or mismatched manifest on `main` just makes apps keep their cached data.

## Rotating the key

`ManifestSignatureVerifier` trusts any key in its list. To rotate: add the new public key next to
the old one and ship that build; once enough users have updated, sign with the new key; later,
drop the old key. If the private key is **compromised**, ship a build with only the new key
immediately: until users update, an attacker holding the old key can still sign.

## CI

`.github/workflows/data.yml` runs the script tests, `update_data.py --check` and
`sign_manifest.py verify` when `data/` or `scripts/` change. It fails until the public key is in the app
and `manifest.sig` is committed (first-time setup above), and again whenever a manifest change is
pushed unsigned. To block merges on it, make the `data` check required in branch protection.

## Related, not done here

- Branch and tag protection on GitHub (option A) is still to do; it protects the tags in step 2.
