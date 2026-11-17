mod support;

use review_api::review_store::*;
use review_api::store::{Role, StoreError};
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

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
    (
        part["item_id"].as_str().unwrap().into(),
        part["content_hash"].as_str().unwrap().into(),
    )
}

async fn target(s: &SqliteStore) -> Target {
    let (item_id, _) = example(s).await;
    Target {
        dataset: "verbs".into(),
        kind: "example".into(),
        item_id,
    }
}

/// An open English-text suggestion on the example; returns its id.
async fn suggest_en(s: &SqliteStore, who: &str, en: &str) -> i64 {
    let (id, hash) = example(s).await;
    let r = post(
        s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": id, "base_hash": hash,
        "action": "change", "edits": {"en": en}}),
        who,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body["id"].as_i64().unwrap()
}

/// A request from Martin to Ben on a fresh suggestion by Aiko: `(target, suggestion id, request id)`.
async fn asked(s: &SqliteStore) -> (Target, i64, i64) {
    let sid = suggest_en(s, AIKO, "Better English.").await;
    let t = target(s).await;
    let id = s
        .ask_opinion(&t, BEN, "Which reads better?", MARTIN, T0)
        .await
        .unwrap();
    (t, sid, id)
}

fn audit_count(s: &SqliteStore, action: &str) -> i64 {
    s.conn
        .borrow()
        .query_row(
            "SELECT COUNT(*) FROM audit_log WHERE action = ?1",
            [action],
            |r| r.get(0),
        )
        .unwrap()
}

#[test]
fn teachers_and_the_owner_can_ask_for_opinions() {
    assert!(Role::Admin.can_ask_opinion());
    assert!(Role::Teacher.can_ask_opinion());
    assert!(!Role::Native.can_ask_opinion());
    assert!(!Role::Reviewer.can_ask_opinion());
}

#[tokio::test(flavor = "current_thread")]
async fn asking_stores_the_request_and_its_audit_row() {
    let s = seeded().await;
    let (t, sid, id) = asked(&s).await;
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert_eq!(o.anchor_id, sid);
    assert_eq!(o.item_id, t.item_id);
    assert_eq!(o.asked_by_name, "Martin");
    assert_eq!(o.asked_of_name, "Ben");
    assert!(o.mine_asked && !o.mine_to_answer && o.waiting);
    assert_eq!(o.question, "Which reads better?");
    assert_eq!(audit_count(&s, "opinion.ask"), 1);
    let ben = s.opinion(id, BEN).await.unwrap().unwrap();
    assert!(ben.mine_to_answer && !ben.mine_asked);
    assert_eq!(
        s.opinions_for_entry("verbs", &o.entry_id, BEN)
            .await
            .unwrap()
            .len(),
        1
    );
    assert_eq!(s.opinions_for_targets(&[t], BEN).await.unwrap().len(), 1);
    assert!(s.opinions_for_targets(&[], BEN).await.unwrap().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn a_second_open_request_on_one_item_is_a_conflict() {
    let s = seeded().await;
    let (t, _, _) = asked(&s).await;
    let again = s.ask_opinion(&t, AIKO, "", MARTIN, T0).await;
    assert_eq!(again, Err(StoreError::Conflict));
    assert_eq!(audit_count(&s, "opinion.ask"), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn cancelling_needs_the_asker_and_an_open_request() {
    let s = seeded().await;
    let (_, _, id) = asked(&s).await;
    assert_eq!(
        s.cancel_opinion(id, BEN, T0).await,
        Err(StoreError::Conflict)
    );
    s.cancel_opinion(id, MARTIN, T0).await.unwrap();
    assert_eq!(
        s.cancel_opinion(id, MARTIN, T0).await,
        Err(StoreError::NotFound)
    );
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert!(!o.waiting);
    assert_eq!(o.cancelled_at.as_deref(), Some(T0));
    assert_eq!(audit_count(&s, "opinion.cancel"), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn answering_records_the_pick_and_stops_waiting() {
    let s = seeded().await;
    let (_, sid, id) = asked(&s).await;
    assert_eq!(
        s.answer_opinion(id, Some(sid), "", MARTIN, T0).await,
        Err(StoreError::Conflict),
        "only the person asked answers"
    );
    s.answer_opinion(id, Some(sid), "", BEN, T0).await.unwrap();
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert_eq!(o.pick, Some(sid));
    assert!(!o.waiting);
    assert_eq!(o.answered_at.as_deref(), Some(T0));
    assert_eq!(audit_count(&s, "opinion.answer"), 1);
    assert_eq!(
        s.answer_opinion(id, None, "again", BEN, T0).await,
        Err(StoreError::NotFound)
    );
    // The thread was read by the one who answered.
    let read: i64 = s
        .conn
        .borrow()
        .query_row(
            "SELECT COUNT(*) FROM thread_reads WHERE user = ?1 AND suggestion_id = ?2",
            rusqlite::params![BEN, sid],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(read, 1);
}

#[tokio::test(flavor = "current_thread")]
async fn a_pick_must_be_a_suggestion_on_the_item() {
    let s = seeded().await;
    let (_, _, id) = asked(&s).await;
    let r = s.answer_opinion(id, Some(999_999), "", BEN, T0).await;
    assert_eq!(r, Err(StoreError::Conflict));
    assert!(s.opinion(id, BEN).await.unwrap().unwrap().waiting);
}

#[tokio::test(flavor = "current_thread")]
async fn deciding_every_open_suggestion_ends_the_wait() {
    let s = seeded().await;
    let (_, sid, id) = asked(&s).await;
    s.decide(sid, false, OwnerEdit::default(), MARTIN, T0)
        .await
        .unwrap();
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert!(!o.waiting);
    assert_eq!(o.answered_at, None);
}

#[tokio::test(flavor = "current_thread")]
async fn candidates_put_people_who_have_not_seen_the_item_first() {
    let s = seeded().await;
    // Keiko's suggestion: she is its author, so she isn't a candidate; Martin is asking.
    suggest_en(&s, KEIKO, "Better English.").await;
    let t = target(&s).await;
    let (_, hash) = example(&s).await;
    s.approve(&t, &hash, AIKO, T0).await.unwrap();
    let list: Vec<Value> = s
        .opinion_candidates(&t, MARTIN)
        .await
        .unwrap()
        .into_iter()
        .map(|c| json!([c.name, c.seen]))
        .collect();
    assert_eq!(
        list,
        vec![json!(["Ben", null]), json!(["Aiko", "approved"])]
    );
    let aiko = s.opinion_candidates(&t, MARTIN).await.unwrap().remove(1);
    let (email, role, active) = s.user_by_number(aiko.user).await.unwrap().unwrap();
    assert_eq!(
        (email.as_str(), role.as_str(), active),
        (AIKO, "reviewer", true)
    );
    assert_eq!(s.user_by_number(0).await.unwrap(), None);
}
