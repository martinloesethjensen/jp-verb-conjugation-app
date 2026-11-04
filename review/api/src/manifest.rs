//! The signed `data/manifest.json`, checked the way the app checks it: an Ed25519 signature over the
//! exact bytes, with the public key the app embeds (`ManifestSignatureVerifier.production`), and each
//! file's SHA-256 and version taken from its entry.

use crate::data::DataFile;
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Deserialize;
use sha2::{Digest, Sha256};

/// The keys the app trusts, copied from `ManifestSignatureVerifier.swift` (a test keeps them equal).
pub const TRUSTED_KEYS: &[&str] = &["rratyJ5yBhlonBpzW/WGUSKL+nw4lHLn7iIcVl2RDH0="];

/// The repo's raw files; the manifest and signature always come from `main`.
pub const RAW_ROOT: &str =
    "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ManifestError {
    BadSignature,
    Malformed,
    MissingEntry(DataFile),
    BadRef(String),
}

/// One file's line in the manifest.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub version: String,
    pub sha256: String,
    /// The release tag the file is fetched from; `main` when absent.
    pub git_ref: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct RawEntry {
    version: String,
    sha256: String,
    #[serde(default, rename = "ref")]
    git_ref: Option<String>,
}

impl From<&RawEntry> for Entry {
    fn from(raw: &RawEntry) -> Entry {
        Entry {
            version: raw.version.clone(),
            sha256: raw.sha256.clone(),
            git_ref: raw.git_ref.clone(),
        }
    }
}

/// A verified manifest. The verbs entry is the top level; the others are nested objects.
#[derive(Debug, Clone, Deserialize)]
pub struct Manifest {
    #[serde(flatten)]
    verbs: RawEntry,
    #[serde(default)]
    words: Option<RawEntry>,
    #[serde(default)]
    counters: Option<RawEntry>,
    #[serde(default)]
    grammar: Option<RawEntry>,
    #[serde(default)]
    furigana: Option<RawEntry>,
    #[serde(default)]
    forms: Option<RawEntry>,
}

impl Manifest {
    pub fn entry(&self, file: DataFile) -> Option<Entry> {
        let raw = match file {
            DataFile::Verbs => Some(&self.verbs),
            DataFile::Words => self.words.as_ref(),
            DataFile::Counters => self.counters.as_ref(),
            DataFile::Grammar => self.grammar.as_ref(),
            DataFile::Furigana => self.furigana.as_ref(),
            DataFile::Forms => self.forms.as_ref(),
        };
        raw.map(Entry::from)
    }
}

/// Checks `signature_b64` over the exact `manifest` bytes against any of `keys`, then parses it.
pub fn verify(
    manifest: &[u8],
    signature_b64: &str,
    keys: &[&str],
) -> Result<Manifest, ManifestError> {
    let signature = STANDARD
        .decode(signature_b64.trim())
        .ok()
        .and_then(|bytes| Signature::from_slice(&bytes).ok())
        .ok_or(ManifestError::BadSignature)?;
    let trusted = keys.iter().any(|key| {
        STANDARD
            .decode(key)
            .ok()
            .and_then(|bytes| <[u8; 32]>::try_from(bytes).ok())
            .and_then(|bytes| VerifyingKey::from_bytes(&bytes).ok())
            .is_some_and(|key| key.verify(manifest, &signature).is_ok())
    });
    if !trusted {
        return Err(ManifestError::BadSignature);
    }
    serde_json::from_slice(manifest).map_err(|_| ManifestError::Malformed)
}

/// The app's rule (`GitHubVerbFetcher.isValidRef`): it ends up in a URL path.
pub fn is_valid_ref(r: &str) -> bool {
    let mut chars = r.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    r.len() <= 64
        && first.is_ascii_alphanumeric()
        && chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

pub fn manifest_url() -> String {
    format!("{RAW_ROOT}main/data/manifest.json")
}

pub fn signature_url() -> String {
    format!("{RAW_ROOT}main/data/manifest.sig")
}

/// Where `file` is published: its entry's ref, or `main`. An invalid ref is refused.
pub fn file_url(file: DataFile, entry: &Entry) -> Result<String, ManifestError> {
    let git_ref = match &entry.git_ref {
        Some(r) if !is_valid_ref(r) => return Err(ManifestError::BadRef(r.clone())),
        Some(r) => r.as_str(),
        None => "main",
    };
    Ok(format!("{RAW_ROOT}{git_ref}/data/{}", file.file_name()))
}

fn parts(version: &str) -> Option<[u64; 3]> {
    let mut it = version.split('.').map(|p| p.parse::<u64>().ok());
    let v = [it.next()??, it.next()??, it.next()??];
    it.next().is_none().then_some(v)
}

/// True when `candidate` is an older `major.minor.patch` than `current` (as `DataVersion.isOlder`).
/// An unparsable candidate counts as older, so a malformed version is refused.
pub fn is_older(candidate: &str, current: &str) -> bool {
    match (parts(candidate), parts(current)) {
        (Some(c), Some(cur)) => c < cur,
        (None, _) => true,
        (Some(_), None) => false,
    }
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}
