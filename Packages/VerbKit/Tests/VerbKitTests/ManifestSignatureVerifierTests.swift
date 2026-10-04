import CryptoKit
import XCTest
@testable import VerbKit

final class ManifestSignatureVerifierTests: XCTestCase {
    private let manifest = Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8)

    func testAcceptsASignatureFromATrustedKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = ManifestSignatureVerifier(publicKeys: [key.publicKey.rawRepresentation])
        XCTAssertTrue(verifier.isValid(signature: try key.signature(for: manifest), for: manifest))
    }

    func testRejectsAChangedManifest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = ManifestSignatureVerifier(publicKeys: [key.publicKey.rawRepresentation])
        let signature = try key.signature(for: manifest)
        XCTAssertFalse(verifier.isValid(signature: signature, for: manifest + Data(" ".utf8)))
    }

    func testRejectsAnUntrustedKey() throws {
        let trusted = Curve25519.Signing.PrivateKey()
        let attacker = Curve25519.Signing.PrivateKey()
        let verifier = ManifestSignatureVerifier(publicKeys: [trusted.publicKey.rawRepresentation])
        XCTAssertFalse(verifier.isValid(signature: try attacker.signature(for: manifest), for: manifest))
    }

    func testEitherOfTwoKeysIsTrustedForRotation() throws {
        let old = Curve25519.Signing.PrivateKey()
        let new = Curve25519.Signing.PrivateKey()
        let verifier = ManifestSignatureVerifier(publicKeys: [old.publicKey.rawRepresentation, new.publicKey.rawRepresentation])
        XCTAssertTrue(verifier.isValid(signature: try old.signature(for: manifest), for: manifest))
        XCTAssertTrue(verifier.isValid(signature: try new.signature(for: manifest), for: manifest))
    }

    func testNoKeysTrustsNothing() throws {
        let key = Curve25519.Signing.PrivateKey()
        XCTAssertFalse(ManifestSignatureVerifier(publicKeys: []).isValid(signature: try key.signature(for: manifest), for: manifest))
        XCTAssertFalse(ManifestSignatureVerifier(base64Keys: ["not base64!"]).isValid(signature: Data(count: 64), for: manifest))
    }

    func testBase64KeysDecode() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = ManifestSignatureVerifier(base64Keys: [key.publicKey.rawRepresentation.base64EncodedString() + "\n"])
        XCTAssertTrue(verifier.isValid(signature: try key.signature(for: manifest), for: manifest))
    }

    func testProductionKeyIsNotACommittedTestKey() {
        // Guards against shipping with no key configured by mistake: either it is empty
        // (fail closed, nothing syncs) or it rejects an arbitrary signature.
        XCTAssertFalse(ManifestSignatureVerifier.production.isValid(signature: Data(count: 64), for: manifest))
    }
}
