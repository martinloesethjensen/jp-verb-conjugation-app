mod support;

use review_api::app::{handle, ApiRequest, ApiResponse, AppConfig};
use review_api::store::{NewUser, Role, Store};
use serde_json::{json, Value};
use support::source::FakeSource;
use support::sqlite::SqliteStore;
use support::*;

const T0: &str = "2026-11-05T12:00:00Z";
const OWNER: &str = "owner@example.com";
const SITE: &str = "https://review.martinloeseth.dev";

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

fn owner() -> String {
    token(rs_header(), claims_for(Some(OWNER), "admin-aud"))
}

async fn post(
    s: &SqliteStore,
    src: &FakeSource,
    step: &str,
    body: Value,
    jwt: String,
) -> ApiResponse {
    let req = ApiRequest {
        method: "POST".into(),
        path: format!("/api/admin/snapshot/{step}"),
        query: String::new(),
        origin: Some(SITE.into()),
        jwt: Some(jwt),
        body: body.to_string().into_bytes(),
    };
    let cfg = AppConfig {
        access: support::cfg(),
        site_origin: SITE.into(),
    };
    handle(req, &cfg, &[jwk()], s, src, NOW, T0).await
}

async fn begin(s: &SqliteStore, src: &FakeSource, file: &str) -> (String, u64) {
    let r = post(s, src, "begin", json!({ "file": file }), owner()).await;
    assert_eq!(r.status, 200, "{}", r.body);
    (
        r.body["load_id"].as_str().unwrap().into(),
        r.body["slices"].as_u64().unwrap(),
    )
}

async fn slice(s: &SqliteStore, src: &FakeSource, load_id: &str, n: u64) -> ApiResponse {
    post(
        s,
        src,
        "slice",
        json!({ "load_id": load_id, "slice": n }),
        owner(),
    )
    .await
}

async fn finish(s: &SqliteStore, src: &FakeSource, load_id: &str) -> ApiResponse {
    post(s, src, "finish", json!({ "load_id": load_id }), owner()).await
}

fn staged(s: &SqliteStore) -> i64 {
    s.conn
        .borrow()
        .query_row("SELECT COUNT(*) FROM items_staging", [], |r| r.get(0))
        .unwrap()
}

#[tokio::test(flavor = "current_thread")]
async fn verbs_load_in_several_steps_and_appear_only_at_finish() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, slices) = begin(&s, &src, "verbs").await;
    assert!(slices > 1, "verbs is split into slices");
    for n in 0..slices {
        assert_eq!(slice(&s, &src, &load_id, n).await.status, 200);
        assert!(
            s.entries("verbs").await.unwrap().is_empty(),
            "nothing visible before finish"
        );
    }
    let done = finish(&s, &src, &load_id).await;
    assert_eq!(done.status, 200, "{}", done.body);
    assert_eq!(done.body["name"], "verbs");
    assert_eq!(s.entries("verbs").await.unwrap().len(), 97);
    assert_eq!(staged(&s), 0, "staging is cleared");
}

#[tokio::test(flavor = "current_thread")]
async fn a_missing_slice_stops_finish_and_nothing_changes() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, slices) = begin(&s, &src, "verbs").await;
    for n in 1..slices {
        slice(&s, &src, &load_id, n).await;
    }
    let r = finish(&s, &src, &load_id).await;
    assert_eq!(
        (r.status, r.body),
        (
            409,
            json!({"error": "not every part of verbs.json was loaded; start again"})
        )
    );
    assert!(s.snapshot_file("verbs").await.unwrap().is_none());
}

#[tokio::test(flavor = "current_thread")]
async fn a_repeated_slice_is_harmless() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, slices) = begin(&s, &src, "words").await;
    assert_eq!(slices, 1);
    slice(&s, &src, &load_id, 0).await;
    let once = staged(&s);
    assert_eq!(slice(&s, &src, &load_id, 0).await.status, 200);
    assert_eq!(staged(&s), once);
    assert_eq!(finish(&s, &src, &load_id).await.status, 200);
    assert_eq!(s.entries("words").await.unwrap().len(), 32);
}

#[tokio::test(flavor = "current_thread")]
async fn data_that_changes_mid_load_is_refused() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, _) = begin(&s, &src, "words").await;
    // A new data PR lands: the file (and so its manifest hash) changes. Here only the file changes,
    // so the published hash no longer matches either the load or the manifest.
    let mut bytes = src.get_bytes("words.json");
    let i = bytes.len() / 2;
    bytes[i] = b' ';
    src.set("words.json", bytes);
    let r = slice(&s, &src, &load_id, 0).await;
    assert_eq!(r.status, 502);
    assert_eq!(
        r.body["error"],
        "words.json doesn't match its signed manifest; try again in a minute"
    );
    assert!(s.snapshot_file("words").await.unwrap().is_none());
}

#[tokio::test(flavor = "current_thread")]
async fn a_load_against_a_changed_manifest_is_refused() {
    // The load began on one manifest; by finish a different (validly signed) version is published.
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, _) = begin(&s, &src, "words").await;
    slice(&s, &src, &load_id, 0).await;
    s.conn
        .borrow()
        .execute("UPDATE snapshot_loads SET version = '0.0.1'", [])
        .unwrap();
    let r = finish(&s, &src, &load_id).await;
    assert_eq!(
        (r.status, r.body),
        (
            409,
            json!({"error": "the published data changed while loading; start again"})
        )
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_second_begin_cancels_the_first() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (first, _) = begin(&s, &src, "words").await;
    slice(&s, &src, &first, 0).await;
    let (second, _) = begin(&s, &src, "words").await;
    assert_eq!(staged(&s), 0, "the first load's staging is gone");
    let r = slice(&s, &src, &first, 0).await;
    assert_eq!(
        (r.status, r.body),
        (
            409,
            json!({"error": "this load is no longer running; start again"})
        )
    );
    slice(&s, &src, &second, 0).await;
    assert_eq!(finish(&s, &src, &second).await.status, 200);
}

#[tokio::test(flavor = "current_thread")]
async fn bad_steps_are_refused() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, slices) = begin(&s, &src, "words").await;
    assert_eq!(slice(&s, &src, &load_id, slices).await.status, 400);
    assert_eq!(slice(&s, &src, "nope", 0).await.status, 409);
    assert_eq!(finish(&s, &src, "nope").await.status, 409);
    assert_eq!(
        post(&s, &src, "begin", json!({"file": "../verbs"}), owner())
            .await
            .status,
        400
    );
    let aiko = token(
        rs_header(),
        claims_for(Some("aiko@example.com"), "reviewer-aud"),
    );
    for (step, body) in [
        ("begin", json!({"file": "words"})),
        ("slice", json!({"load_id": load_id, "slice": 0})),
        ("finish", json!({"load_id": load_id})),
    ] {
        assert_eq!(
            post(&s, &src, step, body, aiko.clone()).await.status,
            403,
            "{step}"
        );
    }
}

#[tokio::test(flavor = "current_thread")]
async fn reference_files_have_no_slices_and_keep_their_text() {
    let (s, src) = (seeded().await, FakeSource::published());
    let (load_id, slices) = begin(&s, &src, "furigana").await;
    assert_eq!(slices, 0);
    assert_eq!(finish(&s, &src, &load_id).await.status, 200);
    assert_eq!(
        s.snapshot_json("furigana")
            .await
            .unwrap()
            .unwrap()
            .into_bytes(),
        src.get_bytes("furigana.json")
    );
}
