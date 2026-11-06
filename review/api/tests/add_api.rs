mod support;

use review_api::data::DataFile;
use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

fn example_add(jp: &str) -> Value {
    json!({"dataset": "verbs", "kind": "example", "parent": {"kind": "entry", "id": "たべる"},
           "fields": {"form": "te", "jp": jp, "en": "I eat, then sleep."}})
}

fn new_word(dict: &str, class: &str) -> Value {
    json!({"dataset": "words", "kind": "entry",
           "fields": {"class": class, "dict": dict, "kanji": "猫", "meaning": "cat", "jlpt": "N5"}})
}

async fn tabe_open(s: &SqliteStore) -> Value {
    let r = get(s, "/api/items?dataset=verbs", BEN).await;
    r.body["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|i| i["item_id"] == "たべる")
        .unwrap()["open"]
        .clone()
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_adds_an_example_and_everyone_sees_it() {
    let s = seeded().await;
    let r = post(&s, "/api/add", example_add("食べてから寝ます。"), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["action"], "add");
    assert_eq!(r.body["item_title"], "食べてから寝ます。");
    assert_eq!(r.body["parent_id"], "たべる");
    assert_eq!(r.body["proposed"]["id"], r.body["item_id"]);
    let review = get(
        &s,
        &format!(
            "/api/review?{}",
            q(&[("dataset", "verbs"), ("id", "たべる")])
        ),
        BEN,
    )
    .await;
    assert!(review.body["suggestions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|x| x["id"] == r.body["id"]));
    assert_eq!(tabe_open(&s).await, 1);
}

#[tokio::test(flavor = "current_thread")]
async fn the_same_addition_twice_returns_the_first() {
    let s = seeded().await;
    let first = post(&s, "/api/add", example_add("同じ文です。"), AIKO).await;
    let second = post(&s, "/api/add", example_add("同じ文です。"), AIKO).await;
    assert_eq!((first.status, second.status), (201, 200));
    assert_eq!(first.body["id"], second.body["id"]);
    let word = post(&s, "/api/add", new_word("ねこ", "noun"), AIKO).await;
    let again = post(&s, "/api/add", new_word("ねこ", "noun"), AIKO).await;
    assert_eq!((word.status, again.status), (201, 200));
    assert_eq!(word.body["id"], again.body["id"]);
}

#[tokio::test(flavor = "current_thread")]
async fn an_example_under_a_pitfall() {
    let s = seeded().await;
    let r = post(&s, "/api/add", json!({"dataset": "counters", "kind": "example",
        "parent": {"kind": "pitfall", "id": "pe3v3c"}, "fields": {"jp": "四人います。", "en": "There are four."}}), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["parent_kind"], "pitfall");
    assert_eq!(r.body["parent_id"], "pe3v3c");
    assert_eq!(r.body["entry_id"], "nin");
}

#[tokio::test(flavor = "current_thread")]
async fn wrong_parents_are_refused() {
    let s = seeded().await;
    let mut body = example_add("あ。");
    body["parent"]["id"] = json!("nobody");
    assert_eq!(post(&s, "/api/add", body, AIKO).await.status, 404);
    let point = doc(DataFile::Grammar)["grammar"][0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let r = post(
        &s,
        "/api/add",
        json!({"dataset": "grammar", "kind": "example",
        "parent": {"kind": "entry", "id": point}, "fields": {"jp": "a", "en": "b"}}),
        AIKO,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("example can't be added there"))
    );
    let mut word = new_word("ねこ", "noun");
    word["parent"] = json!({"kind": "entry", "id": "i-adjective:いい"});
    assert_eq!(post(&s, "/api/add", word, AIKO).await.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn new_entries_and_duplicates() {
    let s = seeded().await;
    let r = post(&s, "/api/add", new_word("ねこ", "noun"), AIKO).await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["item_id"], "noun:ねこ");
    assert_eq!(r.body["item_title"], "ねこ (猫)");
    let r = post(&s, "/api/add", new_word("ねこ", "noun"), BEN).await;
    assert_eq!(r.status, 409);
    assert_eq!(
        r.body["error"],
        "someone already suggested adding noun:ねこ; reply on their suggestion instead"
    );
    let mut taken = new_word("いい", "i-adjective");
    taken["fields"].as_object_mut().unwrap().remove("kanji");
    let r = post(&s, "/api/add", taken, AIKO).await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (409, Some("i-adjective:いい is already in the data"))
    );
    let r = get(&s, "/api/additions?dataset=words", BEN).await;
    let listed = r.body["suggestions"].as_array().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["item_id"], "noun:ねこ");
}

#[tokio::test(flavor = "current_thread")]
async fn a_new_verb_carries_readings_for_new_kanji() {
    let s = seeded().await;
    let fields = json!({
        "dict": "はしる", "kanji": "疾る", "type": "u", "meaning": "to dash", "description": "A u-verb.",
        "notes": "Rare spelling.", "jlpt": "N1",
        "masu_pos": "はしります", "masu_neg": "はしりません", "masu_past": "はしりました",
        "masu_past_neg": "はしりませんでした", "te": "はしって", "short_pos": "はしる",
        "short_neg": "はしらない", "short_past": "はしった", "short_past_neg": "はしらなかった",
        "example_form": "te", "example_jp": "疾って行った。", "example_en": "Dashed off."
    });
    let r = post(
        &s,
        "/api/add",
        json!({"dataset": "verbs", "kind": "entry", "fields": fields,
        "furigana": {"疾": "はし"}}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["furigana"], json!({"疾": "はし"}));
    assert_eq!(r.body["item_title"], "はしる (疾る)");
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_edits_then_accepts_an_addition() {
    let s = seeded().await;
    let made = post(&s, "/api/add", example_add("食べてから寝ます。"), AIKO).await;
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": made.body["id"], "decision": "accept",
        "edits": {"en": "First I eat, then I sleep."}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["admin_edit"]["en"], "First I eat, then I sleep.");
    assert_eq!(r.body["admin_edit"]["id"], made.body["proposed"]["id"]);

    let gone = post(&s, "/api/add", example_add("また食べます。"), AIKO).await;
    let mut d = doc(DataFile::Verbs);
    d["verbs"]
        .as_array_mut()
        .unwrap()
        .retain(|v| v["dict"] != "たべる");
    load_bytes(&s, DataFile::Verbs, d.to_string().as_bytes()).await;
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": gone.body["id"], "decision": "accept"}),
        MARTIN,
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (
            404,
            Some("the place this was added to isn't in the loaded data")
        )
    );
    let inbox = get(&s, "/api/admin/inbox", MARTIN).await;
    let listed = inbox.body["suggestions"]
        .as_array()
        .unwrap()
        .iter()
        .find(|x| x["id"] == gone.body["id"])
        .unwrap()
        .clone();
    assert_eq!(listed["gone"], true);
    assert_eq!(listed["current"], Value::Null);
}

#[tokio::test(flavor = "current_thread")]
async fn edit_then_accept_keeps_a_new_verbs_kanji_id() {
    let s = seeded().await;
    let fields = json!({
        "dict": "きる", "kanji": "斬る", "type": "u", "meaning": "to slash", "description": "A u-verb.",
        "notes": "Swords.", "jlpt": "N1",
        "masu_pos": "きります", "masu_neg": "きりません", "masu_past": "きりました",
        "masu_past_neg": "きりませんでした", "te": "きって", "short_pos": "きる",
        "short_neg": "きらない", "short_past": "きった", "short_past_neg": "きらなかった",
        "example_form": "te", "example_jp": "きってしまった。", "example_en": "Slashed it."
    });
    let made = post(
        &s,
        "/api/add",
        json!({"dataset": "verbs", "kind": "entry", "fields": fields}),
        AIKO,
    )
    .await;
    assert_eq!(made.status, 201, "{}", made.body);
    assert_eq!(made.body["item_id"], "きる:斬る");
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": made.body["id"], "decision": "accept",
        "edits": {"meaning": "to cut down (with a sword)"}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["admin_edit"]["id"], "きる:斬る");
    assert_eq!(
        r.body["admin_edit"]["examples"][0]["id"],
        made.body["proposed"]["examples"][0]["id"]
    );
}

#[tokio::test(flavor = "current_thread")]
async fn reference_serves_add_fields() {
    let s = seeded().await;
    let r = get(&s, "/api/reference", AIKO).await;
    let verb = r.body["add_fields"]["verbs/entry"]
        .as_array()
        .unwrap()
        .to_vec();
    assert!(verb.iter().any(|f| f["name"] == "masu_pos"));
    assert_eq!(
        verb.iter().find(|f| f["name"] == "dict").unwrap()["input"],
        "kana"
    );
    assert_eq!(
        r.body["add_parents"]["grammar/example"],
        json!(["usage", "pitfall"])
    );
    let counter = r.body["add_fields"]["counters/entry"].as_array().unwrap();
    assert_eq!(
        counter.iter().find(|f| f["name"] == "symbol").unwrap()["default"],
        "number"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn reviewers_cannot_add_with_a_foreign_origin() {
    let s = seeded().await;
    let cfg = review_api::app::AppConfig {
        access: support::cfg(),
        site_origin: SITE.into(),
    };
    let req = review_api::app::ApiRequest {
        method: "POST".into(),
        path: "/api/add".into(),
        query: String::new(),
        origin: Some("https://evil.example".into()),
        jwt: Some(jwt(AIKO)),
        body: example_add("あ。").to_string().into_bytes(),
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
async fn edit_then_accept_cannot_change_a_new_entrys_id() {
    let s = seeded().await;
    let made = post(&s, "/api/add", new_word("ねこ", "noun"), AIKO).await;
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": made.body["id"], "decision": "accept",
        "edits": {"dict": "ねご"}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 400, "{}", r.body);
    assert_eq!(
        r.body["error"],
        "that would change its id from noun:ねこ to noun:ねご; decline it and suggest it again under the new spelling"
    );
    let r = post(
        &s,
        "/api/admin/decide",
        json!({"id": made.body["id"], "decision": "accept",
        "edits": {"meaning": "cat (the animal)"}}),
        MARTIN,
    )
    .await;
    assert_eq!(r.status, 200, "{}", r.body);
}
