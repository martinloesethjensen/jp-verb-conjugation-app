#!/usr/bin/env python3
"""Signs data/manifest.json so the app will trust it.

    python3 scripts/sign_manifest.py keygen   # once: make the signing key
    python3 scripts/sign_manifest.py sign     # after every manifest change
    python3 scripts/sign_manifest.py verify   # check data/manifest.sig (also fine in CI)

The signature is Ed25519 over the exact bytes of data/manifest.json, stored base64 in
data/manifest.sig. The app embeds the matching public key (ManifestSignatureVerifier.swift)
and refuses any manifest that does not verify. The private key never goes in the repo:
it lives at ~/.config/verbtable/manifest-signing.key (mode 0600), or wherever
--key / $VERBTABLE_SIGNING_KEY points. See docs/security/data-signing.md.

Needs the `cryptography` package (pip install cryptography). update_data.py does not.
"""
import argparse
import base64
import os
import re
import sys
from pathlib import Path

try:
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
except ImportError:  # pragma: no cover
    sys.exit("this script needs the 'cryptography' package: pip install cryptography")

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_KEY = Path.home() / ".config" / "verbtable" / "manifest-signing.key"
VERIFIER_SWIFT = ROOT / "Packages/VerbKit/Sources/VerbKit/Data/ManifestSignatureVerifier.swift"
KEY_LINE = re.compile(r'^\s*"([A-Za-z0-9+/]{43}=)"\s*,?\s*(?://.*)?$', re.MULTILINE)


def raw_public(key):
    return key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def key_path(arg):
    return Path(arg or os.environ.get("VERBTABLE_SIGNING_KEY") or DEFAULT_KEY).expanduser()


def keygen(path):
    """Writes a new private key (refusing to overwrite one); returns the base64 public key."""
    if path.exists():
        raise SystemExit(f"{path} already exists; refusing to overwrite a signing key")
    key = Ed25519PrivateKey.generate()
    raw = key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(base64.b64encode(raw).decode() + "\n")
    return base64.b64encode(raw_public(key)).decode()


def load_private(path):
    if not path.exists():
        raise SystemExit(f"no signing key at {path}; run 'sign_manifest.py keygen' first")
    if os.name == "posix" and path.stat().st_mode & 0o077:
        raise SystemExit(f"{path} is readable by others; run: chmod 600 {path}")
    return Ed25519PrivateKey.from_private_bytes(base64.b64decode(path.read_text().strip()))


def sign(manifest_path, sig_path, private):
    signature = private.sign(manifest_path.read_bytes())
    sig_path.write_text(base64.b64encode(signature).decode() + "\n")


def trusted_keys(swift_path=VERIFIER_SWIFT):
    """The public keys the app embeds, read from the Swift source so the two cannot drift."""
    return KEY_LINE.findall(swift_path.read_text(encoding="utf-8"))


def verify(manifest_path, sig_path, public_keys):
    """True when the signature is valid for the manifest under any of the base64 `public_keys`."""
    try:
        signature = base64.b64decode(sig_path.read_text().strip(), validate=True)
    except (OSError, ValueError):
        return False
    data = manifest_path.read_bytes()
    for text in public_keys:
        try:
            Ed25519PublicKey.from_public_bytes(base64.b64decode(text)).verify(signature, data)
            return True
        except (InvalidSignature, ValueError):
            continue
    return False


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["keygen", "sign", "verify"])
    parser.add_argument("--data-dir", default=str(ROOT / "data"))
    parser.add_argument("--key", help="private key file (default: $VERBTABLE_SIGNING_KEY or ~/.config/verbtable/manifest-signing.key)")
    args = parser.parse_args(argv)
    data_dir = Path(args.data_dir)
    manifest_path, sig_path = data_dir / "manifest.json", data_dir / "manifest.sig"

    if args.command == "keygen":
        path = key_path(args.key)
        public = keygen(path)
        print(f"private key written to {path} (back it up somewhere safe, offline; never commit it)")
        print("paste this public key into ManifestSignatureVerifier.production:")
        print(f'        "{public}",')
        return 0

    if args.command == "sign":
        private = load_private(key_path(args.key))
        public = base64.b64encode(raw_public(private)).decode()
        if public not in trusted_keys():
            print(f"warning: the app does not trust this key yet ({public}); add it to ManifestSignatureVerifier.production", file=sys.stderr)
        sign(manifest_path, sig_path, private)
        print(f"signed {manifest_path.name} -> {sig_path.name}")
        return 0

    keys = trusted_keys()
    if not keys:
        print("no public key is configured in ManifestSignatureVerifier.swift", file=sys.stderr)
        return 1
    if verify(manifest_path, sig_path, keys):
        print("manifest.sig is valid")
        return 0
    print("manifest.sig is missing or does not match manifest.json: run sign_manifest.py sign", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
