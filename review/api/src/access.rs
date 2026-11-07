//! Cloudflare Access tokens (the `Cf-Access-Jwt-Assertion` header): RS256 JWTs signed by the team's keys.
//!
//! Every request is checked here before anything else. Nothing in this module trusts a header other than
//! the token itself, and only RS256 is accepted, so an unsigned or HMAC token can't pass as a real one.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rsa::pkcs1v15::{Signature, VerifyingKey};
use rsa::signature::Verifier;
use rsa::{BigUint, RsaPublicKey};
use serde::{Deserialize, Deserializer};
use sha2::Sha256;

/// How far in the future `nbf` and `iat` may be, for clock skew between Access and the Worker.
pub const LEEWAY_SECONDS: i64 = 60;
/// Refetch the team's keys at least this often.
pub const KEYS_MAX_AGE_SECONDS: i64 = 3600;
/// An unknown `kid` refetches the keys at most this often, so a flood of made-up kids can't.
pub const UNKNOWN_KID_REFETCH_SECONDS: i64 = 60;

#[derive(Debug, Clone, PartialEq)]
pub struct AccessConfig {
    /// `<team>.cloudflareaccess.com`
    pub team_domain: String,
    /// The reviewer application's AUD tag.
    pub aud: String,
    /// The admin application's AUD tag (GitHub sign-in only).
    pub admin_aud: String,
    /// The export application (`/api/export`, service token only); `None` turns export off.
    pub export: Option<ExportAccess>,
}

/// The Access application in front of `GET /api/export` and the one service token it lets through.
#[derive(Debug, Clone, PartialEq)]
pub struct ExportAccess {
    pub aud: String,
    /// The service token's client id, which Access puts in the token's `common_name`.
    pub client_id: String,
}

impl AccessConfig {
    /// `None` when a value is blank or both applications have the same AUD tag: then an email-PIN sign-in
    /// would count as the admin (GitHub) application, so the Worker refuses to run instead.
    pub fn new(team_domain: &str, aud: &str, admin_aud: &str) -> Option<AccessConfig> {
        let [team_domain, aud, admin_aud] = [team_domain, aud, admin_aud].map(str::trim);
        if team_domain.is_empty() || aud.is_empty() || admin_aud.is_empty() || aud == admin_aud {
            return None;
        }
        Some(AccessConfig {
            team_domain: team_domain.into(),
            aud: aud.into(),
            admin_aud: admin_aud.into(),
            export: None,
        })
    }

    /// Turns export on, unless a value is blank or the AUD tag is one of the other applications'.
    pub fn with_export(mut self, aud: &str, client_id: &str) -> AccessConfig {
        let (aud, client_id) = (aud.trim(), client_id.trim());
        self.export =
            (!aud.is_empty() && !client_id.is_empty() && aud != self.aud && aud != self.admin_aud)
                .then(|| ExportAccess {
                    aud: aud.into(),
                    client_id: client_id.into(),
                });
        self
    }

    pub fn issuer(&self) -> String {
        format!("https://{}", self.team_domain)
    }

    pub fn certs_url(&self) -> String {
        format!("https://{}/cdn-cgi/access/certs", self.team_domain)
    }
}

/// One of the team's public keys, as the certs endpoint lists it (base64url `n` and `e`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Jwk {
    pub kid: String,
    pub n: String,
    pub e: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Audience {
    Reviewer,
    Admin,
    /// The export application: a service token, allowed on `GET /api/export` only.
    Export,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Claims {
    /// Absent for an Access service token.
    #[serde(default)]
    pub email: Option<String>,
    /// A service token's client id (absent for people).
    #[serde(default)]
    pub common_name: Option<String>,
    #[serde(deserialize_with = "string_or_list")]
    pub aud: Vec<String>,
    pub iss: String,
    pub exp: i64,
    #[serde(default)]
    pub nbf: Option<i64>,
    #[serde(default)]
    pub iat: Option<i64>,
}

impl Claims {
    /// `Export` for the export application (when on), `Admin` for the admin one, `Reviewer` for the reviewer
    /// one, else `None`.
    pub fn audience(&self, cfg: &AccessConfig) -> Option<Audience> {
        if cfg
            .export
            .as_ref()
            .is_some_and(|e| self.aud.contains(&e.aud))
        {
            Some(Audience::Export)
        } else if self.aud.contains(&cfg.admin_aud) {
            Some(Audience::Admin)
        } else if self.aud.contains(&cfg.aud) {
            Some(Audience::Reviewer)
        } else {
            None
        }
    }
}

fn string_or_list<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Vec<String>, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum OneOrMany {
        One(String),
        Many(Vec<String>),
    }
    Ok(match OneOrMany::deserialize(deserializer)? {
        OneOrMany::One(one) => vec![one],
        OneOrMany::Many(many) => many,
    })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccessError {
    Malformed,
    Algorithm,
    UnknownKey,
    Signature,
    Expired,
    NotYetValid,
    Issuer,
    Audience,
}

#[derive(Deserialize)]
struct Header {
    alg: String,
    #[serde(default)]
    kid: Option<String>,
    #[serde(default)]
    typ: Option<String>,
}

#[derive(Deserialize)]
struct Certs {
    keys: Vec<Jwk>,
}

/// The `keys` of the team's certs response.
pub fn parse_certs(body: &str) -> Result<Vec<Jwk>, AccessError> {
    serde_json::from_str::<Certs>(body)
        .map(|c| c.keys)
        .map_err(|_| AccessError::Malformed)
}

fn decode_segment(segment: &str) -> Result<Vec<u8>, AccessError> {
    URL_SAFE_NO_PAD
        .decode(segment)
        .map_err(|_| AccessError::Malformed)
}

/// The three segments of a compact JWT, each non-empty except possibly the signature.
fn split(token: &str) -> Result<(&str, &str, &str), AccessError> {
    let mut parts = token.split('.');
    match (parts.next(), parts.next(), parts.next(), parts.next()) {
        (Some(h), Some(p), Some(s), None) if !h.is_empty() && !p.is_empty() => Ok((h, p, s)),
        _ => Err(AccessError::Malformed),
    }
}

fn header(token: &str) -> Result<Header, AccessError> {
    let (h, _, _) = split(token)?;
    serde_json::from_slice(&decode_segment(h)?).map_err(|_| AccessError::Malformed)
}

/// The header's `kid`, after checking the token is RS256 (and, if it says, a JWT).
pub fn token_kid(token: &str) -> Result<String, AccessError> {
    let header = header(token)?;
    if header.alg != "RS256" || header.typ.as_deref().is_some_and(|t| t != "JWT") {
        return Err(AccessError::Algorithm);
    }
    header.kid.ok_or(AccessError::Malformed)
}

fn public_key(jwk: &Jwk) -> Result<RsaPublicKey, AccessError> {
    let n = BigUint::from_bytes_be(&decode_segment(&jwk.n)?);
    let e = BigUint::from_bytes_be(&decode_segment(&jwk.e)?);
    RsaPublicKey::new(n, e).map_err(|_| AccessError::UnknownKey)
}

/// Verifies `token` against `keys` and `cfg` at `now` (epoch seconds). Checks run in this order, so the
/// error names the first problem: shape, algorithm, key, signature, expiry, not-before, issuer, audience.
pub fn verify(
    token: &str,
    keys: &[Jwk],
    cfg: &AccessConfig,
    now: i64,
) -> Result<(Claims, Audience), AccessError> {
    let (h, p, s) = split(token)?;
    let claims_bytes = decode_segment(p)?;
    let signature_bytes = decode_segment(s)?;
    let kid = token_kid(token)?;
    let jwk = keys
        .iter()
        .find(|k| k.kid == kid)
        .ok_or(AccessError::UnknownKey)?;
    let verifying_key = VerifyingKey::<Sha256>::new(public_key(jwk)?);
    let signature =
        Signature::try_from(signature_bytes.as_slice()).map_err(|_| AccessError::Signature)?;
    verifying_key
        .verify(format!("{h}.{p}").as_bytes(), &signature)
        .map_err(|_| AccessError::Signature)?;

    let claims: Claims =
        serde_json::from_slice(&claims_bytes).map_err(|_| AccessError::Malformed)?;
    if claims.exp <= now {
        return Err(AccessError::Expired);
    }
    let too_early = |t: Option<i64>| t.is_some_and(|t| t > now + LEEWAY_SECONDS);
    if too_early(claims.nbf) || too_early(claims.iat) {
        return Err(AccessError::NotYetValid);
    }
    if claims.iss != cfg.issuer() {
        return Err(AccessError::Issuer);
    }
    let audience = claims.audience(cfg).ok_or(AccessError::Audience)?;
    Ok((claims, audience))
}

/// The team's keys and when they were fetched. The Worker keeps one per isolate.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct KeyCache {
    pub keys: Vec<Jwk>,
    pub fetched_at: Option<i64>,
}

impl KeyCache {
    /// True when the keys were never fetched, are older than an hour, or don't have `kid` and the last
    /// fetch is at least a minute old.
    pub fn needs_fetch(&self, kid: &str, now: i64) -> bool {
        let Some(fetched_at) = self.fetched_at else {
            return true;
        };
        let age = now - fetched_at;
        age >= KEYS_MAX_AGE_SECONDS
            || (!self.keys.iter().any(|k| k.kid == kid) && age >= UNKNOWN_KID_REFETCH_SECONDS)
    }

    /// Like `needs_fetch`, but claims the fetch: with keys in hand it stamps `fetched_at` now, before the
    /// fetch is awaited, so requests arriving meanwhile keep using the current keys instead of fetching
    /// too. A cold cache (no keys) doesn't claim, since there is nothing to fall back on.
    pub fn begin_fetch(&mut self, kid: &str, now: i64) -> bool {
        if !self.needs_fetch(kid, now) {
            return false;
        }
        if !self.keys.is_empty() {
            self.fetched_at = Some(now);
        }
        true
    }

    pub fn store(&mut self, keys: Vec<Jwk>, now: i64) {
        self.keys = keys;
        self.fetched_at = Some(now);
    }
}
