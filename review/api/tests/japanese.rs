use review_api::japanese::{edited_fields, is_japanese_field, japanese_only, JAPANESE_FIELDS};
use serde_json::{json, Value};
use std::collections::BTreeSet;

fn example() -> Value {
    json!({"id": "taberu-1", "form": "masu_pos", "jp": "パンを食べます。", "en": "I eat bread.",
           "particle_blanks": [{"at": 3, "particle": "を"}]})
}

fn with(changes: Value) -> Value {
    let mut item = example();
    for (k, v) in changes.as_object().unwrap() {
        item[k] = v.clone();
    }
    item
}

#[test]
fn a_change_to_the_japanese_alone_qualifies() {
    assert!(japanese_only(
        &with(json!({"jp": "パンを食べる。"})),
        &example()
    ));
}

#[test]
fn a_change_that_also_touches_english_or_an_id_does_not() {
    let both = with(json!({"jp": "パンを食べる。", "en": "I eat."}));
    assert!(!japanese_only(&both, &example()));
    assert!(!japanese_only(&with(json!({"en": "I eat."})), &example()));
    assert!(!japanese_only(&with(json!({"id": "taberu-9"})), &example()));
    assert!(!japanese_only(
        &with(json!({"form": "short_pos"})),
        &example()
    ));
}

#[test]
fn dropped_particle_blanks_follow_the_japanese_edit() {
    let mut proposed = with(json!({"jp": "食べます。"}));
    proposed.as_object_mut().unwrap().remove("particle_blanks");
    assert_eq!(
        edited_fields(&proposed, &example()),
        BTreeSet::from(["jp".to_string()])
    );
    assert!(japanese_only(&proposed, &example()));
    let mut blanks_only = example();
    blanks_only
        .as_object_mut()
        .unwrap()
        .remove("particle_blanks");
    assert!(
        !japanese_only(&blanks_only, &example()),
        "nothing a reviewer edits changed"
    );
}

#[test]
fn nothing_changed_or_nothing_loaded_does_not_qualify() {
    assert!(!japanese_only(&example(), &example()));
    assert!(!japanese_only(&with(json!({"jp": "x"})), &Value::Null));
    assert!(!japanese_only(&Value::Null, &example()));
}

#[test]
fn a_removed_optional_japanese_field_counts_as_edited() {
    let current = json!({"meaning": "to eat", "kanji": "食"});
    let proposed = json!({"meaning": "to eat"});
    assert!(japanese_only(&proposed, &current));
}

#[test]
fn the_list_matches_the_web() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../web/src/lib/labels.ts");
    let labels = std::fs::read_to_string(path).unwrap();
    let start = labels
        .find("JAPANESE_FIELDS = new Set([")
        .expect("the web's list")
        + 27;
    let end = start + labels[start..].find("]);").unwrap();
    let web: BTreeSet<&str> = labels[start..end]
        .split(',')
        .map(|s| s.trim().trim_matches('\''))
        .filter(|s| !s.is_empty())
        .collect();
    let worker: BTreeSet<&str> = JAPANESE_FIELDS.iter().copied().collect();
    assert_eq!(worker, web);
    assert!(is_japanese_field("kana") && !is_japanese_field("en"));
}
