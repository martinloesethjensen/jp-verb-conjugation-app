mod support;

use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

/// たべる's `n`th example: `(id, hash)`.
async fn example(s: &SqliteStore, n: usize) -> (String, String) {
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
        .filter(|p| p["kind"] == "example")
        .nth(n)
        .unwrap()
        .clone();
    (
        part["item_id"].as_str().unwrap().into(),
        part["content_hash"].as_str().unwrap().into(),
    )
}

async fn suggest_en(s: &SqliteStore, who: &str, n: usize, en: &str) -> i64 {
    let (id, hash) = example(s, n).await;
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

async fn decide(s: &SqliteStore, id: i64, decision: &str, reply: Option<&str>) {
    let mut body = json!({"id": id, "decision": decision});
    if let Some(reply) = reply {
        body["reply"] = json!(reply);
    }
    let r = post(s, "/api/decide", body, MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
}

async fn contributions(s: &SqliteStore, who: &str) -> Value {
    let r = get(s, "/api/contributions", who).await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body
}

fn ids(list: &Value) -> Vec<i64> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|c| c["id"].as_i64().unwrap())
        .collect()
}

/// Files `suggestion` under a release, the way a finished load would (the load's own claim is tested in
/// `stepped_load`): one `data_releases` row, then `released_in`.
fn release(s: &SqliteStore, label: &str, sha: Option<&str>, suggestion: i64) {
    let conn = s.conn.borrow();
    conn.execute(
        "INSERT OR IGNORE INTO data_releases (manifest_sha256, label, first_loaded_at) VALUES (?1, ?2, ?3)",
        rusqlite::params![sha, label, sha.map(|_| "2026-11-07T08:00:00Z")],
    )
    .unwrap();
    conn.execute(
        "UPDATE suggestions SET released_in = (SELECT id FROM data_releases WHERE label = ?1), exported_at = ?3 WHERE id = ?2",
        rusqlite::params![label, suggestion, "2026-11-06T08:00:00Z"],
    )
    .unwrap();
}

#[tokio::test(flavor = "current_thread")]
async fn counts_and_groups_match_the_viewers_work() {
    let s = seeded().await;
    let open = suggest_en(&s, AIKO, 0, "Open.").await;
    let live = suggest_en(&s, AIKO, 1, "Live.").await;
    let waiting = suggest_en(&s, AIKO, 2, "Accepted, waiting.").await;
    let declined = suggest_en(&s, AIKO, 3, "Declined.").await;
    let withdrawn = suggest_en(&s, AIKO, 4, "Withdrawn.").await;
    decide(&s, live, "accept", None).await;
    decide(&s, waiting, "accept", None).await;
    decide(&s, declined, "decline", Some("Too literal.")).await;
    let r = post(&s, "/api/suggest/withdraw", json!({"id": withdrawn}), AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    release(&s, "2026.11.07", Some("sha-a"), live);

    let c = contributions(&s, AIKO).await;
    assert_eq!(
        c["counts"],
        json!({"approved": 0, "suggested": 4, "accepted": 2, "live": 1})
    );
    let releases = c["releases"].as_array().unwrap();
    assert_eq!(releases.len(), 1);
    assert_eq!(releases[0]["label"], "2026.11.07");
    assert_eq!(releases[0]["loaded_at"], "2026-11-07T08:00:00Z");
    assert_eq!(ids(&releases[0]["changes"]), vec![live]);
    assert_eq!(ids(&c["accepted"]), vec![waiting]);
    assert_eq!(ids(&c["waiting"]), vec![open]);
    assert_eq!(ids(&c["declined"]), vec![declined]);
    assert_eq!(c["declined"][0]["reason"]["body"], "Too literal.");
    assert_eq!(c["declined"][0]["reason"]["by_name"], "Martin");
    assert_eq!(c["accepted"][0]["reason"], Value::Null);

    // An open suggestion's `before` is the current item.
    assert_eq!(c["waiting"][0]["before"], doc_example());
    assert_eq!(c["waiting"][0]["proposed"]["en"], "Open.");
    assert_eq!(c["waiting"][0]["replies"], 0);
    assert_eq!(c["declined"][0]["replies"], 1);
    assert!(c["waiting"][0].get("email").is_none());
    assert!(!c.to_string().contains("@example.com"));
}

fn doc_example() -> Value {
    use review_api::data::DataFile;
    doc(DataFile::Verbs)["verbs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["dict"] == "たべる")
        .unwrap()["examples"][0]
        .clone()
}

#[tokio::test(flavor = "current_thread")]
async fn accepted_changes_show_the_recorded_before_and_earlier_releases_go_last() {
    let s = seeded().await;
    let a = suggest_en(&s, AIKO, 0, "One.").await;
    let b = suggest_en(&s, AIKO, 1, "Two.").await;
    let c = suggest_en(&s, AIKO, 2, "Three.").await;
    for id in [a, b, c] {
        decide(&s, id, "accept", None).await;
    }
    release(&s, "Earlier releases", None, a);
    release(&s, "2026.11.07", Some("sha-a"), b);
    release(&s, "2026.11.21", Some("sha-b"), c);
    s.conn
        .borrow()
        .execute(
            "UPDATE suggestions SET before_json = '{\"en\":\"Was.\"}' WHERE id = ?1",
            [c],
        )
        .unwrap();
    // A release that holds nobody's work from Aiko is not listed.
    s.conn
        .borrow()
        .execute(
            "INSERT INTO data_releases (manifest_sha256, label, first_loaded_at) VALUES ('sha-c', '2026.11.24', 'x')",
            [],
        )
        .unwrap();

    let body = contributions(&s, AIKO).await;
    let labels: Vec<&str> = body["releases"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["label"].as_str().unwrap())
        .collect();
    assert_eq!(labels, ["2026.11.21", "2026.11.07", "Earlier releases"]);
    assert_eq!(
        body["releases"][0]["changes"][0]["before"],
        json!({"en": "Was."})
    );
    // Accepting records the target as it was, so the second one has it without our help.
    assert_eq!(
        body["releases"][1]["changes"][0]["before"]["id"],
        body["releases"][1]["changes"][0]["item_id"]
    );
    assert_eq!(body["releases"][2]["loaded_at"], Value::Null);
    assert_eq!(body["counts"]["live"], 3);
}

#[tokio::test(flavor = "current_thread")]
async fn nobody_sees_anyone_elses_contributions() {
    let s = seeded().await;
    suggest_en(&s, AIKO, 0, "Aiko's.").await;
    let (id, hash) = example(&s, 0).await;
    let r = post(
        &s,
        "/api/approve",
        json!({"dataset": "verbs", "kind": "example", "id": id, "content_hash": hash}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    let c = contributions(&s, BEN).await;
    assert_eq!(
        c["counts"],
        json!({"approved": 0, "suggested": 0, "accepted": 0, "live": 0})
    );
    for list in ["accepted", "waiting", "declined", "releases", "datasets"] {
        assert_eq!(c[list], json!([]), "{list}");
    }
}

#[tokio::test(flavor = "current_thread")]
async fn credit_shows_the_public_name_and_role() {
    let s = seeded().await;
    let c = contributions(&s, AIKO).await;
    assert_eq!(c["credit"], json!({"name": null, "role": "native"}));
    s.conn
        .borrow()
        .execute(
            "UPDATE users SET public_name = 'Keiko S.', public_role = 'teacher' WHERE email = ?1",
            [KEIKO],
        )
        .unwrap();
    let c = contributions(&s, KEIKO).await;
    assert_eq!(c["credit"], json!({"name": "Keiko S.", "role": "teacher"}));
}

#[tokio::test(flavor = "current_thread")]
async fn per_dataset_counts() {
    let s = seeded().await;
    suggest_en(&s, AIKO, 0, "One.").await;
    suggest_en(&s, AIKO, 1, "Two.").await;
    for (dataset, id) in [("verbs", "たべる"), ("words", "i-adjective:いい")] {
        let r = get(
            &s,
            &format!("/api/review?{}", q(&[("dataset", dataset), ("id", id)])),
            AIKO,
        )
        .await;
        let hash = r.body["parts"][0]["content_hash"].as_str().unwrap();
        let r = post(
            &s,
            "/api/approve",
            json!({"dataset": dataset, "kind": "entry", "id": id, "content_hash": hash}),
            AIKO,
        )
        .await;
        assert_eq!(r.status, 200, "{}", r.body);
    }
    let c = contributions(&s, AIKO).await;
    assert_eq!(c["counts"]["approved"], 2);
    assert_eq!(
        c["datasets"],
        json!([
            {"dataset": "verbs", "approved": 1, "suggested": 2},
            {"dataset": "words", "approved": 1, "suggested": 0},
        ])
    );
}
