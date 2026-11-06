mod support;

use review_api::data::DataFile;
use review_api::items::{extract, ItemRow};
use review_api::review_store::{NewSuggestion, QueueFilter, ReviewStore, Target};
use review_api::store::{NewUser, Role, SnapshotFile, Store, StoreError};
use serde_json::Value;
use support::sqlite::SqliteStore;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const T0: &str = "2026-11-05T12:00:00Z";
const AIKO: &str = "aiko@example.com";
const BEN: &str = "ben@example.com";
const MARTIN: &str = "martin@example.com";
const II: &str = "i-adjective:いい";

fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

fn doc(file: DataFile) -> Value {
    serde_json::from_slice(&real(file)).unwrap()
}

async fn load(store: &SqliteStore, file: DataFile, bytes: &[u8]) -> Vec<ItemRow> {
    let rows = extract(file, bytes).unwrap();
    let snapshot = SnapshotFile {
        name: file.name().into(),
        version: "1".into(),
        sha256: "abc".into(),
        git_ref: None,
        item_count: rows.len() as u32,
        imported_at: T0.into(),
        imported_by: MARTIN.into(),
    };
    store
        .replace_snapshot(&snapshot, None, &rows, MARTIN, T0)
        .await
        .unwrap();
    rows
}

async fn setup() -> SqliteStore {
    let s = SqliteStore::new();
    for (email, name, role) in [
        (AIKO, "Aiko", Role::Reviewer),
        (BEN, "Ben", Role::Reviewer),
        (MARTIN, "Martin", Role::Admin),
    ] {
        let user = NewUser {
            email: email.into(),
            display_name: name.into(),
            role,
        };
        s.add_user(&user, MARTIN, T0).await.unwrap();
    }
    load(&s, DataFile::Words, &real(DataFile::Words)).await;
    load(&s, DataFile::Verbs, &real(DataFile::Verbs)).await;
    s
}

fn target(dataset: &str, kind: &str, id: &str) -> Target {
    Target {
        dataset: dataset.into(),
        kind: kind.into(),
        item_id: id.into(),
    }
}

async fn hash(s: &SqliteStore, t: &Target) -> String {
    s.current_hash(t).await.unwrap().unwrap().0
}

fn change(t: &Target, base_hash: &str, proposed: &str) -> NewSuggestion {
    NewSuggestion {
        action: "change".into(),
        target: t.clone(),
        entry_id: t.item_id.clone(),
        item_title: "いい".into(),
        base_hash: base_hash.into(),
        proposed_json: Some(proposed.into()),
        furigana_json: None,
        dropped_blanks: 0,
        comment: String::new(),
    }
}

fn audit_actions(s: &SqliteStore) -> Vec<String> {
    let conn = s.conn.borrow();
    let mut st = conn
        .prepare("SELECT action FROM audit_log ORDER BY id")
        .unwrap();
    let rows = st.query_map([], |r| r.get::<_, String>(0)).unwrap();
    rows.map(Result::unwrap).collect()
}

fn words_without(id_index: usize) -> Vec<u8> {
    let mut d = doc(DataFile::Words);
    d["words"].as_array_mut().unwrap().remove(id_index);
    d.to_string().into_bytes()
}

#[tokio::test(flavor = "current_thread")]
async fn an_approval_counts_while_the_hash_matches() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    s.approve(&t, &h, AIKO, T0).await.unwrap();
    let (approvals, _) = s.entry_review("words", II, BEN).await.unwrap();
    assert_eq!(approvals.len(), 1);
    assert!(approvals[0].current);
    assert!(!approvals[0].mine);
    assert_eq!(approvals[0].reviewer_name, "Aiko");
    let count = |counts: Vec<(String, u32, u32)>| {
        counts.into_iter().find(|c| c.0 == II).map(|c| c.1).unwrap()
    };
    assert_eq!(count(s.review_counts("words").await.unwrap()), 1);

    let mut d = doc(DataFile::Words);
    d["words"][0]["meaning"] = "good, fine".into();
    load(&s, DataFile::Words, d.to_string().as_bytes()).await;
    let (approvals, _) = s.entry_review("words", II, AIKO).await.unwrap();
    assert!(!approvals[0].current);
    assert!(approvals[0].mine);
    assert_eq!(count(s.review_counts("words").await.unwrap()), 0);
}

#[tokio::test(flavor = "current_thread")]
async fn approving_twice_is_one_row() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    s.approve(&t, &h, AIKO, T0).await.unwrap();
    s.approve(&t, &h, AIKO, T0).await.unwrap();
    let (approvals, _) = s.entry_review("words", II, AIKO).await.unwrap();
    assert_eq!(approvals.len(), 1);
    let adds = audit_actions(&s)
        .into_iter()
        .filter(|a| a == "approval.add")
        .count();
    assert_eq!(adds, 2);
}

#[tokio::test(flavor = "current_thread")]
async fn an_identical_open_suggestion_is_not_duplicated() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    let new = change(&t, &h, r#"{"meaning":"good"}"#);
    let first = s.add_suggestion(&new, AIKO, T0).await.unwrap().0;
    let second = s.add_suggestion(&new, AIKO, T0).await.unwrap().0;
    assert_eq!(first, second);
    let other = s
        .add_suggestion(&change(&t, &h, r#"{"meaning":"nice"}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    assert_ne!(first, other);
    s.withdraw(first, AIKO, T0).await.unwrap();
    let third = s.add_suggestion(&new, AIKO, T0).await.unwrap().0;
    assert_ne!(first, third);
    let got = s.suggestion(third, AIKO).await.unwrap().unwrap();
    assert_eq!(got.author_name, "Aiko");
    assert!(got.mine);
    assert_eq!(got.proposed, Some(serde_json::json!({"meaning": "good"})));
}

#[tokio::test(flavor = "current_thread")]
async fn stale_and_gone_are_computed_on_read() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    let stale = s
        .add_suggestion(&change(&t, "old-hash", "{}"), AIKO, T0)
        .await
        .unwrap()
        .0;
    let fresh = s
        .add_suggestion(&change(&t, &h, r#"{"a":1}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    let got = s.suggestion(stale, BEN).await.unwrap().unwrap();
    assert!(got.stale && !got.gone);
    let got = s.suggestion(fresh, BEN).await.unwrap().unwrap();
    assert!(!got.stale && !got.gone);

    load(&s, DataFile::Words, &words_without(0)).await;
    let got = s.suggestion(fresh, BEN).await.unwrap().unwrap();
    assert!(got.gone && !got.stale);
    assert_eq!(got.item_title, "いい");
    let (_, suggestions) = s.entry_review("words", II, BEN).await.unwrap();
    assert_eq!(suggestions.len(), 2);
    assert_eq!(suggestions[0].id, fresh, "newest first");
}

#[tokio::test(flavor = "current_thread")]
async fn only_open_suggestions_can_be_decided_or_withdrawn() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    let a = s
        .add_suggestion(&change(&t, &h, r#"{"a":1}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    assert_eq!(s.withdraw(a, BEN, T0).await, Err(StoreError::Conflict));
    s.decide(a, true, Some(r#"{"a":2}"#), None, MARTIN, T0)
        .await
        .unwrap();
    let got = s.suggestion(a, MARTIN).await.unwrap().unwrap();
    assert_eq!(got.status, "accepted");
    assert_eq!(got.admin_edit, Some(serde_json::json!({"a": 2})));
    assert_eq!(got.decided_at.as_deref(), Some(T0));
    assert_eq!(
        s.decide(a, false, None, None, MARTIN, T0).await,
        Err(StoreError::Conflict)
    );

    let b = s
        .add_suggestion(&change(&t, &h, r#"{"b":1}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.decide(b, false, None, None, MARTIN, T0).await.unwrap();
    assert_eq!(s.withdraw(b, AIKO, T0).await, Err(StoreError::NotFound));
    assert_eq!(s.withdraw(9999, AIKO, T0).await, Err(StoreError::NotFound));
    assert_eq!(
        s.decide(9999, true, None, None, MARTIN, T0).await,
        Err(StoreError::NotFound)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn comments_are_listed_in_order_with_names() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    let a = s
        .add_suggestion(&change(&t, &h, r#"{"a":1}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.add_comment(a, "Why?", MARTIN, T0).await.unwrap();
    s.add_comment(a, "Because.", AIKO, T0).await.unwrap();
    let got = s.suggestion(a, BEN).await.unwrap().unwrap();
    let names: Vec<_> = got
        .comments
        .iter()
        .map(|c| c.author_name.as_str())
        .collect();
    assert_eq!(names, ["Martin", "Aiko"]);
    assert_eq!(got.comments[1].body, "Because.");
    assert_eq!(
        s.add_comment(9999, "x", AIKO, T0).await,
        Err(StoreError::NotFound)
    );
    let inbox = s.inbox("open", MARTIN).await.unwrap();
    assert_eq!(inbox.len(), 1);
    assert_eq!(inbox[0].comments.len(), 2);
}

async fn four_word_queue(s: &SqliteStore) -> (i64, Vec<String>) {
    let ids: Vec<String> = s
        .entries("words")
        .await
        .unwrap()
        .into_iter()
        .take(4)
        .map(|e| e.item_id)
        .collect();
    let filter = QueueFilter {
        dataset: "words".into(),
        kinds: vec![],
        jlpt: vec![],
        never_approved: false,
        ids: ids.clone(),
    };
    assert_eq!(s.preview_queue(&filter).await.unwrap().len(), 4);
    let id = s
        .add_queue("Adjectives", "First four", &filter, MARTIN, T0)
        .await
        .unwrap();
    (id, ids)
}

#[tokio::test(flavor = "current_thread")]
async fn queue_progress_follows_the_counting_rules() {
    let s = setup().await;
    let (q, ids) = four_word_queue(&s).await;
    let t: Vec<Target> = ids.iter().map(|id| target("words", "entry", id)).collect();
    s.approve(&t[0], &hash(&s, &t[0]).await, AIKO, T0)
        .await
        .unwrap();
    let h1 = hash(&s, &t[1]).await;
    s.add_suggestion(&change(&t[1], &h1, "{}"), AIKO, T0)
        .await
        .unwrap();
    s.skip(q, &t[2], AIKO, T0).await.unwrap();

    let (summary, items) = s.queue(q, AIKO).await.unwrap().unwrap();
    assert_eq!(summary.title, "Adjectives");
    assert_eq!((summary.total, summary.done), (4, 3));
    let mine: Vec<_> = items.iter().map(|i| i.mine.as_deref()).collect();
    assert_eq!(
        mine,
        [Some("approved"), Some("suggested"), Some("skipped"), None]
    );
    assert_eq!(items[0].title, "いい");

    let (summary, _) = s.queue(q, BEN).await.unwrap().unwrap();
    assert_eq!((summary.done, summary.with_suggestion), (0, 1));
    let listed = s.queues(BEN, false).await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].with_suggestion, 1);

    load(&s, DataFile::Words, &words_without(3)).await;
    let (summary, items) = s.queue(q, AIKO).await.unwrap().unwrap();
    assert_eq!(summary.done, 4);
    assert!(items[3].gone);
    assert!(!items[0].gone);
    let (summary, _) = s.queue(q, BEN).await.unwrap().unwrap();
    assert_eq!(summary.done, 1, "a gone item is done for everyone");
}

#[tokio::test(flavor = "current_thread")]
async fn queues_can_be_edited_noted_trimmed_and_archived() {
    let s = setup().await;
    let (q, ids) = four_word_queue(&s).await;
    let first = target("words", "entry", &ids[0]);
    s.set_queue_note(q, &first, "Is this natural?", MARTIN, T0)
        .await
        .unwrap();
    s.remove_queue_item(q, &target("words", "entry", &ids[3]), MARTIN, T0)
        .await
        .unwrap();
    let (summary, items) = s.queue(q, AIKO).await.unwrap().unwrap();
    assert_eq!(summary.total, 3);
    assert_eq!(items[0].note, "Is this natural?");
    assert_eq!(
        s.set_queue_note(q, &target("words", "entry", "nope"), "x", MARTIN, T0)
            .await,
        Err(StoreError::NotFound)
    );
    assert_eq!(
        s.skip(q, &target("words", "entry", "nope"), AIKO, T0).await,
        Err(StoreError::NotFound)
    );
    s.update_queue(q, "Renamed", "", true, MARTIN, T0)
        .await
        .unwrap();
    assert!(s.queues(AIKO, false).await.unwrap().is_empty());
    let all = s.queues(MARTIN, true).await.unwrap();
    assert_eq!(all[0].title, "Renamed");
    assert!(all[0].archived);
    assert_eq!(
        s.update_queue(999, "x", "", false, MARTIN, T0).await,
        Err(StoreError::NotFound)
    );
    assert!(s.queue(999, AIKO).await.unwrap().is_none());
}

#[tokio::test(flavor = "current_thread")]
async fn the_filter_picks_by_kind_level_and_never_approved() {
    let s = setup().await;
    let filter = QueueFilter {
        dataset: "verbs".into(),
        kinds: vec!["example".into()],
        jlpt: vec!["N5".into()],
        never_approved: false,
        ids: vec![],
    };
    let items = s.preview_queue(&filter).await.unwrap();
    assert!(!items.is_empty());
    assert!(items.iter().all(|i| i.kind == "example"));
    assert!(items.windows(2).all(|w| w[0].position < w[1].position));
    let verbs = doc(DataFile::Verbs);
    let n5: Vec<String> = verbs["verbs"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|v| v["jlpt"] == "N5")
        .map(|v| {
            v.get("id")
                .unwrap_or(&v["dict"])
                .as_str()
                .unwrap()
                .to_string()
        })
        .collect();
    assert!(items.iter().all(|i| n5.contains(&i.entry_id)));
    let all_examples = s
        .preview_queue(&QueueFilter {
            jlpt: vec![],
            ..filter_clone(&filter)
        })
        .await
        .unwrap();
    assert!(all_examples.len() > items.len(), "other levels exist");

    let first = target("verbs", "example", &items[0].item_id);
    s.approve(&first, "an-old-hash", AIKO, T0).await.unwrap();
    let never = s
        .preview_queue(&QueueFilter {
            never_approved: true,
            ..filter_clone(&filter)
        })
        .await
        .unwrap();
    assert_eq!(never.len(), items.len() - 1);
    assert!(never.iter().all(|i| i.item_id != items[0].item_id));
}

fn filter_clone(f: &QueueFilter) -> QueueFilter {
    QueueFilter {
        dataset: f.dataset.clone(),
        kinds: f.kinds.clone(),
        jlpt: f.jlpt.clone(),
        never_approved: f.never_approved,
        ids: f.ids.clone(),
    }
}

#[tokio::test(flavor = "current_thread")]
async fn every_write_is_audited() {
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    s.approve(&t, &h, AIKO, T0).await.unwrap();
    s.unapprove(&t, AIKO, T0).await.unwrap();
    let a = s
        .add_suggestion(&change(&t, &h, "{}"), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.withdraw(a, AIKO, T0).await.unwrap();
    let b = s
        .add_suggestion(&change(&t, &h, "{}"), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.decide(b, true, None, None, MARTIN, T0).await.unwrap();
    let c = s
        .add_suggestion(&change(&t, &h, r#"{"c":1}"#), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.decide(c, false, None, None, MARTIN, T0).await.unwrap();
    s.add_comment(c, "ok", MARTIN, T0).await.unwrap();
    let (q, ids) = four_word_queue(&s).await;
    s.update_queue(q, "x", "", false, MARTIN, T0).await.unwrap();
    let second = target("words", "entry", &ids[1]);
    s.set_queue_note(q, &second, "n", MARTIN, T0).await.unwrap();
    s.skip(q, &second, AIKO, T0).await.unwrap();
    s.remove_queue_item(q, &second, MARTIN, T0).await.unwrap();
    let actions = audit_actions(&s);
    for name in [
        "approval.add",
        "approval.remove",
        "suggestion.add",
        "suggestion.withdraw",
        "suggestion.accept",
        "suggestion.decline",
        "comment.add",
        "queue.add",
        "queue.update",
        "queue.note",
        "queue.remove_item",
        "queue.skip",
    ] {
        assert_eq!(
            actions.iter().filter(|a| *a == name).count(),
            if name == "suggestion.add" { 3 } else { 1 },
            "{name}"
        );
    }
}

#[tokio::test(flavor = "current_thread")]
async fn a_decision_that_loses_a_race_writes_no_audit_row() {
    use review_api::review_store::{DECIDE, INSERT_DECIDE_AUDIT, INSERT_WITHDRAW_AUDIT, WITHDRAW};
    let s = setup().await;
    let t = target("words", "entry", II);
    let h = hash(&s, &t).await;
    let id = s
        .add_suggestion(&change(&t, &h, "{}"), AIKO, T0)
        .await
        .unwrap()
        .0;
    s.decide(id, true, None, None, MARTIN, T0).await.unwrap();
    let before = audit_actions(&s).len();
    // The second tab's batch, run after the first one committed: audit first, then the update.
    let conn = s.conn.borrow();
    let logged = conn
        .execute(
            INSERT_DECIDE_AUDIT,
            rusqlite::params![T0, MARTIN, "suggestion.accept", "", id],
        )
        .unwrap();
    let changed = conn
        .execute(
            DECIDE,
            rusqlite::params![id, "accepted", None::<String>, MARTIN, T0, None::<String>],
        )
        .unwrap();
    let withdrawn_log = conn
        .execute(INSERT_WITHDRAW_AUDIT, rusqlite::params![T0, AIKO, id])
        .unwrap();
    let withdrawn = conn
        .execute(WITHDRAW, rusqlite::params![id, AIKO, T0])
        .unwrap();
    drop(conn);
    assert_eq!((logged, changed, withdrawn_log, withdrawn), (0, 0, 0, 0));
    assert_eq!(audit_actions(&s).len(), before);
}
