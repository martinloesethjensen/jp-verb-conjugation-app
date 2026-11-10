//! A store seeded with reviewers and the real data (loaded straight into the store: the review routes
//! only read it), and a way to call the API as one of them.

use super::source::FakeSource;
use super::sqlite::SqliteStore;
use super::{claims_for, jwk, rs_header, token, NOW};
use review_api::app::{handle, ApiRequest, ApiResponse, AppConfig};
use review_api::data::DataFile;
use review_api::items::extract;
use review_api::store::{NewUser, Role, SnapshotFile, Store};
use serde_json::Value;

pub const T0: &str = "2026-11-05T12:00:00Z";
pub const SITE: &str = "https://review.martinloeseth.dev";
pub const AIKO: &str = "aiko@example.com";
pub const BEN: &str = "ben@example.com";
pub const MARTIN: &str = "martin@example.com";
/// A teacher: accepts and declines other people's suggestions.
pub const KEIKO: &str = "keiko@example.com";
const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

pub fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

pub fn doc(file: DataFile) -> Value {
    serde_json::from_slice(&real(file)).unwrap()
}

/// Replaces a file's snapshot with `bytes`, as a finished load would.
pub async fn load_bytes(s: &SqliteStore, file: DataFile, bytes: &[u8]) {
    let rows = extract(file, bytes).unwrap();
    let json = (!file.is_browsable()).then(|| String::from_utf8(bytes.to_vec()).unwrap());
    let snapshot = SnapshotFile {
        name: file.name().into(),
        version: "1".into(),
        sha256: "abc".into(),
        git_ref: None,
        item_count: rows.len() as u32,
        imported_at: T0.into(),
        imported_by: MARTIN.into(),
    };
    s.replace_snapshot(&snapshot, json.as_deref(), &rows, MARTIN, T0)
        .await
        .unwrap();
}

/// Aiko and Ben (reviewers), Keiko (teacher), Martin (admin), and every real data file loaded.
pub async fn seeded() -> SqliteStore {
    let s = SqliteStore::new();
    s.conn
        .borrow()
        .execute(
            "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, 'Martin', 'admin', 1, ?2)",
            rusqlite::params![MARTIN, T0],
        )
        .unwrap();
    for (email, name) in [(AIKO, "Aiko"), (BEN, "Ben")] {
        let user = NewUser {
            email: email.into(),
            display_name: name.into(),
            role: Role::Reviewer,
        };
        s.add_user(&user, MARTIN, T0).await.unwrap();
    }
    let keiko = NewUser {
        email: KEIKO.into(),
        display_name: "Keiko".into(),
        role: Role::Teacher,
    };
    s.add_user(&keiko, MARTIN, T0).await.unwrap();
    for file in DataFile::ALL {
        load_bytes(&s, file, &real(file)).await;
    }
    s
}

/// Who is asking: reviewers through the reviewer application, Martin through the admin one.
pub fn jwt(email: &str) -> String {
    let aud = if email == MARTIN {
        "admin-aud"
    } else {
        "reviewer-aud"
    };
    jwt_via(email, aud)
}

/// Who is asking, through the application with this AUD (`"reviewer-aud"` or `"admin-aud"`).
pub fn jwt_via(email: &str, aud: &str) -> String {
    token(rs_header(), claims_for(Some(email), aud))
}

pub async fn call(
    s: &SqliteStore,
    method: &str,
    path_and_query: &str,
    body: Option<Value>,
    who: &str,
) -> ApiResponse {
    call_via(s, method, path_and_query, body, &jwt(who)).await
}

/// `call` with a ready-made token, for asking through a particular application.
pub async fn call_via(
    s: &SqliteStore,
    method: &str,
    path_and_query: &str,
    body: Option<Value>,
    jwt: &str,
) -> ApiResponse {
    call_at(s, method, path_and_query, body, jwt, T0).await
}

/// `call_via` at a given time (the `now` the handlers store), for tests where order matters.
pub async fn call_at(
    s: &SqliteStore,
    method: &str,
    path_and_query: &str,
    body: Option<Value>,
    jwt: &str,
    now: &str,
) -> ApiResponse {
    let (path, query) = path_and_query
        .split_once('?')
        .unwrap_or((path_and_query, ""));
    let req = ApiRequest {
        method: method.into(),
        path: path.into(),
        query: query.into(),
        origin: Some(SITE.into()),
        jwt: Some(jwt.into()),
        body: body.map(|b| b.to_string().into_bytes()).unwrap_or_default(),
    };
    let cfg = AppConfig {
        access: super::cfg(),
        site_origin: SITE.into(),
    };
    handle(req, &cfg, &[jwk()], s, &FakeSource::empty(), NOW, now).await
}

/// `post` at a given time.
pub async fn post_at(
    s: &SqliteStore,
    path: &str,
    body: Value,
    who: &str,
    now: &str,
) -> ApiResponse {
    call_at(s, "POST", path, Some(body), &jwt(who), now).await
}

pub async fn get(s: &SqliteStore, path_and_query: &str, who: &str) -> ApiResponse {
    call(s, "GET", path_and_query, None, who).await
}

pub async fn post(s: &SqliteStore, path: &str, body: Value, who: &str) -> ApiResponse {
    call(s, "POST", path, Some(body), who).await
}

/// `?id=` and friends, percent-encoded.
pub fn q(pairs: &[(&str, &str)]) -> String {
    form_urlencoded::Serializer::new(String::new())
        .extend_pairs(pairs)
        .finish()
}
pub type Response = review_api::app::ApiResponse;
