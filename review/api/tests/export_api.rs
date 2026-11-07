mod support;

use review_api::app::AppConfig;
use review_api::app::{handle, ApiRequest};
use serde_json::{json, Value};
use support::review::*;
use support::source::FakeSource;
use support::sqlite::SqliteStore;
use support::{claims_for, jwk, rs_header, token, NOW};

const CLIENT: &str = "service-token-id.access";

fn export_token(common_name: &str) -> String {
    let mut claims = claims_for(None, "export-aud");
    claims["common_name"] = json!(common_name);
    token(rs_header(), claims)
}

async fn as_token(s: &SqliteStore, method: &str, path: &str, jwt: String) -> Response {
    let req = ApiRequest {
        method: method.into(),
        path: path.into(),
        query: String::new(),
        origin: Some(SITE.into()),
        jwt: Some(jwt),
        body: b"{}".to_vec(),
    };
    let cfg = AppConfig {
        access: support::cfg().with_export("export-aud", CLIENT),
        site_origin: SITE.into(),
    };
    handle(req, &cfg, &[jwk()], s, &FakeSource::empty(), NOW, T0).await
}

#[tokio::test(flavor = "current_thread")]
async fn the_export_token_reads_export_only() {
    let s = seeded().await;
    assert_eq!(
        as_token(&s, "GET", "/api/export", export_token(CLIENT))
            .await
            .status,
        200
    );
    for (method, path) in [
        ("GET", "/api/items"),
        ("GET", "/api/me"),
        ("GET", "/api/admin/inbox"),
        ("GET", "/api/admin/export"),
        ("POST", "/api/admin/exported"),
    ] {
        let r = as_token(&s, method, path, export_token(CLIENT)).await;
        assert_eq!(r.status, 403, "{method} {path}");
    }
    let wrong = as_token(
        &s,
        "GET",
        "/api/export",
        export_token("someone-else.access"),
    )
    .await;
    assert_eq!(wrong.status, 403);
    assert_eq!(get(&s, "/api/export", MARTIN).await.status, 403);
    assert_eq!(get(&s, "/api/export", AIKO).await.status, 403);
}

/// `(kind, id, content_hash)` of the first example of a verb.
async fn first_example(s: &SqliteStore, verb: &str) -> (String, String) {
    let r = get(
        s,
        &format!("/api/review?{}", q(&[("dataset", "verbs"), ("id", verb)])),
        AIKO,
    )
    .await;
    let p = r.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["kind"] == "example")
        .unwrap();
    (
        p["item_id"].as_str().unwrap().into(),
        p["content_hash"].as_str().unwrap().into(),
    )
}

async fn decide(s: &SqliteStore, id: &Value, body: Value) {
    let mut body = body;
    body["id"] = id.clone();
    let r = post(s, "/api/admin/decide", body, MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn export_lists_accepted_work_once() {
    let s = seeded().await;
    assert_eq!(
        post(
            &s,
            "/api/me/public-name",
            json!({"public_name": "Aiko S."}),
            AIKO
        )
        .await
        .status,
        200
    );
    let (ex, hash) = first_example(&s, "たべる").await;
    let change = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": ex,
        "base_hash": hash, "action": "change", "edits": {"en": "Reviewer's English."}}),
        AIKO,
    )
    .await;
    assert_eq!(change.status, 201, "{}", change.body);
    decide(
        &s,
        &change.body["id"],
        json!({"decision": "accept", "edits": {"en": "Owner's English."}}),
    )
    .await;
    let (ex2, hash2) = first_example(&s, "のむ").await;
    let delete = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": ex2,
        "base_hash": hash2, "action": "delete", "comment": "Unnatural."}),
        BEN,
    )
    .await;
    assert_eq!(delete.status, 201, "{}", delete.body);
    decide(&s, &delete.body["id"], json!({"decision": "accept"})).await;
    let add = post(&s, "/api/add", json!({"dataset": "words", "kind": "entry",
        "fields": {"class": "noun", "dict": "ねこ", "kanji": "猫", "meaning": "cat", "jlpt": "N5"}}), AIKO).await;
    assert_eq!(add.status, 201, "{}", add.body);
    decide(&s, &add.body["id"], json!({"decision": "accept"})).await;
    let (ex3, hash3) = first_example(&s, "みる").await;
    let open = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": ex3,
        "base_hash": hash3, "action": "note", "comment": "Hmm."}),
        BEN,
    )
    .await;
    assert_eq!(open.status, 201, "{}", open.body);

    let r = as_token(&s, "GET", "/api/export", export_token(CLIENT)).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert!(
        !r.body.to_string().contains('@'),
        "an email leaked: {}",
        r.body
    );
    let list = r.body["suggestions"].as_array().unwrap();
    let ids: Vec<&Value> = list.iter().map(|x| &x["id"]).collect();
    assert_eq!(
        ids,
        vec![&change.body["id"], &delete.body["id"], &add.body["id"]]
    );
    let c = &list[0];
    assert_eq!(c["action"], "change");
    assert_eq!(c["item"]["en"], "Owner's English.");
    let editable: Vec<&str> = c["editable"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    assert!(
        editable.contains(&"jp") && editable.contains(&"particle_blanks"),
        "{editable:?}"
    );
    assert_eq!(c["credit"], json!({"role": "native", "name": "Aiko S."}));
    assert_eq!(list[1]["item"], Value::Null);
    assert_eq!(list[1]["editable"], Value::Null);
    assert_eq!(list[2]["item"]["dict"], "ねこ");
    assert_eq!(r.body["files"]["verbs"], "abc"); // the test snapshot's placeholder sha256
    assert_eq!(r.body["stamps"], json!([]));

    let marked = post(
        &s,
        "/api/admin/exported",
        json!({"suggestions": ids.iter().map(|v| (*v).clone()).collect::<Vec<_>>(), "stamps": []}),
        MARTIN,
    )
    .await;
    assert_eq!(marked.status, 200, "{}", marked.body);
    let again = get(&s, "/api/admin/export", MARTIN).await;
    assert_eq!(again.status, 200);
    assert_eq!(again.body["suggestions"], json!([]));
}

#[tokio::test(flavor = "current_thread")]
async fn marking_exported_skips_rows_that_are_not_accepted() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s, "たべる").await;
    let open = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": ex,
        "base_hash": hash, "action": "change", "edits": {"en": "Open still."}}),
        AIKO,
    )
    .await;
    let r = post(
        &s,
        "/api/admin/exported",
        json!({"suggestions": [open.body["id"]], "stamps": []}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    decide(&s, &open.body["id"], json!({"decision": "accept"})).await;
    let listed = get(&s, "/api/admin/export", MARTIN).await;
    assert_eq!(listed.body["suggestions"][0]["id"], open.body["id"]);
}
