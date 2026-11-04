mod support;

use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use review_api::app::{handle, ApiRequest, ApiResponse, AppConfig};
use review_api::data::DataFile;
use review_api::store::{NewUser, Role, Store};
use serde_json::{json, Value};
use support::source::FakeSource;
use support::sqlite::SqliteStore;
use support::*;

const T0: &str = "2026-11-04T12:00:00Z";
const OWNER: &str = "owner@example.com";
const SITE: &str = "https://review.martinloeseth.dev";
const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

async fn seeded() -> SqliteStore {
    let s = SqliteStore::new();
    s.conn
        .borrow()
        .execute(
            "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, 'Martin', 'admin', 1, ?2)",
            rusqlite::params![OWNER, T0],
        )
        .unwrap();
    let aiko = NewUser {
        email: "aiko@example.com".into(),
        display_name: "Aiko".into(),
        role: Role::Reviewer,
    };
    s.add_user(&aiko, OWNER, T0).await.unwrap();
    s
}

fn cfg() -> AppConfig {
    AppConfig {
        access: support::cfg(),
        site_origin: SITE.into(),
    }
}

fn aiko() -> String {
    token(
        rs_header(),
        claims_for(Some("aiko@example.com"), "reviewer-aud"),
    )
}

fn owner_admin() -> String {
    token(rs_header(), claims_for(Some(OWNER), "admin-aud"))
}

async fn get(
    store: &SqliteStore,
    source: &FakeSource,
    path_and_query: &str,
    jwt: String,
) -> ApiResponse {
    let (path, query) = path_and_query
        .split_once('?')
        .unwrap_or((path_and_query, ""));
    let req = ApiRequest {
        method: "GET".into(),
        path: path.into(),
        query: query.into(),
        origin: None,
        jwt: Some(jwt),
        body: Vec::new(),
    };
    handle(req, &cfg(), &[jwk()], store, source, NOW, T0).await
}

async fn load(store: &SqliteStore, source: &FakeSource, file: &str, jwt: String) -> ApiResponse {
    let req = ApiRequest {
        method: "POST".into(),
        path: "/api/admin/snapshot".into(),
        query: String::new(),
        origin: Some(SITE.into()),
        jwt: Some(jwt),
        body: json!({ "file": file }).to_string().into_bytes(),
    };
    handle(req, &cfg(), &[jwk()], store, source, NOW, T0).await
}

fn manifest_version(file: DataFile) -> String {
    let m: Value =
        serde_json::from_slice(&std::fs::read(format!("{ROOT}/data/manifest.json")).unwrap())
            .unwrap();
    let v = if file == DataFile::Verbs {
        &m["version"]
    } else {
        &m[file.name()]["version"]
    };
    v.as_str().unwrap().into()
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_loads_every_file_and_reviewers_browse() {
    let (s, src) = (seeded().await, FakeSource::published());
    for file in DataFile::ALL {
        let r = load(&s, &src, file.name(), owner_admin()).await;
        assert_eq!(r.status, 200, "{}: {}", file.name(), r.body);
        assert_eq!(r.body["version"], json!(manifest_version(file)));
    }
    let snapshot = get(&s, &src, "/api/snapshot", aiko()).await;
    assert_eq!(snapshot.status, 200);
    let names: Vec<&str> = snapshot.body["files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["name"].as_str().unwrap())
        .collect();
    assert_eq!(
        names,
        ["furigana", "forms", "words", "counters", "grammar", "verbs"]
    );

    let verbs = get(&s, &src, "/api/items?dataset=verbs", aiko()).await;
    assert_eq!(verbs.status, 200);
    assert_eq!(verbs.body["dataset"], "verbs");
    assert_eq!(
        verbs.body["version"],
        json!(manifest_version(DataFile::Verbs))
    );
    assert_eq!(verbs.body["items"].as_array().unwrap().len(), 84);
    assert_eq!(verbs.body["items"][0]["title"], "する");

    let taberu = get(
        &s,
        &src,
        "/api/item?dataset=verbs&id=%E3%81%9F%E3%81%B9%E3%82%8B",
        aiko(),
    )
    .await;
    assert_eq!(taberu.status, 200);
    assert_eq!(taberu.body["id"], "たべる");
    assert_eq!(taberu.body["item"]["meaning"], "to eat");
    assert_eq!(taberu.body["content_hash"].as_str().unwrap().len(), 64);
    let kiru = get(
        &s,
        &src,
        "/api/item?dataset=verbs&id=%E3%81%8D%E3%82%8B%3A%E5%88%87%E3%82%8B",
        aiko(),
    )
    .await;
    assert_eq!(kiru.body["item"]["id"], "きる:切る");

    let reference = get(&s, &src, "/api/reference", aiko()).await;
    let furigana: Value =
        serde_json::from_slice(&std::fs::read(format!("{ROOT}/data/furigana.json")).unwrap())
            .unwrap();
    assert_eq!(reference.body["readings"], furigana["readings"]);
    assert_eq!(reference.body["forms"]["masu_pos"], "Polite");
}

#[tokio::test(flavor = "current_thread")]
async fn reviewers_cannot_load_data() {
    let (s, src) = (seeded().await, FakeSource::published());
    let reviewer_on_admin_app = token(
        rs_header(),
        claims_for(Some("aiko@example.com"), "admin-aud"),
    );
    assert_eq!(load(&s, &src, "words", aiko()).await.status, 403);
    assert_eq!(
        load(&s, &src, "words", reviewer_on_admin_app).await.status,
        403
    );
    assert!(
        src.requests.borrow().is_empty(),
        "nothing fetched for a refused request"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_tampered_file_is_refused_and_the_old_rows_stay() {
    let (s, src) = (seeded().await, FakeSource::published());
    assert_eq!(load(&s, &src, "words", owner_admin()).await.status, 200);
    let mut bytes = src.get_bytes("words.json");
    let i = bytes.len() / 2;
    bytes[i] = b' ';
    src.set("words.json", bytes);
    let r = load(&s, &src, "words", owner_admin()).await;
    assert_eq!(
        (r.status, r.body),
        (
            502,
            json!({"error": "words.json doesn't match its signed manifest; try again in a minute"})
        )
    );
    assert_eq!(
        get(&s, &src, "/api/items?dataset=words", aiko()).await.body["items"]
            .as_array()
            .unwrap()
            .len(),
        32
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_bad_signature_is_refused() {
    let (s, src) = (seeded().await, FakeSource::published());
    let other = SigningKey::from_bytes(&[7u8; 32]);
    src.set(
        "manifest.sig",
        STANDARD
            .encode(other.sign(&src.get_bytes("manifest.json")).to_bytes())
            .into_bytes(),
    );
    let r = load(&s, &src, "words", owner_admin()).await;
    assert_eq!(
        (r.status, r.body),
        (
            502,
            json!({"error": "the published manifest isn't signed by Martin's key"})
        )
    );
    assert!(
        src.requests
            .borrow()
            .iter()
            .all(|u| !u.ends_with("words.json")),
        "the data file isn't fetched"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn an_older_manifest_is_refused() {
    let (s, src) = (seeded().await, FakeSource::published());
    s.conn
        .borrow()
        .execute(
            "INSERT INTO snapshot_files (name, version, sha256, git_ref, item_count, imported_at, imported_by, json) \
             VALUES ('words', '9.0.0', 'x', NULL, 1, ?1, ?2, NULL)",
            rusqlite::params![T0, OWNER],
        )
        .unwrap();
    let r = load(&s, &src, "words", owner_admin()).await;
    let expected = format!(
        "words.json {} is older than the loaded 9.0.0",
        manifest_version(DataFile::Words)
    );
    assert_eq!((r.status, r.body), (502, json!({ "error": expected })));
    assert_eq!(
        s.snapshot_file("words").await.unwrap().unwrap().version,
        "9.0.0"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn reloading_the_same_version_is_fine() {
    let (s, src) = (seeded().await, FakeSource::published());
    assert_eq!(load(&s, &src, "words", owner_admin()).await.status, 200);
    assert_eq!(load(&s, &src, "words", owner_admin()).await.status, 200);
}

#[tokio::test(flavor = "current_thread")]
async fn a_fetch_failure_is_a_clear_502() {
    let (s, src) = (seeded().await, FakeSource::published());
    src.remove("words.json");
    let r = load(&s, &src, "words", owner_admin()).await;
    assert_eq!(
        (r.status, r.body),
        (
            502,
            json!({"error": "couldn't fetch the published data; try again in a minute"})
        )
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_bad_ref_is_refused_before_fetching() {
    // A manifest naming ref "../evil" for words, signed by a test key the store trusts for this test.
    let key = SigningKey::from_bytes(&[3u8; 32]);
    let public = STANDARD.encode(key.verifying_key().to_bytes());
    let mut manifest: Value =
        serde_json::from_slice(&FakeSource::published().get_bytes("manifest.json")).unwrap();
    manifest["words"]["ref"] = json!("../evil");
    let bytes = serde_json::to_vec(&manifest).unwrap();
    let src = FakeSource::published();
    src.set(
        "manifest.sig",
        STANDARD.encode(key.sign(&bytes).to_bytes()).into_bytes(),
    );
    src.set("manifest.json", bytes);
    let s = seeded().await;
    let err = review_api::app::import_file_with_keys(
        DataFile::Words,
        &s,
        &src,
        &[public.as_str()],
        OWNER,
        T0,
    )
    .await
    .unwrap_err();
    assert_eq!(err, "the manifest has an invalid ref for words.json");
    assert!(src.requests.borrow().iter().all(|u| !u.contains("evil")));
}

#[tokio::test(flavor = "current_thread")]
async fn queries_are_validated() {
    let (s, src) = (seeded().await, FakeSource::published());
    assert_eq!(
        get(&s, &src, "/api/items?dataset=forms", aiko())
            .await
            .status,
        400
    );
    assert_eq!(
        get(&s, &src, "/api/items?dataset=nope", aiko())
            .await
            .status,
        400
    );
    assert_eq!(get(&s, &src, "/api/items", aiko()).await.status, 400);
    let before = get(&s, &src, "/api/items?dataset=verbs", aiko()).await;
    assert_eq!(
        (before.status, before.body),
        (404, json!({"error": "Martin hasn't loaded this data yet."}))
    );
    assert_eq!(
        get(&s, &src, "/api/item?dataset=verbs", aiko())
            .await
            .status,
        400
    );
    assert_eq!(load(&s, &src, "verbs", owner_admin()).await.status, 200);
    assert_eq!(
        get(&s, &src, "/api/item?dataset=verbs&id=nobody", aiko())
            .await
            .status,
        404
    );
    assert_eq!(load(&s, &src, "../verbs", owner_admin()).await.status, 400);
    let reference = get(&s, &src, "/api/reference", aiko()).await;
    assert_eq!(reference.body, json!({"readings": {}, "forms": {}}));
    let no_token = ApiRequest {
        method: "GET".into(),
        path: "/api/items".into(),
        query: "dataset=verbs".into(),
        origin: None,
        jwt: None,
        body: vec![],
    };
    assert_eq!(
        handle(no_token, &cfg(), &[jwk()], &s, &src, NOW, T0)
            .await
            .status,
        401
    );
}
