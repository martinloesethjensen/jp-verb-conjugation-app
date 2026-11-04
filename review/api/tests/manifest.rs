use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use review_api::data::DataFile;
use review_api::manifest::{
    file_url, is_older, is_valid_ref, manifest_url, sha256_hex, signature_url, verify, Entry,
    ManifestError, RAW_ROOT, TRUSTED_KEYS,
};

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn real(name: &str) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{name}")).unwrap()
}

fn real_sig() -> String {
    String::from_utf8(real("manifest.sig"))
        .unwrap()
        .trim()
        .to_string()
}

/// The base64 keys in the app's production list, read the way scripts/sign_manifest.py reads them.
fn swift_keys() -> Vec<String> {
    let path =
        format!("{ROOT}/Packages/VerbKit/Sources/VerbKit/Data/ManifestSignatureVerifier.swift");
    std::fs::read_to_string(path)
        .unwrap()
        .lines()
        .filter_map(|line| {
            let t = line.trim().trim_end_matches(',');
            let inner = t.strip_prefix('"')?.strip_suffix('"')?;
            let ok = inner.len() == 44
                && inner.ends_with('=')
                && inner[..43]
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/');
            ok.then(|| inner.to_string())
        })
        .collect()
}

#[test]
fn the_published_manifest_verifies_with_the_apps_key() {
    let m = verify(&real("manifest.json"), &real_sig(), TRUSTED_KEYS).unwrap();
    for file in DataFile::ALL {
        let entry = m
            .entry(file)
            .unwrap_or_else(|| panic!("{}", file.file_name()));
        assert_eq!(
            entry.sha256,
            sha256_hex(&real(file.file_name())),
            "{}",
            file.file_name()
        );
    }
}

#[test]
fn one_changed_byte_breaks_it() {
    let mut bytes = real("manifest.json");
    let i = bytes.len() / 2;
    bytes[i] ^= 1;
    assert_eq!(
        verify(&bytes, &real_sig(), TRUSTED_KEYS).err(),
        Some(ManifestError::BadSignature)
    );
}

#[test]
fn a_signature_from_another_key_is_refused() {
    let other = SigningKey::from_bytes(&[7u8; 32]);
    let manifest = real("manifest.json");
    let sig = STANDARD.encode(other.sign(&manifest).to_bytes());
    assert_eq!(
        verify(&manifest, &sig, TRUSTED_KEYS).err(),
        Some(ManifestError::BadSignature)
    );
    // ... and accepted when that key is trusted, so the check is the key, not the bytes.
    let other_public = STANDARD.encode(other.verifying_key().to_bytes());
    assert!(verify(&manifest, &sig, &[other_public.as_str()]).is_ok());
    assert_eq!(
        verify(&manifest, "not base64!", TRUSTED_KEYS).err(),
        Some(ManifestError::BadSignature)
    );
}

#[test]
fn the_trusted_keys_are_the_ones_the_app_embeds() {
    assert_eq!(swift_keys(), TRUSTED_KEYS);
}

#[test]
fn refs_follow_the_apps_rule() {
    for ok in ["v1.2.0", "data-2026_11", "a", &"a".repeat(64)] {
        assert!(is_valid_ref(ok), "{ok}");
    }
    let long = "a".repeat(65);
    for bad in [
        "",
        "../evil",
        "main/../../x",
        ".hidden",
        "-x",
        "_x",
        "a b",
        "é",
        "a/b",
        long.as_str(),
    ] {
        assert!(!is_valid_ref(bad), "{bad}");
    }
}

#[test]
fn urls() {
    let e = |r: Option<&str>| Entry {
        version: "1.0.0".into(),
        sha256: "x".into(),
        git_ref: r.map(Into::into),
    };
    assert_eq!(
        file_url(DataFile::Words, &e(None)).unwrap(),
        format!("{RAW_ROOT}main/data/words.json")
    );
    assert_eq!(
        file_url(DataFile::Words, &e(Some("v2"))).unwrap(),
        format!("{RAW_ROOT}v2/data/words.json")
    );
    assert!(matches!(
        file_url(DataFile::Words, &e(Some("../x"))),
        Err(ManifestError::BadRef(_))
    ));
    assert_eq!(manifest_url(), format!("{RAW_ROOT}main/data/manifest.json"));
    assert_eq!(signature_url(), format!("{RAW_ROOT}main/data/manifest.sig"));
    assert_eq!(
        RAW_ROOT,
        "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/"
    );
}

#[test]
fn entries_carry_their_ref() {
    let manifest =
        br#"{"version":"1.0.0","sha256":"a","ref":"v1","words":{"version":"2.0.0","sha256":"b"}}"#;
    let key = SigningKey::from_bytes(&[9u8; 32]);
    let sig = STANDARD.encode(key.sign(manifest).to_bytes());
    let public = STANDARD.encode(key.verifying_key().to_bytes());
    let m = verify(manifest, &sig, &[public.as_str()]).unwrap();
    assert_eq!(
        m.entry(DataFile::Verbs).unwrap().git_ref.as_deref(),
        Some("v1")
    );
    assert_eq!(m.entry(DataFile::Words).unwrap().version, "2.0.0");
    assert_eq!(m.entry(DataFile::Words).unwrap().git_ref, None);
    assert!(m.entry(DataFile::Counters).is_none());
}

#[test]
fn versions_compare_numerically() {
    assert!(is_older("1.9.0", "1.10.0"));
    assert!(!is_older("1.10.0", "1.9.0"));
    assert!(!is_older("1.17.0", "1.17.0"));
    assert!(is_older("1.17.0", "2.0.0"));
    assert!(is_older("junk", "1.0.0"));
    assert!(is_older("1.0", "1.0.0"));
}
