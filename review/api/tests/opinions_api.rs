mod support;

use review_api::review_store::*;
use review_api::store::{NewUser, Role, Store, StoreError};
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
    s.decide(sid, false, OwnerEdit::default(), MARTIN, T0, &[], "")
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

// --- Routes ----------------------------------------------------------------------------------------

const NATIVE: &str = "nao@example.com";

async fn with_native() -> SqliteStore {
    let s = seeded().await;
    let user = NewUser {
        email: NATIVE.into(),
        display_name: "Nao".into(),
        role: Role::Native,
    };
    s.add_user(&user, MARTIN, T0).await.unwrap();
    s
}

fn number(s: &SqliteStore, email: &str) -> i64 {
    s.conn
        .borrow()
        .query_row("SELECT rowid FROM users WHERE email = ?1", [email], |r| {
            r.get(0)
        })
        .unwrap()
}

async fn ask_via(s: &SqliteStore, who: &str, of: i64, question: &str) -> Response {
    let (id, _) = example(s).await;
    post(
        s,
        "/api/opinion/ask",
        json!({"dataset": "verbs", "kind": "example", "id": id, "user": of, "question": question}),
        who,
    )
    .await
}

async fn review_of(s: &SqliteStore, who: &str) -> Response {
    get(
        s,
        &format!(
            "/api/review?{}",
            q(&[("dataset", "verbs"), ("id", "たべる")])
        ),
        who,
    )
    .await
}

#[tokio::test(flavor = "current_thread")]
async fn only_teachers_and_the_owner_may_ask() {
    let s = with_native().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let ben = number(&s, BEN);
    assert_eq!(ask_via(&s, AIKO, ben, "Which?").await.status, 403);
    assert_eq!(ask_via(&s, NATIVE, ben, "Which?").await.status, 403);
    let r = ask_via(&s, KEIKO, ben, "Which?").await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert!(r.body["id"].as_i64().is_some());
    // Another item: the first open request blocks only its own item.
    let sen = get(
        &s,
        &format!("/api/review?{}", q(&[("dataset", "verbs"), ("id", "のむ")])),
        AIKO,
    )
    .await;
    let part = sen.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["kind"] == "example")
        .unwrap()
        .clone();
    let (item, hash) = (part["item_id"].clone(), part["content_hash"].clone());
    let sg = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": item, "base_hash": hash,
        "action": "change", "edits": {"en": "Other English."}}),
        AIKO,
    )
    .await;
    assert_eq!(sg.status, 201, "{}", sg.body);
    let r = post(
        &s,
        "/api/opinion/ask",
        json!({"dataset": "verbs", "kind": "example", "id": item, "user": ben, "question": ""}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn asking_a_second_time_on_one_item_is_refused() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let ben = number(&s, BEN);
    assert_eq!(ask_via(&s, KEIKO, ben, "").await.status, 201);
    let r = ask_via(&s, MARTIN, ben, "").await;
    assert_eq!(r.status, 409);
    assert_eq!(r.body["error"], "someone was already asked about this item");
}

#[tokio::test(flavor = "current_thread")]
async fn asking_needs_an_open_suggestion_on_the_item() {
    let s = seeded().await;
    let r = ask_via(&s, KEIKO, number(&s, BEN), "Which?").await;
    assert_eq!(r.status, 409);
    assert_eq!(r.body["error"], "nothing open to give an opinion on");
}

#[tokio::test(flavor = "current_thread")]
async fn the_asked_person_must_be_someone_else_and_not_an_author() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let r = ask_via(&s, KEIKO, number(&s, KEIKO), "").await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "you can't ask yourself")
    );
    let r = ask_via(&s, KEIKO, number(&s, AIKO), "").await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "they wrote one of these suggestions")
    );
    s.conn
        .borrow()
        .execute("UPDATE users SET active = 0 WHERE email = ?1", [BEN])
        .unwrap();
    let r = ask_via(&s, KEIKO, number(&s, BEN), "").await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "no such reviewer")
    );
    let r = ask_via(&s, KEIKO, 999_999, "").await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "no such reviewer")
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_native_or_reviewer_can_be_asked_and_answer() {
    let s = with_native().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "Which reads better?")
        .await
        .body["id"]
        .as_i64()
        .unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": null, "body": " Both read oddly. "}),
        BEN,
    )
    .await;
    assert_eq!((r.status, r.body), (200, json!({})));
    let seen = review_of(&s, AIKO).await;
    let o = &seen.body["opinions"][0];
    assert_eq!(o["answer"], "Both read oddly.");
    assert_eq!(o["asked_by_name"], "Keiko");
    assert_eq!(o["asked_of_name"], "Ben");
    assert_eq!(o["waiting"], false);
    assert!(!seen.body.to_string().contains("@example.com"));
    // A native is asked too.
    let s2 = with_native().await;
    suggest_en(&s2, AIKO, "Better English.").await;
    assert_eq!(
        ask_via(&s2, KEIKO, number(&s2, NATIVE), "").await.status,
        201
    );
}

#[tokio::test(flavor = "current_thread")]
async fn candidates_list_who_can_be_asked_without_emails() {
    let s = with_native().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let (item, _) = example(&s).await;
    let path = format!(
        "/api/opinion/candidates?{}",
        q(&[("dataset", "verbs"), ("kind", "example"), ("id", &item)])
    );
    assert_eq!(get(&s, &path, AIKO).await.status, 403);
    assert_eq!(get(&s, &path, NATIVE).await.status, 403);
    let r = get(&s, &path, KEIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let names: Vec<&str> = r.body["candidates"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["Ben", "Martin", "Nao"]);
    assert!(r.body["candidates"][0]["user"].as_i64().is_some());
    assert!(!r.body.to_string().contains("@example.com"));
}

#[tokio::test(flavor = "current_thread")]
async fn neither_needs_a_reason() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": null, "body": "  "}),
        BEN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "say why neither works")
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_pick_must_be_an_open_suggestion_on_the_item() {
    let s = seeded().await;
    let own = suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    for pick in [999_999, own + 1000] {
        let r = post(
            &s,
            "/api/opinion/answer",
            json!({"id": id, "pick": pick, "body": ""}),
            BEN,
        )
        .await;
        assert_eq!(r.status, 400, "{}", r.body);
    }
    // A suggestion on another item.
    let other = get(
        &s,
        &format!("/api/review?{}", q(&[("dataset", "verbs"), ("id", "のむ")])),
        AIKO,
    )
    .await;
    let part = other.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["kind"] == "example")
        .unwrap()
        .clone();
    let sg = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": part["item_id"],
        "base_hash": part["content_hash"], "action": "change", "edits": {"en": "Elsewhere."}}),
        AIKO,
    )
    .await;
    let other_id = sg.body["id"].as_i64().unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": other_id, "body": ""}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 400, "{}", r.body);
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": own, "body": ""}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn only_the_asked_person_answers() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": null, "body": "No."}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 403);
}

#[tokio::test(flavor = "current_thread")]
async fn answering_a_decided_item_is_refused() {
    let s = seeded().await;
    let sid = suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    let d = post(
        &s,
        "/api/decide",
        json!({"id": sid, "decision": "decline"}),
        MARTIN,
    )
    .await;
    assert_eq!(d.status, 200, "{}", d.body);
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": null, "body": "Neither."}),
        BEN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (409, "already decided")
    );
}

#[tokio::test(flavor = "current_thread")]
async fn only_the_asker_cancels() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    let r = post(&s, "/api/opinion/cancel", json!({"id": id}), MARTIN).await;
    assert_eq!(r.status, 403);
    let r = post(&s, "/api/opinion/cancel", json!({"id": id}), KEIKO).await;
    assert_eq!((r.status, r.body), (200, json!({})));
    let r = post(&s, "/api/opinion/cancel", json!({"id": id}), KEIKO).await;
    assert_eq!(r.status, 409);
    let r = post(&s, "/api/opinion/cancel", json!({"id": 999_999}), KEIKO).await;
    assert_eq!(r.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn the_question_and_answer_are_capped() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let long = "あ".repeat(review_api::proposal::MAX_TEXT + 1);
    let ben = number(&s, BEN);
    assert_eq!(ask_via(&s, KEIKO, ben, &long).await.status, 400);
    let id = ask_via(&s, KEIKO, ben, "").await.body["id"]
        .as_i64()
        .unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": null, "body": long}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 400);
}

// --- Closing: a request ends with the item's last open suggestion -----------------------------------

async fn inbox_of(s: &SqliteStore, status: &str) -> Vec<Value> {
    let r = get(s, &format!("/api/inbox?status={status}"), MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body["suggestions"].as_array().unwrap().clone()
}

/// An open note on the example by `who`; returns its id.
async fn note(s: &SqliteStore, who: &str) -> i64 {
    let (id, hash) = example(s).await;
    let r = post(
        s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": id, "base_hash": hash,
        "action": "note", "comment": "Hmm."}),
        who,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body["id"].as_i64().unwrap()
}

#[tokio::test(flavor = "current_thread")]
async fn a_request_closes_when_its_items_last_open_suggestion_is_decided() {
    let s = seeded().await;
    let aiko = suggest_en(&s, AIKO, "Aiko's English.").await;
    let old = ask_via(&s, KEIKO, number(&s, BEN), "Which reads better?")
        .await
        .body["id"]
        .as_i64()
        .unwrap();
    let d = post(
        &s,
        "/api/decide",
        json!({"id": aiko, "decision": "accept"}),
        MARTIN,
    )
    .await;
    assert_eq!(d.status, 200, "{}", d.body);
    let o = s.opinion(old, MARTIN).await.unwrap().unwrap();
    assert!(o.closed_at.is_some() && o.cancelled_at.is_none() && !o.waiting);
    assert_eq!(audit_count(&s, "opinion.close"), 1);
    // Ben suggests a new change on the same item: it is open, not waiting on the old request.
    let ben = suggest_en(&s, BEN, "Ben's English.").await;
    let open: Vec<i64> = inbox_of(&s, "open")
        .await
        .iter()
        .map(|r| r["id"].as_i64().unwrap())
        .collect();
    assert_eq!(open, vec![ben]);
    assert!(inbox_of(&s, "waiting").await.is_empty());
    assert!(inbox_of(&s, "open").await[0]["opinion"].is_null());
    // The old request can't be answered or cancelled any more.
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": old, "pick": null, "body": "Neither."}),
        BEN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (409, "already decided")
    );
    let r = post(&s, "/api/opinion/cancel", json!({"id": old}), KEIKO).await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (409, "already decided")
    );
    // A fresh ask goes through.
    let r = ask_via(&s, KEIKO, number(&s, AIKO), "And now?").await;
    assert_eq!(r.status, 201, "{}", r.body);
    // Closing isn't a cancellation: Ben hears of no cancelled request.
    let replies = get(&s, "/api/replies", BEN).await;
    assert!(!replies.body.to_string().contains("opinion_cancelled"));
}

#[tokio::test(flavor = "current_thread")]
async fn withdrawing_the_last_open_suggestion_closes_the_request() {
    let s = seeded().await;
    let (_, sid, id) = asked(&s).await;
    s.withdraw(sid, AIKO, T0).await.unwrap();
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert_eq!(o.closed_at.as_deref(), Some(T0));
    assert_eq!(audit_count(&s, "opinion.close"), 1);
    let t = target(&s).await;
    suggest_en(&s, KEIKO, "Keiko's.").await;
    s.ask_opinion(&t, BEN, "", MARTIN, T0).await.unwrap();
}

#[tokio::test(flavor = "current_thread")]
async fn a_request_stays_open_while_another_suggestion_is_open() {
    let s = seeded().await;
    let (_, sid, id) = asked(&s).await;
    suggest_en(&s, KEIKO, "Keiko's.").await;
    s.decide(sid, false, OwnerEdit::default(), MARTIN, T0, &[], "")
        .await
        .unwrap();
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert!(o.closed_at.is_none() && o.waiting);
    assert_eq!(audit_count(&s, "opinion.close"), 0);
}

#[tokio::test(flavor = "current_thread")]
async fn an_open_note_neither_keeps_a_request_waiting_nor_open() {
    let s = seeded().await;
    let (_, sid, id) = asked(&s).await;
    note(&s, MARTIN).await;
    s.decide(sid, false, OwnerEdit::default(), MARTIN, T0, &[], "")
        .await
        .unwrap();
    let o = s.opinion(id, MARTIN).await.unwrap().unwrap();
    assert!(o.closed_at.is_some() && !o.waiting);
    assert!(inbox_of(&s, "waiting").await.is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn an_item_whose_only_open_suggestion_is_a_note_cannot_be_asked_about() {
    let s = seeded().await;
    note(&s, AIKO).await;
    let r = ask_via(&s, KEIKO, number(&s, BEN), "Which?").await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (409, "nothing open to give an opinion on")
    );
    let t = target(&s).await;
    assert_eq!(
        s.ask_opinion(&t, BEN, "", KEIKO, T0).await,
        Err(StoreError::Conflict)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_anchor_is_the_oldest_open_change_not_a_note() {
    let s = seeded().await;
    note(&s, MARTIN).await;
    let sid = suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    assert_eq!(s.opinion(id, KEIKO).await.unwrap().unwrap().anchor_id, sid);
}

#[tokio::test(flavor = "current_thread")]
async fn a_note_cannot_be_the_pick() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let n = note(&s, MARTIN).await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": n, "body": ""}),
        BEN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "pick one of the open suggestions")
    );
    assert_eq!(
        s.answer_opinion(id, Some(n), "", BEN, T0).await,
        Err(StoreError::Conflict)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_asked_person_cannot_pick_their_own_suggestion() {
    let s = seeded().await;
    suggest_en(&s, AIKO, "Better English.").await;
    let id = ask_via(&s, KEIKO, number(&s, BEN), "").await.body["id"]
        .as_i64()
        .unwrap();
    // Ben writes a suggestion after being asked.
    let own = suggest_en(&s, BEN, "Ben's English.").await;
    let r = post(
        &s,
        "/api/opinion/answer",
        json!({"id": id, "pick": own, "body": ""}),
        BEN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str().unwrap()),
        (400, "you can't pick your own suggestion")
    );
    assert_eq!(
        s.answer_opinion(id, Some(own), "", BEN, T0).await,
        Err(StoreError::Conflict)
    );
    assert!(s.opinion(id, BEN).await.unwrap().unwrap().waiting);
}
