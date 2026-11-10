mod support;

use review_api::data::DataFile;
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

/// A minute after T0's day starts, plus `n` minutes: distinct, ordered timestamps.
fn at(n: u32) -> String {
    format!("2026-11-10T12:{n:02}:00.000Z")
}

/// たべる's first example: `(id, hash)`.
async fn example(s: &SqliteStore) -> (String, String) {
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
    let _ = doc(DataFile::Verbs);
    (
        part["item_id"].as_str().unwrap().into(),
        part["content_hash"].as_str().unwrap().into(),
    )
}

async fn suggest(s: &SqliteStore, who: &str, en: &str, n: u32) -> Value {
    let (id, hash) = example(s).await;
    let body = json!({"dataset": "verbs", "kind": "example", "id": id, "base_hash": hash,
        "action": "change", "edits": {"en": en}});
    let r = post_at(s, "/api/suggest", body, who, &at(n)).await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body["id"].clone()
}

async fn comment(s: &SqliteStore, id: &Value, who: &str, body: &str, n: u32) {
    let r = post_at(
        s,
        "/api/comment",
        json!({"suggestion_id": id, "body": body}),
        who,
        &at(n),
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
}

async fn replies(s: &SqliteStore, who: &str) -> (u64, Vec<Value>) {
    let r = get(s, "/api/replies", who).await;
    assert_eq!(r.status, 200, "{}", r.body);
    (
        r.body["unread"].as_u64().unwrap(),
        r.body["replies"].as_array().unwrap().clone(),
    )
}

fn summary(list: &[Value]) -> Vec<(String, String, bool)> {
    list.iter()
        .map(|r| {
            (
                r["what"].as_str().unwrap().to_string(),
                r["by_name"].as_str().unwrap().to_string(),
                r["unread"].as_bool().unwrap(),
            )
        })
        .collect()
}

#[tokio::test(flavor = "current_thread")]
async fn the_author_hears_about_replies_and_decisions() {
    let s = seeded().await;
    let id = suggest(&s, AIKO, "Hear about it.", 1).await;
    comment(&s, &id, BEN, "Nice.", 2).await;
    let r = post_at(
        &s,
        "/api/decide",
        json!({"id": id, "decision": "accept", "reply": "Thanks!"}),
        KEIKO,
        &at(3),
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    let (unread, list) = replies(&s, AIKO).await;
    assert_eq!(unread, 3);
    assert_eq!(
        summary(&list),
        [
            ("comment".into(), "Keiko".into(), true),
            ("accepted".into(), "Keiko".into(), true),
            ("comment".into(), "Ben".into(), true),
        ]
    );
    assert_eq!(list[0]["body"], "Thanks!");
    assert_eq!(list[1]["body"], "");
    assert_eq!(list[2]["suggestion_id"], id);
    assert_eq!(list[2]["dataset"], "verbs");
    assert_eq!(list[2]["entry_id"], "たべる");
    assert_eq!(list[2]["action"], "change");
}

#[tokio::test(flavor = "current_thread")]
async fn a_commenter_hears_only_what_came_after_their_comment() {
    let s = seeded().await;
    let id = suggest(&s, AIKO, "Order matters.", 1).await;
    comment(&s, &id, BEN, "First.", 2).await;
    comment(&s, &id, KEIKO, "Second.", 3).await;
    comment(&s, &id, BEN, "Third.", 4).await;
    comment(&s, &id, AIKO, "Fourth.", 5).await;
    let (unread, list) = replies(&s, BEN).await;
    assert_eq!(unread, 1);
    let fresh: Vec<_> = list.iter().filter(|r| r["unread"] == true).collect();
    assert_eq!(fresh.len(), 1);
    assert_eq!(fresh[0]["body"], "Fourth.");
    assert!(list.iter().all(|r| r["by_name"] != "Ben"));
}

#[tokio::test(flavor = "current_thread")]
async fn nothing_you_did_yourself_is_an_event() {
    let s = seeded().await;
    let id = suggest(&s, AIKO, "Keiko decides.", 1).await;
    let r = post_at(
        &s,
        "/api/decide",
        json!({"id": id, "decision": "accept", "reply": "Done."}),
        KEIKO,
        &at(2),
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(replies(&s, KEIKO).await, (0, vec![]));
    let gone = suggest(&s, BEN, "Withdrawn.", 3).await;
    let r = post_at(
        &s,
        "/api/suggest/withdraw",
        json!({"id": gone}),
        BEN,
        &at(4),
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(replies(&s, BEN).await, (0, vec![]));
}

#[tokio::test(flavor = "current_thread")]
async fn marking_read_clears_the_count() {
    let s = seeded().await;
    let a = suggest(&s, AIKO, "One.", 1).await;
    let b = suggest(&s, AIKO, "Two.", 2).await;
    let c = suggest(&s, AIKO, "Three.", 3).await;
    for id in [&a, &b, &c] {
        comment(&s, id, BEN, "Reply.", 4).await;
    }
    assert_eq!(replies(&s, AIKO).await.0, 3);
    let r = post_at(&s, "/api/replies/read", json!({"ids": [a]}), AIKO, &at(5)).await;
    assert_eq!(
        (r.status, r.body["unread"].as_u64()),
        (200, Some(2)),
        "{}",
        r.body
    );
    let (unread, list) = replies(&s, AIKO).await;
    assert_eq!(unread, 2);
    assert_eq!(list.len(), 3);
    assert_eq!(list.iter().filter(|r| r["unread"] == false).count(), 1);
    let r = post_at(&s, "/api/replies/read", json!({"all": true}), AIKO, &at(6)).await;
    assert_eq!(
        (r.status, r.body["unread"].as_u64()),
        (200, Some(0)),
        "{}",
        r.body
    );
    for body in [
        json!({}),
        json!({"ids": []}),
        json!({"ids": (0..201).collect::<Vec<_>>()}),
    ] {
        let r = post_at(&s, "/api/replies/read", body.clone(), AIKO, &at(7)).await;
        assert_eq!(r.status, 400, "{body}");
    }
}

#[tokio::test(flavor = "current_thread")]
async fn an_uninvolved_person_hears_nothing() {
    let s = seeded().await;
    let id = suggest(&s, AIKO, "Just us.", 1).await;
    comment(&s, &id, BEN, "Yes.", 2).await;
    assert_eq!(replies(&s, MARTIN).await, (0, vec![]));
}

#[tokio::test(flavor = "current_thread")]
async fn a_long_comment_is_cut_in_the_list() {
    let s = seeded().await;
    let id = suggest(&s, AIKO, "Long.", 1).await;
    let long: String = "長".repeat(300);
    comment(&s, &id, BEN, &long, 2).await;
    let (_, list) = replies(&s, AIKO).await;
    let body = list[0]["body"].as_str().unwrap();
    assert_eq!(body.chars().count(), 141);
    assert!(body.ends_with('…'));
}
