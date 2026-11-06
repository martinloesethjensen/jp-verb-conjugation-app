mod support;

use review_api::data::DataFile;
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

/// たべる's first example: `(id, hash, json)`.
async fn example(s: &SqliteStore) -> (String, String, Value) {
    let r = get(
        s,
        &format!(
            "/api/review?{}",
            q(&[("dataset", "verbs"), ("id", "たべる")])
        ),
        AIKO,
    )
    .await;
    let part = r.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["kind"] == "example")
        .unwrap()
        .clone();
    let id = part["item_id"].as_str().unwrap().to_string();
    let json = doc(DataFile::Verbs)["verbs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["dict"] == "たべる")
        .unwrap()["examples"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == id.as_str())
        .unwrap()
        .clone();
    (id, part["content_hash"].as_str().unwrap().into(), json)
}

async fn suggest_en(s: &SqliteStore, who: &str, en: &str) -> Value {
    let (id, hash, _) = example(s).await;
    let r = post(
        s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": id, "base_hash": hash,
        "action": "change", "edits": {"en": en}}),
        who,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body["id"].clone()
}

async fn inbox(s: &SqliteStore, status: &str) -> Vec<Value> {
    let r = get(s, &format!("/api/admin/inbox?status={status}"), MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body["suggestions"].as_array().unwrap().clone()
}

async fn decide(s: &SqliteStore, body: Value) -> support::review::Response {
    post(s, "/api/admin/decide", body, MARTIN).await
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_sees_open_suggestions_with_the_current_text() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let (_, _, current) = example(&s).await;
    let open = inbox(&s, "open").await;
    assert_eq!(open.len(), 1);
    assert_eq!(open[0]["current"], current);
    assert_eq!(open[0]["author_name"], "Aiko");
    let r = get(&s, "/api/admin/inbox", MARTIN).await;
    assert_eq!(
        r.body["suggestions"].as_array().unwrap().len(),
        1,
        "open is the default"
    );
    let r = get(&s, "/api/admin/inbox?status=nope", MARTIN).await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn accept_decline_and_reply() {
    let s = seeded().await;
    let a = suggest_en(&s, AIKO, "One.").await;
    let b = suggest_en(&s, AIKO, "Two.").await;
    let r = decide(
        &s,
        json!({"id": a, "decision": "accept", "reply": "Thanks!"}),
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["status"], "accepted");
    assert_eq!(r.body["comments"].as_array().unwrap().len(), 1);
    assert_eq!(r.body["comments"][0]["author_name"], "Martin");
    let r = decide(&s, json!({"id": b, "decision": "decline"})).await;
    assert_eq!(r.body["status"], "declined");
    assert!(inbox(&s, "open").await.is_empty());
    assert_eq!(inbox(&s, "accepted").await.len(), 1);
    assert_eq!(inbox(&s, "declined").await.len(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn a_stale_change_needs_edit_then_accept() {
    let s = seeded().await;
    let id = suggest_en(&s, AIKO, "Mine.").await;
    let (ex, _, current) = example(&s).await;
    let mut d = doc(DataFile::Verbs);
    for verb in d["verbs"].as_array_mut().unwrap() {
        for e in verb["examples"].as_array_mut().unwrap() {
            if e["id"] == ex.as_str() {
                e["jp"] = json!(format!("{}よ", e["jp"].as_str().unwrap()));
            }
        }
    }
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    let r = decide(&s, json!({"id": id, "decision": "accept"})).await;
    assert_eq!(r.status, 409);
    assert_eq!(
        r.body["error"],
        "the data changed since this was suggested; use Edit then accept"
    );
    let r = decide(
        &s,
        json!({"id": id, "decision": "accept", "edits": {"en": "Martin's merge."}}),
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    let mut expected = current.clone();
    expected["jp"] = json!(format!("{}よ", current["jp"].as_str().unwrap()));
    expected["en"] = json!("Martin's merge.");
    assert_eq!(r.body["admin_edit"], expected);
}

#[tokio::test(flavor = "current_thread")]
async fn two_suggestions_on_one_item_are_decided_separately() {
    let s = seeded().await;
    let a = suggest_en(&s, AIKO, "Aiko's.").await;
    suggest_en(&s, BEN, "Ben's.").await;
    decide(&s, json!({"id": a, "decision": "accept"})).await;
    let open = inbox(&s, "open").await;
    assert_eq!(open.len(), 1);
    assert_eq!(open[0]["author_name"], "Ben");
}

#[tokio::test(flavor = "current_thread")]
async fn deleting_a_verb_asks_for_confirmation() {
    let s = seeded().await;
    let r = get(
        &s,
        &format!(
            "/api/review?{}",
            q(&[("dataset", "verbs"), ("id", "たべる")])
        ),
        AIKO,
    )
    .await;
    let hash = r.body["parts"][0]["content_hash"].clone();
    let r = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "entry", "id": "たべる",
        "base_hash": hash, "action": "delete"}),
        AIKO,
    )
    .await;
    let id = r.body["id"].clone();
    let warning = "Saved favourites, quiz history and widgets that point at たべる (食べる) will be dropped when this is exported.";
    let r = decide(&s, json!({"id": id, "decision": "accept"})).await;
    assert_eq!((r.status, r.body["error"].as_str()), (400, Some(warning)));
    let r = decide(&s, json!({"id": id, "decision": "accept", "confirm": true})).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["warning"], warning);
    assert_eq!(r.body["status"], "accepted");
}

#[tokio::test(flavor = "current_thread")]
async fn edits_on_a_gone_target_are_refused() {
    let s = seeded().await;
    let id = suggest_en(&s, AIKO, "Mine.").await;
    let mut d = doc(DataFile::Verbs);
    d["verbs"]
        .as_array_mut()
        .unwrap()
        .retain(|v| v["dict"] != "たべる");
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    let r = decide(
        &s,
        json!({"id": id, "decision": "accept", "edits": {"en": "x"}}),
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (404, Some("that isn't in the loaded data"))
    );
    assert_eq!(inbox(&s, "open").await[0]["current"], Value::Null);
    let r = decide(&s, json!({"id": id, "decision": "decline"})).await;
    assert_eq!(r.status, 200);
}

#[tokio::test(flavor = "current_thread")]
async fn deciding_twice_is_refused() {
    let s = seeded().await;
    let id = suggest_en(&s, AIKO, "Mine.").await;
    decide(&s, json!({"id": id, "decision": "decline"})).await;
    let r = decide(&s, json!({"id": id, "decision": "accept"})).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("this suggestion has already been decided"))
    );
    let r = decide(&s, json!({"id": 9999, "decision": "accept"})).await;
    assert_eq!(r.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn reviewers_cannot_use_the_inbox() {
    let s = seeded().await;
    let r = get(&s, "/api/admin/inbox", AIKO).await;
    assert_eq!(r.status, 403);
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": 1, "decision": "accept"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 403);
}

#[tokio::test(flavor = "current_thread")]
async fn a_removal_cannot_be_edited_then_accepted() {
    let s = seeded().await;
    let (id, hash, _) = example(&s).await;
    let r = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": id,
        "base_hash": hash, "action": "delete"}),
        AIKO,
    )
    .await;
    let sid = r.body["id"].clone();
    let r = decide(
        &s,
        json!({"id": sid, "decision": "accept", "edits": {"en": "Kept, but changed."}}),
    )
    .await;
    assert_eq!(r.status, 400);
    assert_eq!(
        r.body["error"],
        "a removal can't be edited; decline it and suggest a change instead"
    );
    assert_eq!(inbox(&s, "open").await.len(), 1, "still open");
}
