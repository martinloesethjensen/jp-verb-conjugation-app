mod support;

use review_api::data::DataFile;
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

const STALE: &str = "this changed since you opened it; reload to see the new version";

async fn review(s: &SqliteStore, id: &str, who: &str) -> Value {
    let r = get(
        s,
        &format!("/api/review?{}", q(&[("dataset", "verbs"), ("id", id)])),
        who,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body
}

/// たべる's parts as `(kind, id, hash)`, from the API.
async fn parts(s: &SqliteStore) -> Vec<(String, String, String)> {
    review(s, "たべる", AIKO).await["parts"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| {
            (
                p["kind"].as_str().unwrap().into(),
                p["item_id"].as_str().unwrap().into(),
                p["content_hash"].as_str().unwrap().into(),
            )
        })
        .collect()
}

async fn first_example(s: &SqliteStore) -> (String, String) {
    let p = parts(s).await;
    let (_, id, hash) = p.iter().find(|p| p.0 == "example").unwrap();
    (id.clone(), hash.clone())
}

fn approve_body(kind: &str, id: &str, hash: &str) -> Value {
    json!({"dataset": "verbs", "kind": kind, "id": id, "content_hash": hash})
}

fn en_change(id: &str, hash: &str, en: &str) -> Value {
    json!({"dataset": "verbs", "kind": "example", "id": id, "base_hash": hash,
           "action": "change", "edits": {"en": en}})
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_approves_and_everyone_sees_it() {
    let s = seeded().await;
    let p = parts(&s).await;
    assert_eq!(p[0].0, "entry");
    assert_eq!(p[0].1, "たべる");
    assert!(p.len() > 2);
    let r = post(
        &s,
        "/api/approve",
        approve_body("entry", "たべる", &p[0].2),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["approvals"].as_array().unwrap().len(), 1);
    let (ex, hash) = first_example(&s).await;
    let r = post(
        &s,
        "/api/approve",
        approve_body("example", &ex, &hash),
        AIKO,
    )
    .await;
    assert_eq!(r.body["approvals"].as_array().unwrap().len(), 2);

    let ben = review(&s, "たべる", BEN).await;
    let approvals = ben["approvals"].as_array().unwrap();
    assert_eq!(approvals.len(), 2);
    assert!(approvals
        .iter()
        .all(|a| a["reviewer_name"] == "Aiko" && a["mine"] == false));
    assert!(approvals.iter().all(|a| a["current"] == true));
    let mine = review(&s, "たべる", AIKO).await;
    assert!(mine["approvals"]
        .as_array()
        .unwrap()
        .iter()
        .all(|a| a["mine"] == true));

    let r = get(&s, "/api/items?dataset=verbs", BEN).await;
    let tabe = r.body["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|i| i["item_id"] == "たべる")
        .unwrap()
        .clone();
    assert_eq!(tabe["approved"], 2);
    assert_eq!(tabe["open"], 0);
    assert_eq!(tabe["targets"], json!(p.len()));

    let r = post(
        &s,
        "/api/approve/withdraw",
        json!({"dataset": "verbs", "kind": "example", "id": ex}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["approvals"].as_array().unwrap().len(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn approving_an_old_version_is_refused() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/approve",
        approve_body("entry", "たべる", "old"),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 409);
    assert_eq!(r.body["error"], STALE);
    let r = post(
        &s,
        "/api/approve",
        approve_body("thing", "たべる", "old"),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 404);
    assert_eq!(r.body["error"], "that isn't in the loaded data");
    let r = post(
        &s,
        "/api/approve",
        approve_body("nonsense", "たべる", "old"),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn a_change_is_stored_as_the_whole_proposed_item() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let r = post(
        &s,
        "/api/suggest",
        en_change(&ex, &hash, "A new English line."),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    let tabe = doc(DataFile::Verbs)["verbs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["dict"] == "たべる")
        .unwrap()
        .clone();
    let mut expected = tabe["examples"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"] == ex.as_str())
        .unwrap()
        .clone();
    expected["en"] = json!("A new English line.");
    assert_eq!(r.body["proposed"], expected);
    assert_eq!(r.body["stale"], false);
    assert_eq!(r.body["author_name"], "Aiko");
    assert_eq!(r.body["action"], "change");
    assert_eq!(r.body["item_title"], tabe["examples"][0]["jp"]);
}

#[tokio::test(flavor = "current_thread")]
async fn the_same_suggestion_twice_returns_the_first() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let first = post(&s, "/api/suggest", en_change(&ex, &hash, "Again."), AIKO).await;
    let second = post(&s, "/api/suggest", en_change(&ex, &hash, "Again."), AIKO).await;
    assert_eq!((first.status, second.status), (201, 200));
    assert_eq!(first.body["id"], second.body["id"]);
}

#[tokio::test(flavor = "current_thread")]
async fn a_reload_makes_open_suggestions_stale_and_new_ones_refused() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let made = post(&s, "/api/suggest", en_change(&ex, &hash, "Mine."), AIKO).await;
    let mut d = doc(DataFile::Verbs);
    for verb in d["verbs"].as_array_mut().unwrap() {
        for example in verb["examples"].as_array_mut().unwrap() {
            if example["id"] == ex.as_str() {
                example["en"] = json!("Changed by Martin.");
            }
        }
    }
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    let body = review(&s, "たべる", BEN).await;
    let listed = body["suggestions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|x| x["id"] == made.body["id"])
        .unwrap()
        .clone();
    assert_eq!(listed["stale"], true);
    let r = post(&s, "/api/suggest", en_change(&ex, &hash, "Another."), BEN).await;
    assert_eq!(r.status, 409);
    assert_eq!(r.body["error"], STALE);
}

#[tokio::test(flavor = "current_thread")]
async fn locked_and_unknown_fields_come_back_as_400() {
    let s = seeded().await;
    let p = parts(&s).await;
    let body = json!({"dataset": "verbs", "kind": "entry", "id": "たべる", "base_hash": p[0].2,
                      "action": "change", "edits": {"dict": "x"}});
    let r = post(&s, "/api/suggest", body, AIKO).await;
    assert_eq!(r.status, 400);
    assert_eq!(
        r.body["error"],
        "dict can't be changed here; leave a note instead"
    );
    let body = json!({"dataset": "verbs", "kind": "entry", "id": "たべる", "base_hash": p[0].2,
                      "action": "change", "edits": {"meaning": "to eat"}});
    let r = post(&s, "/api/suggest", body, AIKO).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("nothing changed"))
    );
}

#[tokio::test(flavor = "current_thread")]
async fn furigana_rides_along_with_a_change() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let mut body = en_change(&ex, &hash, "With a reading.");
    body["furigana"] = json!({"鰐": "わに"});
    let r = post(&s, "/api/suggest", body.clone(), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["furigana"], json!({"鰐": "わに"}));
    body["furigana"] = json!({"猫": "ねこ"});
    let r = post(&s, "/api/suggest", body, AIKO).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("猫 already has a reading"))
    );
    let r = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "example", "id": ex,
        "base_hash": hash, "action": "delete", "furigana": {"鰐": "わに"}}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn a_note_and_a_delete() {
    let s = seeded().await;
    let p = parts(&s).await;
    let (_, colloc, colloc_hash) = p.iter().find(|p| p.0 == "collocation").unwrap().clone();
    let note = |comment: Option<&str>| {
        let mut b = json!({"dataset": "verbs", "kind": "entry", "id": "たべる", "base_hash": p[0].2, "action": "note"});
        if let Some(c) = comment {
            b["comment"] = json!(c);
        }
        b
    };
    let r = post(&s, "/api/suggest", note(None), AIKO).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("a note needs a comment"))
    );
    let r = post(&s, "/api/suggest", note(Some("   ")), AIKO).await;
    assert_eq!(r.status, 400);
    let r = post(&s, "/api/suggest", note(Some("The kanji looks off.")), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["action"], "note");
    assert_eq!(r.body["proposed"], Value::Null);
    let r = post(
        &s,
        "/api/suggest",
        json!({"dataset": "verbs", "kind": "collocation", "id": colloc,
        "base_hash": colloc_hash, "action": "delete"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    let body = json!({"dataset": "verbs", "kind": "collocation", "id": colloc, "base_hash": colloc_hash,
                      "action": "change", "edits": {"en": "Ben's version"}});
    let r = post(&s, "/api/suggest", body, BEN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    let all = review(&s, "たべる", AIKO).await;
    assert_eq!(all["suggestions"].as_array().unwrap().len(), 3);
    let r = get(&s, "/api/items?dataset=verbs", BEN).await;
    let tabe = r.body["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|i| i["item_id"] == "たべる")
        .unwrap()
        .clone();
    assert_eq!(tabe["open"], 3);
}

#[tokio::test(flavor = "current_thread")]
async fn only_the_author_withdraws() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let made = post(&s, "/api/suggest", en_change(&ex, &hash, "Mine."), AIKO).await;
    let id = made.body["id"].clone();
    let r = post(&s, "/api/suggest/withdraw", json!({"id": id}), BEN).await;
    assert_eq!(r.status, 403);
    assert_eq!(
        r.body["error"],
        "only the person who suggested it can withdraw it"
    );
    let r = post(&s, "/api/suggest/withdraw", json!({"id": id}), AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["status"], "withdrawn");
    let r = post(&s, "/api/suggest/withdraw", json!({"id": id}), AIKO).await;
    assert_eq!(r.status, 409);
    assert_eq!(r.body["error"], "this suggestion has already been decided");
}

#[tokio::test(flavor = "current_thread")]
async fn comments_show_on_the_suggestion() {
    let s = seeded().await;
    let (ex, hash) = first_example(&s).await;
    let made = post(&s, "/api/suggest", en_change(&ex, &hash, "Mine."), AIKO).await;
    let id = made.body["id"].clone();
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": id, "body": "Why this?"}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": id, "body": "It's more natural."}),
        AIKO,
    )
    .await;
    assert_eq!(r.body["comments"].as_array().unwrap().len(), 2);
    let body = review(&s, "たべる", BEN).await;
    let comments = body["suggestions"][0]["comments"]
        .as_array()
        .unwrap()
        .clone();
    let names: Vec<_> = comments
        .iter()
        .map(|c| c["author_name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Martin", "Aiko"]);
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": 9999, "body": "x"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 404);
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": id, "body": " "}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": id, "body": "あ".repeat(2001)}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn targets_that_left_the_data() {
    let s = seeded().await;
    let p = parts(&s).await;
    let (ex, hash) = first_example(&s).await;
    post(&s, "/api/suggest", en_change(&ex, &hash, "Mine."), AIKO).await;
    let mut d = doc(DataFile::Verbs);
    d["verbs"]
        .as_array_mut()
        .unwrap()
        .retain(|v| v["dict"] != "たべる");
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    let r = post(
        &s,
        "/api/approve",
        approve_body("entry", "たべる", &p[0].2),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 404);
    let body = review(&s, "たべる", AIKO).await;
    assert!(body["parts"].as_array().unwrap().is_empty());
    let suggestions = body["suggestions"].as_array().unwrap();
    assert_eq!(suggestions.len(), 1);
    assert_eq!(suggestions[0]["gone"], true);
}

#[tokio::test(flavor = "current_thread")]
async fn reference_serves_the_field_table() {
    let s = seeded().await;
    let r = get(&s, "/api/reference", AIKO).await;
    let fields = r.body["fields"]["verbs/example"].as_array().unwrap();
    let names: Vec<_> = fields.iter().map(|f| f["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["form", "jp", "en"]);
    assert_eq!(fields[0]["input"], "form");
    assert_eq!(
        r.body["fields"]["counters/thing"][3]["choices"],
        json!(["primary", "casual", "acceptable"])
    );
    assert!(r.body["fields"].get("words/example").is_none());
}

#[tokio::test(flavor = "current_thread")]
async fn wrong_origin_and_unknown_users() {
    let s = seeded().await;
    let p = parts(&s).await;
    let mut req_body = approve_body("entry", "たべる", &p[0].2);
    let r = post(&s, "/api/approve", req_body.clone(), "stranger@example.com").await;
    assert_eq!(r.status, 403);
    req_body["extra"] = json!(1);
    let r = post(&s, "/api/approve", req_body, AIKO).await;
    assert_eq!(r.status, 400, "unknown keys are refused");
    let cfg = review_api::app::AppConfig {
        access: support::cfg(),
        site_origin: SITE.into(),
    };
    let req = review_api::app::ApiRequest {
        method: "POST".into(),
        path: "/api/approve".into(),
        query: String::new(),
        origin: Some("https://evil.example".into()),
        jwt: Some(jwt(AIKO)),
        body: approve_body("entry", "たべる", &p[0].2)
            .to_string()
            .into_bytes(),
    };
    let r = review_api::app::handle(
        req,
        &cfg,
        &[support::jwk()],
        &s,
        &support::source::FakeSource::empty(),
        support::NOW,
        T0,
    )
    .await;
    assert_eq!(r.status, 403);
}

#[tokio::test(flavor = "current_thread")]
async fn writing_marks_the_thread_read_for_the_writer() {
    let s = seeded().await;
    let (id, hash) = first_example(&s).await;
    let r = post(&s, "/api/suggest", en_change(&id, &hash, "Read me."), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    let sid = r.body["id"].clone();
    let find = |body: &Value| {
        body["suggestions"]
            .as_array()
            .unwrap()
            .iter()
            .find(|x| x["id"] == sid)
            .unwrap()
            .clone()
    };
    assert!(find(&review(&s, "たべる", AIKO).await)["last_read"].is_string());
    assert!(find(&review(&s, "たべる", BEN).await)["last_read"].is_null());
    let r = post(
        &s,
        "/api/comment",
        json!({"suggestion_id": sid, "body": "Agreed."}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    let for_ben = find(&review(&s, "たべる", BEN).await);
    assert!(for_ben["last_read"].is_string());
    assert_eq!(for_ben["comments"][0]["mine"], true);
    assert_eq!(
        find(&review(&s, "たべる", AIKO).await)["comments"][0]["mine"],
        false
    );
}
