import CryptoKit
import Foundation

/// Checks the Ed25519 signature on the exact bytes of `manifest.json`. The hashes
/// in the manifest are only worth trusting once this passes: the manifest is
/// served from the same place as the data, so a hash alone proves nothing about who
/// published it.
///
/// More than one key can be trusted at once, so a key can be rotated by shipping an
/// app that trusts both, then signing with the new one.
public struct ManifestSignatureVerifier: Sendable {
    /// Raw 32-byte public keys. Kept as bytes so the type stays trivially `Sendable`.
    private let publicKeys: [Data]

    public init(publicKeys: [Data]) {
        self.publicKeys = publicKeys
    }

    /// `base64Keys` are base64 of the raw 32-byte public key, as printed by
    /// `scripts/sign_manifest.py keygen`. Entries that don't decode are dropped,
    /// so a mistyped key means "trust nothing", never "trust anything".
    public init(base64Keys: [String]) {
        self.init(publicKeys: base64Keys.compactMap {
            Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    public func isValid(signature: Data, for manifest: Data) -> Bool {
        publicKeys.contains { raw in
            guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
            return key.isValidSignature(signature, for: manifest)
        }
    }

    /// The key(s) the shipping app trusts. Empty until the maintainer runs
    /// `scripts/sign_manifest.py keygen` and pastes the public key here (see
    /// docs/security/data-signing.md). While it is empty every sync fails closed.
    public static let production = ManifestSignatureVerifier(base64Keys: [
        "rratyJ5yBhlonBpzW/WGUSKL+nw4lHLn7iIcVl2RDH0=",
    ])
}
