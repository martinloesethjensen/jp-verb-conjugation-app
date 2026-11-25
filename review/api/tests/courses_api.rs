mod support;

use serde_json::{json, Value};
use support::review::*;
use support::sqlite::SqliteStore;

async fn verb_ids(s: &SqliteStore, n: usize) -> Vec<Value> {
    let r = get(s, "/api/items?dataset=verbs", AIKO).await;
    r.body["items"]
        .as_array()
        .unwrap()
        .iter()
        .take(n)
        .map(|i| json!({"dataset": "verbs", "kind": "entry", "item_id": i["item_id"]}))
        .collect()
}

async fn create(s: &SqliteStore, who: &str) -> String {
    let r = post(
        s,
        "/api/course/create",
        json!({"start": "scratch", "title": "My course"}),
        who,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    r.body["id"].as_str().unwrap().to_string()
}

fn save_body(id: &str, items: Vec<Value>) -> Value {
    json!({"id": id, "title": "Renamed", "summary": "About",
           "lessons": [{"title": "One", "goal": "Eat", "note": "", "items": items}]})
}

async fn course(s: &SqliteStore, id: &str, who: &str) -> Response {
    get(s, &format!("/api/course?{}", q(&[("id", id)])), who).await
}

async fn search(s: &SqliteStore, query: &str, kind: &str) -> Response {
    let mut pairs = vec![("q", query)];
    if !kind.is_empty() {
        pairs.push(("kind", kind));
    }
    get(s, &format!("/api/course/search?{}", q(&pairs)), AIKO).await
}

fn titles(r: &Response) -> Vec<String> {
    r.body["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["title"].as_str().unwrap().to_string())
        .collect()
}

#[tokio::test(flavor = "current_thread")]
async fn only_the_author_saves() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let items = verb_ids(&s, 2).await;
    let r = post(&s, "/api/course/save", save_body(&id, items.clone()), AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["title"], "Renamed");
    assert_eq!(r.body["lessons"][0]["items"].as_array().unwrap().len(), 2);
    assert_eq!(r.body["lessons"][0]["items"][0]["loaded"], true);
    // Ben can't even see a draft; once it is in review he sees it and still can't save.
    let r = post(&s, "/api/course/save", save_body(&id, vec![]), BEN).await;
    assert_eq!(r.status, 404);
    s.execute(&format!(
        "UPDATE courses SET status = 'in_review' WHERE id = '{id}'"
    ));
    let r = post(&s, "/api/course/save", save_body(&id, vec![]), BEN).await;
    assert_eq!(r.status, 403, "{}", r.body);
    let r = post(&s, "/api/course/save", save_body(&id, vec![]), MARTIN).await;
    assert_eq!(
        r.status, 403,
        "the owner doesn't edit other people's courses"
    );
    // And the author can't once it isn't a draft.
    let r = post(&s, "/api/course/save", save_body(&id, vec![]), AIKO).await;
    assert_eq!(r.status, 409, "{}", r.body);
}

#[tokio::test(flavor = "current_thread")]
async fn an_item_that_is_not_loaded_is_refused() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let ghost = json!({"dataset": "verbs", "kind": "entry", "item_id": "no-such-verb"});
    let r = post(&s, "/api/course/save", save_body(&id, vec![ghost]), AIKO).await;
    assert_eq!(r.status, 400);
    assert!(r.body["error"]
        .as_str()
        .unwrap()
        .contains("not in the loaded data"));
    let r = course(&s, &id, AIKO).await;
    assert_eq!(
        r.body["lessons"].as_array().unwrap().len(),
        0,
        "nothing was saved"
    );
}

#[tokio::test(flavor = "current_thread")]
async fn save_checks_the_shape() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let item = verb_ids(&s, 1).await.remove(0);
    let twice = post(
        &s,
        "/api/course/save",
        save_body(&id, vec![item.clone(), item.clone()]),
        AIKO,
    )
    .await;
    assert_eq!(twice.status, 400, "no item twice in a lesson");
    let bad_kind = json!({"dataset": "verbs", "kind": "phrase", "item_id": "x"});
    assert_eq!(
        post(&s, "/api/course/save", save_body(&id, vec![bad_kind]), AIKO)
            .await
            .status,
        400
    );
    let many: Vec<Value> = (0..61)
        .map(|i| json!({"title": format!("L{i}"), "goal": "", "note": "", "items": []}))
        .collect();
    let r = post(
        &s,
        "/api/course/save",
        json!({"id": id, "title": "T", "summary": "", "lessons": many}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
    let long = "x".repeat(2001);
    let r = post(
        &s,
        "/api/course/save",
        json!({"id": id, "title": "T", "summary": long, "lessons": []}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
    let r = post(
        &s,
        "/api/course/save",
        json!({"id": id, "title": "  ", "summary": "", "lessons": []}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400, "a course needs a title");
    let r = post(
        &s,
        "/api/course/save",
        json!({"id": "zzzzzz", "title": "T", "summary": "", "lessons": []}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn lessons_round_trip_with_their_ids() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let items = verb_ids(&s, 1).await;
    let saved = post(&s, "/api/course/save", save_body(&id, items), AIKO).await;
    let mut body = json!({"id": id, "title": "T", "summary": "", "lessons": saved.body["lessons"]});
    body["lessons"][0]["title"] = json!("Changed");
    let r = post(&s, "/api/course/save", body, AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["lessons"][0]["id"], saved.body["lessons"][0]["id"]);
    assert_eq!(r.body["lessons"][0]["title"], "Changed");
}

#[tokio::test(flavor = "current_thread")]
async fn drafts_are_hidden_from_others_except_the_owner() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    assert_eq!(course(&s, &id, AIKO).await.status, 200);
    assert_eq!(course(&s, &id, MARTIN).await.status, 200);
    assert_eq!(course(&s, &id, BEN).await.status, 404);
    let ids = |r: &Response| -> Vec<String> {
        r.body["courses"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["id"].as_str().unwrap().to_string())
            .collect()
    };
    assert!(ids(&get(&s, "/api/courses", AIKO).await).contains(&id));
    assert!(ids(&get(&s, "/api/courses", MARTIN).await).contains(&id));
    assert!(!ids(&get(&s, "/api/courses", BEN).await).contains(&id));
    s.execute(&format!(
        "UPDATE courses SET status = 'in_review' WHERE id = '{id}'"
    ));
    assert_eq!(course(&s, &id, BEN).await.status, 200);
    assert!(ids(&get(&s, "/api/courses", BEN).await).contains(&id));
    assert_eq!(get(&s, "/api/course", AIKO).await.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn search_finds_by_english_kana_kanji_and_romaji() {
    let s = seeded().await;
    let english = search(&s, "to eat", "verb").await;
    assert_eq!(english.status, 200, "{}", english.body);
    assert!(
        titles(&english).iter().any(|t| t.contains("食べる")),
        "{:?}",
        titles(&english)
    );
    for query in ["たべる", "食べる", "taberu", "TABERU"] {
        let r = search(&s, query, "verb").await;
        assert!(
            titles(&r).iter().any(|t| t.contains("食べる")),
            "{query}: {:?}",
            titles(&r)
        );
    }
    let first = &search(&s, "taberu", "verb").await.body["items"][0];
    assert_eq!(first["course_kind"], "verb");
    assert_eq!(first["loaded"], true);
}

#[tokio::test(flavor = "current_thread")]
async fn search_filters_by_kind_and_limits() {
    let s = seeded().await;
    let all = search(&s, "taberu", "").await;
    let verbs = search(&s, "taberu", "verb").await;
    let grammar = search(&s, "taberu", "grammar").await;
    assert!(titles(&verbs).len() <= titles(&all).len());
    for item in verbs.body["items"].as_array().unwrap() {
        assert_eq!(item["course_kind"], "verb");
    }
    for item in grammar.body["items"].as_array().unwrap() {
        assert_eq!(item["course_kind"], "grammar");
    }
    let examples = search(&s, "a", "example").await;
    assert_eq!(
        examples.body["items"].as_array().unwrap().len(),
        40,
        "capped at 40"
    );
    assert_eq!(search(&s, "x", "nonsense").await.status, 400);
    assert_eq!(get(&s, "/api/course/search", AIKO).await.status, 400);
    assert_eq!(search(&s, "  ", "").await.body["items"], json!([]));
}

#[tokio::test(flavor = "current_thread")]
async fn a_textbook_start_makes_one_lesson_per_book_lesson() {
    let s = seeded().await;
    let r = post(
        &s,
        "/api/course/create",
        json!({"start": "textbook", "title": "Genki II", "book": "genki-2"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    let c = course(&s, r.body["id"].as_str().unwrap(), AIKO).await.body;
    assert_eq!(c["follows_book"], "genki-2");
    let lessons = c["lessons"].as_array().unwrap();
    assert_eq!(lessons.len(), 11, "lessons 13 to 23");
    assert_eq!(lessons[0]["textbook_lesson"], 13);
    assert_eq!(lessons[0]["title"], "Lesson 13");
    assert_eq!(lessons[10]["textbook_lesson"], 23);
    let one = post(
        &s,
        "/api/course/create",
        json!({"start": "textbook", "title": "G", "book": "genki-1"}),
        AIKO,
    )
    .await;
    let c = course(&s, one.body["id"].as_str().unwrap(), AIKO)
        .await
        .body;
    assert_eq!(c["lessons"].as_array().unwrap().len(), 12);
    assert_eq!(c["lessons"][0]["textbook_lesson"], 1);
    let r = post(
        &s,
        "/api/course/create",
        json!({"start": "textbook", "title": "G", "book": "nope"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
    let r = post(
        &s,
        "/api/course/create",
        json!({"start": "textbook", "title": "G"}),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn create_checks_its_input() {
    let s = seeded().await;
    for body in [
        json!({"start": "sideways", "title": "T"}),
        json!({"start": "scratch", "title": " "}),
        json!({"start": "scratch"}),
        json!({"start": "copy", "title": "T"}),
        json!({"start": "copy", "title": "T", "from": "zzzzzz"}),
    ] {
        let r = post(&s, "/api/course/create", body.clone(), AIKO).await;
        assert!(
            r.status == 400 || r.status == 404,
            "{body}: {} {}",
            r.status,
            r.body
        );
    }
}

#[tokio::test(flavor = "current_thread")]
async fn a_copy_needs_an_approved_course_and_credits_its_author() {
    let s = seeded().await;
    let source = create(&s, AIKO).await;
    let items = verb_ids(&s, 1).await;
    let r = post(
        &s,
        "/api/course/save",
        save_body(&source, items.clone()),
        AIKO,
    )
    .await;
    assert_eq!(r.status, 200);
    s.execute(&format!(
        "UPDATE courses SET status = 'in_review' WHERE id = '{source}'"
    ));
    async fn copy(s: &SqliteStore, from: &str, who: &str) -> Response {
        let body = json!({"start": "copy", "title": "Mine", "from": from});
        post(s, "/api/course/create", body, who).await
    }
    let r = copy(&s, &source, BEN).await;
    assert_eq!(
        r.status, 400,
        "an unapproved course can't be copied: {}",
        r.body
    );

    let verb = items[0]["item_id"].as_str().unwrap();
    let snapshot = json!({"id": source, "title": "Renamed", "summary": "About", "levels": ["N5"],
        "copied_from": null, "follows": null,
        "lessons": [{"id": "abcdef", "title": "One", "goal": "Eat", "note": "", "textbook_lesson": null,
                     "items": [{"kind": "verb", "id": verb}, {"kind": "verb", "id": "gone-verb"}]}]});
    s.execute(&format!(
        "UPDATE courses SET status = 'approved', approved_json = '{}' WHERE id = '{source}'",
        snapshot.to_string().replace('\'', "''")
    ));
    s.execute("UPDATE users SET public_name = 'Aiko S.', public_role = 'teacher' WHERE email = 'aiko@example.com'");
    let r = copy(&s, &source, BEN).await;
    assert_eq!(r.status, 201, "{}", r.body);
    let id = r.body["id"].as_str().unwrap();
    assert_ne!(id, source);
    assert_eq!(r.body["dropped"], 1, "the item that left the data");
    let c = course(&s, id, BEN).await.body;
    assert_eq!(c["status"], "draft");
    assert_eq!(c["title"], "Mine");
    assert_eq!(
        c["copied_from"],
        json!({"title": "Renamed", "author": {"name": "Aiko S.", "role": "teacher"}})
    );
    let lessons = c["lessons"].as_array().unwrap();
    assert_eq!(lessons.len(), 1);
    assert_ne!(lessons[0]["id"], "abcdef", "a copy gets new lesson ids");
    assert_eq!(
        lessons[0]["items"].as_array().unwrap().len(),
        1,
        "an item that left the data is dropped"
    );
    assert_eq!(lessons[0]["items"][0]["item_id"], verb);
}

#[tokio::test(flavor = "current_thread")]
async fn only_the_author_or_the_owner_deletes_a_never_exported_course() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let r = post(&s, "/api/course/delete", json!({"id": id}), BEN).await;
    assert_eq!(r.status, 404, "a draft is hidden from Ben");
    s.execute(&format!(
        "UPDATE courses SET status = 'in_review' WHERE id = '{id}'"
    ));
    assert_eq!(
        post(&s, "/api/course/delete", json!({"id": id}), BEN)
            .await
            .status,
        403
    );
    s.execute(&format!(
        "UPDATE courses SET status = 'draft' WHERE id = '{id}'"
    ));
    assert_eq!(
        post(&s, "/api/course/delete", json!({"id": id}), AIKO)
            .await
            .status,
        200
    );
    assert_eq!(course(&s, &id, AIKO).await.status, 404);

    let id = create(&s, AIKO).await;
    assert_eq!(
        post(&s, "/api/course/delete", json!({"id": id}), MARTIN)
            .await
            .status,
        200,
        "the owner may"
    );

    let id = create(&s, AIKO).await;
    s.execute(&format!(
        "UPDATE courses SET exported_at = '2026-11-20' WHERE id = '{id}'"
    ));
    let r = post(&s, "/api/course/delete", json!({"id": id}), AIKO).await;
    assert_eq!(r.status, 409, "{}", r.body);
    assert_eq!(course(&s, &id, AIKO).await.status, 200);
}

#[tokio::test(flavor = "current_thread")]
async fn books_come_from_the_loaded_grammar() {
    let s = seeded().await;
    let r = get(&s, "/api/books", AIKO).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let books = r.body["books"].as_array().unwrap();
    assert!(books
        .iter()
        .any(|b| b["id"] == "genki-2" && b["first_lesson"] == 13 && b["lessons"] == 23));
    assert!(books
        .iter()
        .any(|b| b["id"] == "genki-1" && b["first_lesson"] == 1));
}

#[tokio::test(flavor = "current_thread")]
async fn books_need_grammar_loaded() {
    let s = seeded().await;
    s.execute("UPDATE snapshot_files SET json = NULL WHERE name = 'grammar'");
    let r = get(&s, "/api/books", AIKO).await;
    assert_eq!(r.status, 409, "{}", r.body);
    assert!(r.body["error"]
        .as_str()
        .unwrap()
        .contains("grammar isn't loaded"));
}

#[tokio::test(flavor = "current_thread")]
async fn no_email_is_ever_sent_to_a_reviewer() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    s.execute("UPDATE users SET display_name = 'Aiko' WHERE email = 'aiko@example.com'");
    let approved = json!({"id": id, "title": "T", "summary": "", "levels": [], "lessons": []});
    s.execute(&format!(
        "UPDATE courses SET approved_json = '{approved}', approved_by = '{KEIKO}' WHERE id = '{id}'"
    ));
    // The owner's own courses and one by someone whose name is gone must not fall back to an email.
    let other = create(&s, BEN).await;
    s.execute(&format!(
        "UPDATE courses SET author = 'gone@example.com' WHERE id = '{other}'"
    ));
    s.execute(&format!(
        "UPDATE courses SET status = 'in_review' WHERE id IN ('{id}', '{other}')"
    ));
    for who in [AIKO, BEN, KEIKO] {
        for response in [
            get(&s, "/api/courses", who).await,
            course(&s, &id, who).await,
            course(&s, &other, who).await,
        ] {
            assert_eq!(response.status, 200, "{}", response.body);
            let text = response.body.to_string();
            assert!(!text.contains('@'), "{who} saw an email: {text}");
        }
    }
    let c = course(&s, &id, BEN).await.body;
    assert_eq!(c["author_name"], "Aiko");
    assert_eq!(c["approved_by_name"], "Keiko");
    assert_eq!(c["mine"], false);
    assert_eq!(course(&s, &other, BEN).await.body["author_name"], "");
}

#[tokio::test(flavor = "current_thread")]
async fn an_approved_course_being_edited_can_still_be_copied() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let approved =
        json!({"id": id, "title": "Shipped", "summary": "", "levels": [], "lessons": []});
    s.execute(&format!(
        "UPDATE courses SET status = 'draft', approved_json = '{approved}' WHERE id = '{id}'"
    ));
    assert_eq!(
        course(&s, &id, BEN).await.status,
        404,
        "its draft stays hidden"
    );
    let r = post(
        &s,
        "/api/course/create",
        json!({"start": "copy", "title": "", "from": id}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["title"], "Shipped");
    assert_eq!(r.body["copied_from"]["title"], "Shipped");
}

#[tokio::test(flavor = "current_thread")]
async fn a_copy_keeps_the_textbook_link_and_credits_a_missing_author_as_native() {
    let s = seeded().await;
    let id = create(&s, AIKO).await;
    let snapshot = json!({"id": id, "title": "Genki II", "summary": "", "levels": [],
        "follows": {"book": "genki-2"},
        "lessons": [{"id": "abcdef", "title": "L13", "goal": "g", "note": "", "textbook_lesson": 13, "items": []},
                    {"id": "ghijkl", "title": "L14", "goal": "g", "note": "", "textbook_lesson": 14, "items": []}]});
    s.execute(&format!(
        "UPDATE courses SET status = 'approved', approved_json = '{snapshot}', author = 'gone@example.com' WHERE id = '{id}'"
    ));
    let r = post(
        &s,
        "/api/course/create",
        json!({"start": "copy", "title": "Mine", "from": id}),
        BEN,
    )
    .await;
    assert_eq!(r.status, 201, "{}", r.body);
    assert_eq!(r.body["dropped"], 0);
    assert_eq!(r.body["follows_book"], "genki-2");
    assert_eq!(r.body["lessons"][0]["textbook_lesson"], 13);
    assert_eq!(r.body["lessons"][1]["textbook_lesson"], 14);
    assert_eq!(r.body["copied_from"]["author"], json!({"role": "native"}));
}
