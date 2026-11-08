mod support;

use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

const POINT: &str = "hou-ga-ii";

/// `(kind, id, content_hash)` of every part of a grammar point.
async fn parts_of(s: &SqliteStore, dataset: &str, id: &str) -> Vec<(String, String, String)> {
    let r = get(
        s,
        &format!("/api/review?{}", q(&[("dataset", dataset), ("id", id)])),
        AIKO,
    )
    .await;
    r.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| {
            let text = |k: &str| p[k].as_str().unwrap().to_string();
            (text("kind"), text("item_id"), text("content_hash"))
        })
        .collect()
}

async fn approve(s: &SqliteStore, dataset: &str, part: &(String, String, String), who: &str) {
    let body = json!({"dataset": dataset, "kind": part.0, "id": part.1, "content_hash": part.2});
    let r = post(s, "/api/approve", body, who).await;
    assert_eq!(r.status, 200, "{}", r.body);
}

async fn approve_all(s: &SqliteStore, dataset: &str, id: &str, who: &str) {
    for part in parts_of(s, dataset, id).await {
        approve(s, dataset, &part, who).await;
    }
}

async fn stamp(s: &SqliteStore, dataset: &str, id: &str, who: &str) -> Response {
    post(
        s,
        "/api/admin/stamp",
        json!({"dataset": dataset, "id": id}),
        who,
    )
    .await
}

async fn review(s: &SqliteStore, id: &str) -> Value {
    get(
        s,
        &format!("/api/review?{}", q(&[("dataset", "grammar"), ("id", id)])),
        MARTIN,
    )
    .await
    .body
}

#[tokio::test(flavor = "current_thread")]
async fn a_fully_approved_grammar_point_is_stamped_by_its_most_senior_reviewer() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/admin/users/role",
        json!({"email": BEN, "public_role": "teacher"}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    approve_all(&s, "grammar", POINT, AIKO).await;
    assert_eq!(review(&s, POINT).await["stampable"], true);
    let parts = parts_of(&s, "grammar", POINT).await;
    approve(&s, "grammar", &parts[3], BEN).await;
    let r = stamp(&s, "grammar", POINT, MARTIN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["by"], "teacher");
    assert_eq!(r.body["name"], Value::Null);
    assert_eq!(r.body["item_id"], POINT);
    assert_eq!(r.body["content_hash"], parts[0].2);
    let shown = review(&s, POINT).await;
    assert_eq!(shown["stamp"]["by"], "teacher");
    assert_eq!(shown["stamp"]["reviewer_name"], "Ben");
}

#[tokio::test(flavor = "current_thread")]
async fn stamping_needs_every_part_approved() {
    let s = seeded().await;
    let parts = parts_of(&s, "grammar", POINT).await;
    for part in &parts[1..] {
        approve(&s, "grammar", part, AIKO).await;
    }
    assert_eq!(review(&s, POINT).await["stampable"], false);
    let r = stamp(&s, "grammar", POINT, MARTIN).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("every part needs an approval first"))
    );
}

#[tokio::test(flavor = "current_thread")]
async fn stamping_waits_for_open_suggestions() {
    let s = seeded().await;
    approve_all(&s, "grammar", POINT, AIKO).await;
    let parts = parts_of(&s, "grammar", POINT).await;
    let note = json!({"dataset": "grammar", "kind": parts[0].0, "id": POINT, "base_hash": parts[0].2,
                      "action": "note", "comment": "Is this natural?"});
    let r = post(&s, "/api/suggest", note, BEN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    let r = stamp(&s, "grammar", POINT, MARTIN).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("settle its open suggestions first"))
    );
}

async fn stamp_kind(s: &SqliteStore, dataset: &str, kind: &str, id: &str) -> Response {
    post(
        s,
        "/api/admin/stamp",
        json!({"dataset": dataset, "kind": kind, "id": id}),
        MARTIN,
    )
    .await
}

async fn note_on(s: &SqliteStore, dataset: &str, part: &(String, String, String)) {
    let note = json!({"dataset": dataset, "kind": part.0, "id": part.1, "base_hash": part.2,
                      "action": "note", "comment": "Is this natural?"});
    let r = post(s, "/api/suggest", note, BEN).await;
    assert_eq!(r.status, 201, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn verb_readiness_skips_examples_and_examples_stand_alone() {
    let s = seeded().await;
    let parts = parts_of(&s, "verbs", "たべる").await;
    let of = |kind: &str| -> Vec<(String, String, String)> {
        parts.iter().filter(|p| p.0 == kind).cloned().collect()
    };
    let (examples, phrases) = (of("example"), of("collocation"));
    assert!(examples.len() >= 2 && !phrases.is_empty());
    for part in of("entry").iter().chain(&phrases) {
        approve(&s, "verbs", part, AIKO).await;
    }
    // An open suggestion on an example doesn't hold the verb back.
    note_on(&s, "verbs", &examples[0]).await;
    let r = stamp(&s, "verbs", "たべる", MARTIN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["kind"], "entry");
    let r = post(
        &s,
        "/api/admin/stamp/withdraw",
        json!({"dataset": "verbs", "id": "たべる"}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    // One on a collocation does.
    note_on(&s, "verbs", &phrases[0]).await;
    let r = stamp(&s, "verbs", "たべる", MARTIN).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("settle its open suggestions first"))
    );
    // An example stands alone: its own approval, named by its approver.
    approve(&s, "verbs", &examples[1], BEN).await;
    let r = stamp_kind(&s, "verbs", "example", &examples[1].1).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(
        (r.body["kind"].as_str(), r.body["reviewer_name"].as_str()),
        (Some("example"), Some("Ben"))
    );
    assert_eq!(r.body["content_hash"], examples[1].2);
    assert_eq!(r.body["entry_id"], "たべる");
    let r = stamp_kind(&s, "verbs", "example", &examples[0].1).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("every part needs an approval first"))
    );
    let r = post(
        &s,
        "/api/admin/stamp/withdraw",
        json!({"dataset": "verbs", "kind": "example", "id": examples[1].1}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn words_take_a_stamp() {
    let s = seeded().await;
    approve_all(&s, "words", "i-adjective:いい", AIKO).await;
    let r = stamp(&s, "words", "i-adjective:いい", MARTIN).await;
    assert_eq!(r.status, 201, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn grammar_examples_cannot_be_stamped_alone() {
    let s = seeded().await;
    let parts = parts_of(&s, "grammar", POINT).await;
    let example = parts.iter().find(|p| p.0 == "example").unwrap();
    let r = stamp_kind(&s, "grammar", "example", &example.1).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("this can't take a stamp"))
    );
}

#[tokio::test(flavor = "current_thread")]
async fn ready_list_includes_verbs_words_and_verb_examples() {
    let s = seeded().await;
    let parts = parts_of(&s, "verbs", "たべる").await;
    for part in parts.iter().filter(|p| p.0 != "example") {
        approve(&s, "verbs", part, AIKO).await;
    }
    let example = parts.iter().find(|p| p.0 == "example").unwrap().clone();
    approve(&s, "verbs", &example, AIKO).await;
    approve_all(&s, "words", "i-adjective:いい", AIKO).await;
    let r = get(&s, "/api/admin/stampable", MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let rows: Vec<(String, String, String, String, String)> = r.body["entries"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            let t = |k: &str| e[k].as_str().unwrap().to_string();
            (
                t("dataset"),
                t("kind"),
                t("item_id"),
                t("entry_id"),
                t("entry_title"),
            )
        })
        .collect();
    let title = rows
        .iter()
        .find(|r| r.2 == "たべる")
        .map(|r| r.4.clone())
        .unwrap();
    assert_eq!(
        rows,
        vec![
            (
                "verbs".into(),
                "entry".into(),
                "たべる".into(),
                "たべる".into(),
                title.clone()
            ),
            (
                "verbs".into(),
                "example".into(),
                example.1.clone(),
                "たべる".into(),
                title
            ),
            (
                "words".into(),
                "entry".into(),
                "i-adjective:いい".into(),
                "i-adjective:いい".into(),
                rows.last().unwrap().4.clone()
            ),
        ]
    );
}

#[tokio::test(flavor = "current_thread")]
async fn stamping_twice_returns_the_pending_stamp() {
    let s = seeded().await;
    approve_all(&s, "grammar", POINT, AIKO).await;
    let first = stamp(&s, "grammar", POINT, MARTIN).await;
    let second = stamp(&s, "grammar", POINT, MARTIN).await;
    assert_eq!((first.status, second.status), (201, 200));
    assert_eq!(first.body["id"], second.body["id"]);
    assert_eq!(first.body["by"], "native");
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_cannot_stamp() {
    let s = seeded().await;
    approve_all(&s, "grammar", POINT, AIKO).await;
    assert_eq!(stamp(&s, "grammar", POINT, AIKO).await.status, 403);
}

#[tokio::test(flavor = "current_thread")]
async fn withdrawing_a_stamp_frees_the_entry() {
    let s = seeded().await;
    approve_all(&s, "grammar", POINT, AIKO).await;
    assert_eq!(stamp(&s, "grammar", POINT, MARTIN).await.status, 201);
    let r = post(
        &s,
        "/api/admin/stamp/withdraw",
        json!({"dataset": "grammar", "id": POINT}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(review(&s, POINT).await["stamp"], Value::Null);
    assert_eq!(stamp(&s, "grammar", POINT, MARTIN).await.status, 201);
}

#[tokio::test(flavor = "current_thread")]
async fn the_stamp_names_the_reviewers_public_name() {
    let s = seeded().await;
    let named = json!({"public_name": "Aiko S."});
    assert_eq!(
        post(&s, "/api/me/public-name", named, AIKO).await.status,
        200
    );
    approve_all(&s, "counters", "hon", AIKO).await;
    let r = stamp(&s, "counters", "hon", MARTIN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(
        (r.body["by"].as_str(), r.body["name"].as_str()),
        (Some("native"), Some("Aiko S."))
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_sees_what_is_ready_to_stamp() {
    let s = seeded().await;
    let ready = |r: &Response| -> Vec<String> {
        r.body["entries"]
            .as_array()
            .unwrap()
            .iter()
            .map(|e| {
                format!(
                    "{}/{}",
                    e["dataset"].as_str().unwrap(),
                    e["item_id"].as_str().unwrap()
                )
            })
            .collect()
    };
    assert_eq!(
        ready(&get(&s, "/api/admin/stampable", MARTIN).await),
        Vec::<String>::new()
    );
    approve_all(&s, "grammar", POINT, AIKO).await;
    let r = get(&s, "/api/admin/stampable", MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(ready(&r), vec![format!("grammar/{POINT}")]);
    assert_eq!(r.body["entries"][0]["title"], "〜ほうがいいです");
    assert_eq!(stamp(&s, "grammar", POINT, MARTIN).await.status, 201);
    assert_eq!(
        ready(&get(&s, "/api/admin/stampable", MARTIN).await),
        Vec::<String>::new()
    );
    assert_eq!(get(&s, "/api/admin/stampable", AIKO).await.status, 403);
}
