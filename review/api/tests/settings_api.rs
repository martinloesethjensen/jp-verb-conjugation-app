mod support;

use serde_json::{json, Value};
use support::review::*;

async fn settings(s: &support::sqlite::SqliteStore, who: &str) -> Value {
    let r = get(s, "/api/settings", who).await;
    assert_eq!(r.status, 200, "{}", r.body);
    r.body
}

async fn change(
    s: &support::sqlite::SqliteStore,
    who: &str,
    body: Value,
) -> support::review::Response {
    post(s, "/api/settings", body, who).await
}

#[tokio::test(flavor = "current_thread")]
async fn a_new_person_gets_the_defaults() {
    let s = seeded().await;
    assert_eq!(
        settings(&s, AIKO).await,
        json!({"welcome_seen_at": null, "tour_seen_at": null, "tips_on": true,
               "tips_dismissed": [], "shortcuts_on": true})
    );
}

#[tokio::test(flavor = "current_thread")]
async fn switches_save_one_at_a_time() {
    let s = seeded().await;
    let r = change(&s, AIKO, json!({"shortcuts_on": false})).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(
        (r.body["shortcuts_on"].clone(), r.body["tips_on"].clone()),
        (json!(false), json!(true))
    );
    let r = change(&s, AIKO, json!({"tips_on": false})).await;
    assert_eq!(
        (r.body["shortcuts_on"].clone(), r.body["tips_on"].clone()),
        (json!(false), json!(false))
    );
    assert_eq!(settings(&s, AIKO).await["shortcuts_on"], false);
}

#[tokio::test(flavor = "current_thread")]
async fn the_tour_moves_from_welcome_to_done_and_resets() {
    let s = seeded().await;
    let r = change(&s, AIKO, json!({"tour": "welcomed"})).await;
    assert!(r.body["welcome_seen_at"].is_string(), "{}", r.body);
    assert!(r.body["tour_seen_at"].is_null());
    let r = change(&s, AIKO, json!({"tour": "done"})).await;
    assert!(r.body["tour_seen_at"].is_string());
    let r = change(&s, AIKO, json!({"tour": "reset"})).await;
    assert!(
        r.body["welcome_seen_at"].is_null() && r.body["tour_seen_at"].is_null(),
        "{}",
        r.body
    );
    let r = change(&s, BEN, json!({"tour": "done"})).await;
    assert!(
        r.body["welcome_seen_at"].is_string() && r.body["tour_seen_at"].is_string(),
        "{}",
        r.body
    );
    assert_eq!(change(&s, AIKO, json!({"tour": "later"})).await.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn tips_are_dismissed_once_and_unknown_ones_refused() {
    let s = seeded().await;
    for _ in 0..2 {
        let r = change(&s, AIKO, json!({"dismiss_tip": "inbox"})).await;
        assert_eq!(r.status, 200, "{}", r.body);
    }
    assert_eq!(settings(&s, AIKO).await["tips_dismissed"], json!(["inbox"]));
    assert_eq!(
        change(&s, AIKO, json!({"dismiss_tip": "nope"}))
            .await
            .status,
        400
    );
    assert_eq!(change(&s, AIKO, json!({})).await.status, 400);
    assert_eq!(change(&s, AIKO, json!({"colour": "red"})).await.status, 400);
}

#[tokio::test(flavor = "current_thread")]
async fn settings_are_per_person() {
    let s = seeded().await;
    change(
        &s,
        AIKO,
        json!({"shortcuts_on": false, "dismiss_tip": "thread"}),
    )
    .await;
    let ben = settings(&s, BEN).await;
    assert_eq!(ben["shortcuts_on"], true);
    assert_eq!(ben["tips_dismissed"], json!([]));
}
