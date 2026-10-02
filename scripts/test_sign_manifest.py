import base64
import os
import stat
import tempfile
import unittest
from pathlib import Path

import sign_manifest as sm
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class SignManifestTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.manifest = self.dir / "manifest.json"
        self.sig = self.dir / "manifest.sig"
        self.manifest.write_text('{"version": "1.0.0", "sha256": "abc"}\n')

    def test_sign_then_verify(self):
        key = Ed25519PrivateKey.generate()
        sm.sign(self.manifest, self.sig, key)
        public = base64.b64encode(sm.raw_public(key)).decode()
        self.assertTrue(sm.verify(self.manifest, self.sig, [public]))

    def test_a_changed_manifest_fails(self):
        key = Ed25519PrivateKey.generate()
        sm.sign(self.manifest, self.sig, key)
        self.manifest.write_text('{"version": "1.0.0", "sha256": "evil"}\n')
        public = base64.b64encode(sm.raw_public(key)).decode()
        self.assertFalse(sm.verify(self.manifest, self.sig, [public]))

    def test_another_key_fails_and_a_second_trusted_key_passes(self):
        key, other = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()
        sm.sign(self.manifest, self.sig, key)
        b64 = lambda k: base64.b64encode(sm.raw_public(k)).decode()
        self.assertFalse(sm.verify(self.manifest, self.sig, [b64(other)]))
        self.assertTrue(sm.verify(self.manifest, self.sig, [b64(other), b64(key)]))

    def test_missing_or_garbage_signature_fails(self):
        key = Ed25519PrivateKey.generate()
        public = base64.b64encode(sm.raw_public(key)).decode()
        self.assertFalse(sm.verify(self.manifest, self.sig, [public]))
        self.sig.write_text("not base64 !!")
        self.assertFalse(sm.verify(self.manifest, self.sig, [public]))

    def test_no_keys_trusts_nothing(self):
        sm.sign(self.manifest, self.sig, Ed25519PrivateKey.generate())
        self.assertFalse(sm.verify(self.manifest, self.sig, []))

    def test_keygen_writes_a_private_file_and_refuses_to_overwrite(self):
        path = self.dir / "sub" / "key"
        public = sm.keygen(path)
        self.assertEqual(len(base64.b64decode(public)), 32)
        if os.name == "posix":
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        with self.assertRaises(SystemExit):
            sm.keygen(path)
        # the stored key loads and matches the printed public key
        self.assertEqual(base64.b64encode(sm.raw_public(sm.load_private(path))).decode(), public)

    def test_loading_a_group_readable_key_is_refused(self):
        path = self.dir / "key"
        sm.keygen(path)
        path.chmod(0o644)
        if os.name == "posix":
            with self.assertRaises(SystemExit):
                sm.load_private(path)

    def test_trusted_keys_are_read_from_the_swift_source(self):
        swift = self.dir / "V.swift"
        key = base64.b64encode(bytes(range(32))).decode()
        swift.write_text(f'static let production = X(base64Keys: [\n    // "{key}",\n        "{key}",\n    ])\n')
        # the commented-out example line must not count
        self.assertEqual(sm.trusted_keys(swift), [key])

    def test_the_committed_swift_file_has_a_parsable_key_list(self):
        # empty until the maintainer pastes a key; every entry that is there must be a 32-byte key
        for key in sm.trusted_keys():
            self.assertEqual(len(base64.b64decode(key)), 32)


if __name__ == "__main__":
    unittest.main()
