mod support;

use review_api::data::DataFile;
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

fn n5_examples() -> Value {
    json!({"dataset": "verbs", "kinds": ["example"], "jlpt": ["N5"]})
}

async fn create(s: &SqliteStore, title: &str, filter: Value) -> Value {
    let r = post(
        s,
        "/api/admin/queues",
        json!({"title": title, "description": "", "filter": filter}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body
}

async fn queue(s: &SqliteStore, id: &Value, who: &str) -> Value {
    let r = get(s, &format!("/api/queue?id={id}"), who).await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body
}

fn target_of(item: &Value) -> Value {
    json!({"dataset": item["dataset"], "kind": item["kind"], "id": item["item_id"]})
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_builds_a_queue_and_reviewers_work_through_it() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/admin/queues/preview",
        json!({"filter": n5_examples(), "ids_text": ""}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    let count = r.body["count"].as_u64().unwrap();
    assert!(count > 0 && count <= 500, "{count}");
    assert!(r.body["items"].as_array().unwrap().len() <= 50);

    let created = create(&s, "N5 verb examples", n5_examples()).await;
    let id = created["queue"]["id"].clone();
    assert_eq!(created["queue"]["total"].as_u64(), Some(count));
    let first = created["items"][0].clone();
    let mut note = target_of(&first);
    note["queue_id"] = id.clone();
    note["note"] = json!("Is this natural?");
    let r = post(&s, "/api/admin/queues/note", note, MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);

    let r = get(&s, "/api/queues", AIKO).await;
    let listed = r.body["queues"].as_array().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["done"], 0);

    let body = queue(&s, &id, AIKO).await;
    assert_eq!(body["items"][0]["note"], "Is this natural?");

    let mut skip = target_of(&body["items"][0]);
    skip["queue_id"] = id.clone();
    let r = post(&s, "/api/queue/skip", skip, AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["queue"]["done"], 1);
    let second = &body["items"][1];
    let hash = s_hash(&s, second).await;
    let mut approve = target_of(second);
    approve["content_hash"] = json!(hash);
    let r = post(&s, "/api/approve", approve, AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let body = queue(&s, &id, AIKO).await;
    assert_eq!(body["queue"]["done"], 2);
    assert_eq!(body["items"][0]["mine"], "skipped");
    assert_eq!(body["items"][1]["mine"], "approved");
}

async fn s_hash(s: &SqliteStore, item: &Value) -> String {
    let r = get(
        s,
        &format!(
            "/api/review?{}",
            q(&[
                ("dataset", item["dataset"].as_str().unwrap()),
                ("id", item["entry_id"].as_str().unwrap())
            ])
        ),
        AIKO,
    )
    .await;
    r.body["parts"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["item_id"] == item["item_id"] && p["kind"] == item["kind"])
        .unwrap()["content_hash"]
        .as_str()
        .unwrap()
        .into()
}

#[tokio::test(flavor = "current_thread")]
async fn pasted_ids_report_what_didnt_match() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/admin/queues/preview",
        json!({"filter": {"dataset": "verbs"}, "ids_text": "たべる\nnope\n\n  のむ  "}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["count"], 2);
    assert_eq!(r.body["unmatched"], json!(["nope"]));
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "Two verbs", "description": "",
        "filter": {"dataset": "verbs"}, "ids_text": "たべる\nnope\nのむ"}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["queue"]["total"], 2);
}

#[tokio::test(flavor = "current_thread")]
async fn limits_and_empty_queues() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "  ", "description": "", "filter": n5_examples()}),
        MARTIN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("a queue needs a title"))
    );
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "x".repeat(81), "description": "", "filter": n5_examples()}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 400);
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "None", "description": "",
        "filter": {"dataset": "verbs", "ids": ["nope"]}}),
        MARTIN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("nothing matches"))
    );
    let many: String = (0..501).map(|i| format!("id{i}\n")).collect();
    let r = post(
        &s,
        "/api/admin/queues/preview",
        json!({"filter": {"dataset": "verbs"}, "ids_text": many}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 400);
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "All", "description": "", "filter": {"dataset": "verbs"}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 400);
    assert_eq!(
        r.body["error"],
        "a queue holds at most 500 items; narrow the filter"
    );
    let r = post(
        &s,
        "/api/admin/queues",
        json!({"title": "Bad", "description": "", "filter": {"dataset": "furigana"}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn archived_queues_leave_the_home_list() {
    let s = seeded().await;
    let created = create(
        &s,
        "Short",
        json!({"dataset": "words", "ids": ["i-adjective:いい"]}),
    )
    .await;
    let id = created["queue"]["id"].clone();
    let r = post(
        &s,
        "/api/admin/queues/update",
        json!({"id": id, "title": "Short", "description": "d", "archived": true}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    let r = get(&s, "/api/queues", AIKO).await;
    assert!(r.body["queues"].as_array().unwrap().is_empty());
    let r = get(&s, &format!("/api/queue?id={id}"), AIKO).await;
    assert_eq!(r.status, 404);
    let r = get(&s, "/api/admin/queues", MARTIN).await;
    assert_eq!(r.body["queues"][0]["archived"], true);
    assert_eq!(r.body["queues"][0]["description"], "d");
    let r = get(&s, &format!("/api/queue?id={id}"), MARTIN).await;
    assert_eq!(r.status, 200);
    let r = post(
        &s,
        "/api/admin/queues/update",
        json!({"id": 999, "title": "x", "description": "", "archived": false}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_removes_an_item() {
    let s = seeded().await;
    let created = create(
        &s,
        "Two",
        json!({"dataset": "words", "ids": ["i-adjective:いい", "i-adjective:おおきい"]}),
    )
    .await;
    let id = created["queue"]["id"].clone();
    let mut body = target_of(&created["items"][0]);
    body["queue_id"] = id.clone();
    let r = post(&s, "/api/admin/queues/remove", body.clone(), MARTIN).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(queue(&s, &id, AIKO).await["queue"]["total"], 1);
    let r = post(&s, "/api/admin/queues/remove", body, MARTIN).await;
    assert_eq!(r.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn reviewers_cannot_build_queues() {
    let s = seeded().await;
    for (method, path) in [
        ("GET", "/api/admin/queues"),
        ("POST", "/api/admin/queues"),
        ("POST", "/api/admin/queues/preview"),
        ("POST", "/api/admin/queues/update"),
        ("POST", "/api/admin/queues/note"),
        ("POST", "/api/admin/queues/remove"),
    ] {
        let r = call(&s, method, path, Some(json!({})), AIKO).await;
        assert_eq!(r.status, 403, "{path}");
    }
}

#[tokio::test(flavor = "current_thread")]
async fn a_gone_item_counts_as_done() {
    let s = seeded().await;
    let tabe_queue = create(
        &s,
        "One verb",
        json!({"dataset": "verbs", "ids": ["たべる", "のむ"]}),
    )
    .await;
    let id = tabe_queue["queue"]["id"].clone();
    let mut d = doc(DataFile::Verbs);
    d["verbs"]
        .as_array_mut()
        .unwrap()
        .retain(|v| v["dict"] != "たべる");
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    for who in [AIKO, BEN] {
        let body = queue(&s, &id, who).await;
        assert_eq!(body["queue"]["done"], 1, "{who}");
        let gone = body["items"]
            .as_array()
            .unwrap()
            .iter()
            .find(|i| i["item_id"] == "たべる")
            .unwrap()
            .clone();
        assert_eq!(gone["gone"], true);
        assert_eq!(gone["title"], "たべる (食べる)");
    }
}
