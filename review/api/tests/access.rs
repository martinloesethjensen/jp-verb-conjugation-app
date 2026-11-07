mod support;

use review_api::access::{parse_certs, verify, AccessError, Audience, KeyCache};
use serde_json::{json, Value};
use support::*;

fn good_claims() -> Value {
    claims_for(Some("a@example.com"), "reviewer-aud")
}

fn check(token: &str) -> Result<(review_api::access::Claims, Audience), AccessError> {
    verify(token, &[jwk()], &cfg(), NOW)
}

#[test]
fn a_good_reviewer_token_verifies() {
    let (claims, aud) = check(&token(rs_header(), good_claims())).unwrap();
    assert_eq!(claims.email.as_deref(), Some("a@example.com"));
    assert_eq!(aud, Audience::Reviewer);
}

#[test]
fn an_admin_token_has_the_admin_audience() {
    let mut claims = good_claims();
    claims["aud"] = json!("admin-aud");
    let (_, aud) = check(&token(rs_header(), claims)).unwrap();
    assert_eq!(aud, Audience::Admin);
}

#[test]
fn none_and_hs256_are_rejected() {
    assert_eq!(
        check(&token_with_alg("none", good_claims())),
        Err(AccessError::Algorithm)
    );
    assert_eq!(
        check(&token_with_alg("HS256", good_claims())),
        Err(AccessError::Algorithm)
    );
}

#[test]
fn a_tampered_payload_fails_the_signature() {
    let real = token(rs_header(), good_claims());
    let mut forged_claims = good_claims();
    forged_claims["email"] = json!("owner@example.com");
    let forged = token(rs_header(), forged_claims);
    let parts: Vec<&str> = real.split('.').collect();
    let forged_payload = forged.split('.').nth(1).unwrap();
    let spliced = format!("{}.{}.{}", parts[0], forged_payload, parts[2]);
    assert_eq!(check(&spliced), Err(AccessError::Signature));
}

#[test]
fn a_token_signed_by_another_key_with_the_same_kid_fails_the_signature() {
    let forged = token_signed_by(other_key(), rs_header(), good_claims());
    assert_eq!(check(&forged), Err(AccessError::Signature));
}

#[test]
fn an_unknown_kid_is_unknown_key() {
    let header = json!({"alg": "RS256", "kid": "k2", "typ": "JWT"});
    assert_eq!(
        check(&token(header, good_claims())),
        Err(AccessError::UnknownKey)
    );
}

#[test]
fn expired_tokens_are_rejected() {
    let mut claims = good_claims();
    claims["exp"] = json!(NOW - 1);
    assert_eq!(
        check(&token(rs_header(), claims)),
        Err(AccessError::Expired)
    );
}

#[test]
fn future_tokens_beyond_60s_are_rejected() {
    let mut claims = good_claims();
    claims["nbf"] = json!(NOW + 61);
    assert_eq!(
        check(&token(rs_header(), claims.clone())),
        Err(AccessError::NotYetValid)
    );
    claims["nbf"] = json!(NOW + 60);
    assert!(check(&token(rs_header(), claims.clone())).is_ok());
    claims["nbf"] = json!(NOW - 5);
    claims["iat"] = json!(NOW + 61);
    assert_eq!(
        check(&token(rs_header(), claims)),
        Err(AccessError::NotYetValid)
    );
}

#[test]
fn wrong_issuer_is_rejected() {
    let mut claims = good_claims();
    claims["iss"] = json!("https://evil.cloudflareaccess.com");
    assert_eq!(check(&token(rs_header(), claims)), Err(AccessError::Issuer));
}

#[test]
fn wrong_audience_is_rejected() {
    let mut claims = good_claims();
    claims["aud"] = json!(["other"]);
    assert_eq!(
        check(&token(rs_header(), claims)),
        Err(AccessError::Audience)
    );
}

#[test]
fn garbage_is_malformed() {
    for t in ["", "a.b", "a.b.c", "!!.!!.!!", "a.b.c.d"] {
        assert_eq!(check(t), Err(AccessError::Malformed), "{t:?}");
    }
}

#[test]
fn a_service_token_verifies_without_an_email() {
    let (claims, _) = check(&token(rs_header(), claims_for(None, "reviewer-aud"))).unwrap();
    assert_eq!(claims.email, None);
}

#[test]
fn certs_are_parsed() {
    let key = jwk();
    let body = json!({
        "keys": [{"kid": "k1", "kty": "RSA", "alg": "RS256", "use": "sig", "e": key.e, "n": key.n}],
        "public_cert": {"kid": "k1", "cert": "-----BEGIN CERTIFICATE-----"},
        "public_certs": [{"kid": "k1", "cert": "-----BEGIN CERTIFICATE-----"}]
    });
    assert_eq!(parse_certs(&body.to_string()).unwrap(), vec![key]);
    assert_eq!(parse_certs("not json"), Err(AccessError::Malformed));
}

#[test]
fn the_key_cache_refetches_sparingly() {
    let mut cache = KeyCache::default();
    assert!(cache.needs_fetch("k1", NOW));
    cache.store(vec![jwk()], NOW);
    assert!(!cache.needs_fetch("k1", NOW + 10));
    assert!(!cache.needs_fetch("k9", NOW + 59));
    assert!(cache.needs_fetch("k9", NOW + 60));
    assert!(cache.needs_fetch("k1", NOW + 3600));
    assert_eq!(cache.keys, vec![jwk()]);
}

#[test]
fn concurrent_requests_with_an_unknown_kid_start_one_fetch() {
    // The glue claims the fetch before awaiting it, so requests arriving meanwhile use the current keys.
    let mut cache = KeyCache::default();
    cache.store(vec![jwk()], NOW);
    assert!(cache.begin_fetch("k9", NOW + 60));
    assert!(!cache.begin_fetch("k9", NOW + 60));
    assert!(!cache.begin_fetch("k8", NOW + 61));
    assert_eq!(cache.keys, vec![jwk()]);
}

#[test]
fn a_cold_cache_lets_every_request_fetch() {
    // With no keys yet there is nothing to fall back on, so nobody waits on someone else's fetch.
    let mut cache = KeyCache::default();
    assert!(cache.begin_fetch("k1", NOW));
    assert!(cache.begin_fetch("k1", NOW));
}

#[test]
fn the_config_refuses_missing_or_identical_audiences() {
    use review_api::access::AccessConfig;
    let ok = AccessConfig::new("team.cloudflareaccess.com", "reviewer-aud", "admin-aud");
    assert_eq!(ok, Some(cfg()));
    // The same tag for both applications would let an email-PIN sign-in count as the admin application.
    assert_eq!(
        AccessConfig::new("team.cloudflareaccess.com", "same", "same"),
        None
    );
    assert_eq!(AccessConfig::new("", "a", "b"), None);
    assert_eq!(AccessConfig::new("t", " ", "b"), None);
    assert_eq!(AccessConfig::new("t", "a", ""), None);
}

#[test]
fn export_config_needs_a_distinct_aud_and_a_client_id() {
    let with = |aud: &str, id: &str| cfg().with_export(aud, id).export;
    assert!(with("export-aud", "client.access").is_some());
    assert_eq!(with("", "client.access"), None);
    assert_eq!(with("export-aud", " "), None);
    assert_eq!(with("reviewer-aud", "client.access"), None);
    assert_eq!(with("admin-aud", "client.access"), None);
}
