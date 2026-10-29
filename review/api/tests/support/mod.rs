//! Test helpers: one RSA key per test binary, Access-like tokens signed with it.
#![allow(dead_code)]

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use review_api::access::{AccessConfig, Jwk};
use rsa::pkcs1v15::SigningKey;
use rsa::pkcs8::EncodePublicKey;
use rsa::signature::{SignatureEncoding, Signer};
use rsa::traits::PublicKeyParts;
use rsa::{RsaPrivateKey, RsaPublicKey};
use serde_json::{json, Value};
use sha2::Sha256;
use std::sync::OnceLock;

pub const NOW: i64 = 1_800_000_000;

pub fn key() -> &'static RsaPrivateKey {
    static KEY: OnceLock<RsaPrivateKey> = OnceLock::new();
    KEY.get_or_init(|| RsaPrivateKey::new(&mut rand::thread_rng(), 2048).unwrap())
}

/// A second key, for forgeries that reuse the real key's kid.
pub fn other_key() -> &'static RsaPrivateKey {
    static KEY: OnceLock<RsaPrivateKey> = OnceLock::new();
    KEY.get_or_init(|| RsaPrivateKey::new(&mut rand::thread_rng(), 2048).unwrap())
}

pub fn jwk_for(public: &RsaPublicKey, kid: &str) -> Jwk {
    Jwk {
        kid: kid.into(),
        n: URL_SAFE_NO_PAD.encode(public.n().to_bytes_be()),
        e: URL_SAFE_NO_PAD.encode(public.e().to_bytes_be()),
    }
}

pub fn jwk() -> Jwk {
    jwk_for(&key().to_public_key(), "k1")
}

pub fn cfg() -> AccessConfig {
    AccessConfig {
        team_domain: "team.cloudflareaccess.com".into(),
        aud: "reviewer-aud".into(),
        admin_aud: "admin-aud".into(),
    }
}

pub fn rs_header() -> Value {
    json!({"alg": "RS256", "kid": "k1", "typ": "JWT"})
}

fn segment(value: &Value) -> String {
    URL_SAFE_NO_PAD.encode(serde_json::to_vec(value).unwrap())
}

pub fn token_signed_by(signer: &RsaPrivateKey, header: Value, claims: Value) -> String {
    let input = format!("{}.{}", segment(&header), segment(&claims));
    let signature = SigningKey::<Sha256>::new(signer.clone()).sign(input.as_bytes());
    format!("{input}.{}", URL_SAFE_NO_PAD.encode(signature.to_bytes()))
}

pub fn token(header: Value, claims: Value) -> String {
    token_signed_by(key(), header, claims)
}

/// An unsigned ("none") or HS256 token, the classic algorithm-confusion forgeries. HS256 uses the public
/// key's DER bytes as the HMAC secret.
pub fn token_with_alg(alg: &str, claims: Value) -> String {
    let header = json!({"alg": alg, "kid": "k1", "typ": "JWT"});
    let input = format!("{}.{}", segment(&header), segment(&claims));
    if alg == "none" {
        return format!("{input}.");
    }
    let secret = key().to_public_key().to_public_key_der().unwrap();
    format!(
        "{input}.{}",
        URL_SAFE_NO_PAD.encode(hmac_sha256(secret.as_bytes(), input.as_bytes()))
    )
}

fn hmac_sha256(key: &[u8], message: &[u8]) -> Vec<u8> {
    use sha2::Digest;
    let mut block = [0u8; 64];
    if key.len() > 64 {
        block[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        block[..key.len()].copy_from_slice(key);
    }
    let inner: Vec<u8> = block
        .iter()
        .map(|b| b ^ 0x36)
        .chain(message.iter().copied())
        .collect();
    let inner_hash = Sha256::digest(&inner);
    let outer: Vec<u8> = block
        .iter()
        .map(|b| b ^ 0x5c)
        .chain(inner_hash.iter().copied())
        .collect();
    Sha256::digest(&outer).to_vec()
}

pub fn claims_for(email: Option<&str>, aud: &str) -> Value {
    let mut claims = json!({"aud": [aud], "iss": "https://team.cloudflareaccess.com",
                            "exp": NOW + 600, "iat": NOW - 5, "nbf": NOW - 5});
    match email {
        Some(email) => claims["email"] = json!(email),
        None => claims["common_name"] = json!("service-token-id.access"),
    }
    claims
}
pub mod sqlite;
