use review_api::data::{check_entry, DataFile};
use review_api::items::{extract, Kind};
use review_api::proposal::{
    add_fields, add_parents, addable_targets, build_add, find_part, AddError, Input, NewItem, Taken,
};
use serde_json::{json, Map, Value};
use std::collections::BTreeSet;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const ALPHABET: &str = "abcdefghijkmnpqrstuvwxyz23456789";

fn doc(file: DataFile) -> Value {
    serde_json::from_slice(&std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap())
        .unwrap()
}

fn entry(file: DataFile, pick: impl Fn(&Value) -> bool) -> Value {
    doc(file)[file.name()]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| pick(e))
        .unwrap()
        .clone()
}

fn verb(dict: &str) -> Value {
    entry(DataFile::Verbs, |v| v["dict"] == dict)
}

fn form_ids() -> BTreeSet<String> {
    doc(DataFile::Forms)["forms"]
        .as_array()
        .unwrap()
        .iter()
        .map(|f| f["id"].as_str().unwrap().to_string())
        .collect()
}

fn fields(v: Value) -> Map<String, Value> {
    v.as_object().unwrap().clone()
}

/// Candidate ids "aaaaa2", "aaaaa3", … so every build is predictable.
fn counter() -> impl FnMut() -> String {
    let mut n = 0;
    move || {
        n += 1;
        format!("aaaaa{}", ALPHABET.chars().nth(23 + n % 9).unwrap())
    }
}

fn free(_: &str) -> Taken {
    Taken::Free
}

fn add(
    file: DataFile,
    kind: Kind,
    parent: Option<(&Value, Kind)>,
    f: Value,
    taken: &dyn Fn(&str) -> Taken,
) -> Result<NewItem, AddError> {
    build_add(
        file,
        kind,
        parent,
        &fields(f),
        &form_ids(),
        &mut counter(),
        taken,
    )
}

fn invalid(r: Result<NewItem, AddError>) -> String {
    match r {
        Err(AddError::Invalid(m)) => m,
        other => panic!("expected Invalid, got {other:?}"),
    }
}

fn is_stable_id(id: &str) -> bool {
    id.len() == 6 && id.chars().all(|c| ALPHABET.contains(c))
}

fn new_verb(extra: Value) -> Value {
    let mut v = json!({
        "dict": "はしる", "type": "u", "meaning": "to run", "description": "A u-verb.",
        "notes": "Often 走って.", "jlpt": "N4",
        "masu_pos": "はしります", "masu_neg": "はしりません", "masu_past": "はしりました",
        "masu_past_neg": "はしりませんでした", "te": "はしって", "short_pos": "はしる",
        "short_neg": "はしらない", "short_past": "はしった", "short_past_neg": "はしらなかった",
        "example_form": "te", "example_jp": "駅まではしって行きました。", "example_en": "I ran to the station."
    });
    for (k, val) in extra.as_object().unwrap() {
        v[k] = val.clone();
    }
    v
}

#[test]
fn a_new_example_on_a_verb() {
    let tabe = verb("たべる");
    let new = add(
        DataFile::Verbs,
        Kind::Example,
        Some((&tabe, Kind::Entry)),
        json!({"form": "te", "jp": "食べてから寝ます。", "en": "I eat, then sleep."}),
        &free,
    )
    .unwrap();
    assert!(is_stable_id(&new.item_id), "{}", new.item_id);
    assert_eq!(new.item["id"], new.item_id.as_str());
    assert_eq!(new.item["jp"], "食べてから寝ます。");
    let shinu = verb("しぬ");
    let e = invalid(add(
        DataFile::Verbs,
        Kind::Example,
        Some((&shinu, Kind::Entry)),
        json!({"form": "nasai", "jp": "a", "en": "b"}),
        &free,
    ));
    assert_eq!(e, "しぬ has no nasai form");
}

#[test]
fn a_new_verb_gets_its_kana_id_or_a_kanji_id() {
    let new = add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({})),
        &free,
    )
    .unwrap();
    assert_eq!(new.item_id, "はしる");
    assert!(new.item.get("id").is_none());

    let kiru_taken = |id: &str| {
        if id == "きる" {
            Taken::Loaded
        } else {
            Taken::Free
        }
    };
    let new = add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({"dict": "きる", "kanji": "斬る"})),
        &kiru_taken,
    )
    .unwrap();
    assert_eq!(new.item_id, "きる:斬る");
    assert_eq!(new.item["id"], "きる:斬る");

    let e = invalid(add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({"dict": "きる"})),
        &kiru_taken,
    ));
    assert_eq!(
        e,
        "きる is already a verb; add its kanji so the new one gets its own id"
    );

    let suggested = |id: &str| {
        if id == "はしる" {
            Taken::Suggested
        } else {
            Taken::Free
        }
    };
    match add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({})),
        &suggested,
    ) {
        Err(AddError::Conflict(m)) => {
            assert_eq!(
                m,
                "someone already suggested adding はしる; reply on their suggestion instead"
            )
        }
        other => panic!("{other:?}"),
    }
}

#[test]
fn a_new_verb_has_placeholders_and_its_first_example() {
    let new = add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({})),
        &free,
    )
    .unwrap();
    assert_eq!(new.item["label"], "U-verb");
    let forms: Vec<&String> = new.item["forms"].as_object().unwrap().keys().collect();
    assert_eq!(forms.len(), 9);
    assert_eq!(new.item["forms"]["te"], "はしって");
    let examples = new.item["examples"].as_array().unwrap();
    assert_eq!(examples.len(), 1);
    assert!(is_stable_id(examples[0]["id"].as_str().unwrap()));
    assert_eq!(examples[0]["form"], "te");
    assert!(check_entry(DataFile::Verbs, &new.item).is_ok());
    let e = invalid(add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({"example_form": "potential"})),
        &free,
    ));
    assert_eq!(e, "はしる has no potential form");
}

#[test]
fn a_new_grammar_point_has_one_usage_with_one_example() {
    let new = add(
        DataFile::Grammar,
        Kind::Entry,
        None,
        json!({"id": "te-shimau", "title": "てしまう", "summary": "Finished, or regretted.", "jlpt": "N4",
               "usage_heading": "Done completely", "usage_explanation": "The action is finished.",
               "example_jp": "全部食べてしまいました。", "example_en": "I ate it all."}),
        &free,
    )
    .unwrap();
    assert_eq!(new.item_id, "te-shimau");
    let usage = &new.item["usages"][0];
    let example = &usage["examples"][0];
    let ids = [
        usage["id"].as_str().unwrap(),
        example["id"].as_str().unwrap(),
    ];
    assert!(ids.iter().all(|id| is_stable_id(id)));
    assert_ne!(ids[0], ids[1]);
    assert!(check_entry(DataFile::Grammar, &new.item).is_ok());
}

#[test]
fn a_new_counter_uses_the_symbol_default() {
    let base = json!({"id": "wa", "counter": "羽", "reading": "わ", "meaning": "birds", "jlpt": "N3", "sound": "plain"});
    let new = add(DataFile::Counters, Kind::Entry, None, base.clone(), &free).unwrap();
    assert_eq!(new.item["symbol"], "number");
    assert!(check_entry(DataFile::Counters, &new.item).is_ok());
    let mut bad = base;
    bad["id"] = json!("Wa");
    assert_eq!(
        invalid(add(DataFile::Counters, Kind::Entry, None, bad, &free)),
        "id must be lowercase letters, digits and hyphens"
    );
}

#[test]
fn kana_fields_are_checked() {
    let e = invalid(add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        new_verb(json!({"dict": "走る"})),
        &free,
    ));
    assert_eq!(e, "dict must be written in kana");
}

#[test]
fn ids_skip_taken_candidates() {
    let tabe = verb("たべる");
    let mut seq = vec!["aaaaaa", "bbbbbb", "cccccc"]
        .into_iter()
        .map(String::from);
    let taken = |id: &str| {
        if id == "aaaaaa" || id == "bbbbbb" {
            Taken::Loaded
        } else {
            Taken::Free
        }
    };
    let new = build_add(
        DataFile::Verbs,
        Kind::Example,
        Some((&tabe, Kind::Entry)),
        &fields(json!({"form": "te", "jp": "a", "en": "b"})),
        &form_ids(),
        &mut || seq.next().unwrap_or_else(|| "aaaaaa".into()),
        &taken,
    )
    .unwrap();
    assert_eq!(new.item_id, "cccccc");
    let all_taken = |_: &str| Taken::Loaded;
    let e = invalid(build_add(
        DataFile::Verbs,
        Kind::Example,
        Some((&tabe, Kind::Entry)),
        &fields(json!({"form": "te", "jp": "a", "en": "b"})),
        &form_ids(),
        &mut counter(),
        &all_taken,
    ));
    assert_eq!(e, "couldn't pick a new id; try again");
}

#[test]
fn the_fingerprint_ignores_ids() {
    let f = new_verb(json!({}));
    let a = build_add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        &fields(f.clone()),
        &form_ids(),
        &mut counter(),
        &free,
    )
    .unwrap();
    let mut other = vec!["zzzzzz".to_string()].into_iter();
    let b = build_add(
        DataFile::Verbs,
        Kind::Entry,
        None,
        &fields(f),
        &form_ids(),
        &mut || other.next().unwrap(),
        &free,
    )
    .unwrap();
    assert_ne!(a.item, b.item, "different example ids");
    assert_eq!(a.fingerprint, b.fingerprint);
}

#[test]
fn parents_are_checked() {
    let point = doc(DataFile::Grammar)["grammar"][0].clone();
    let e = invalid(add(
        DataFile::Grammar,
        Kind::Example,
        Some((&point, Kind::Entry)),
        json!({"jp": "a", "en": "b"}),
        &free,
    ));
    assert_eq!(e, "example can't be added there");
    let e = invalid(add(
        DataFile::Words,
        Kind::Entry,
        Some((&point, Kind::Entry)),
        json!({}),
        &free,
    ));
    assert_eq!(e, "entry can't be added there");
    assert_eq!(
        add_parents(DataFile::Grammar, Kind::Example),
        [Kind::Usage, Kind::Pitfall]
    );
    assert_eq!(
        add_parents(DataFile::Counters, Kind::Example),
        [Kind::Entry, Kind::Pitfall]
    );
}

#[test]
fn unknown_and_missing_fields() {
    let e = invalid(add(
        DataFile::Words,
        Kind::Entry,
        None,
        json!({"class": "noun", "dict": "ねこ", "meaning": "cat", "jlpt": "N5", "forms": "x"}),
        &free,
    ));
    assert_eq!(
        e,
        "forms can't be changed here; leave a note for Martin instead"
    );
    let e = invalid(add(
        DataFile::Words,
        Kind::Entry,
        None,
        json!({"class": "noun", "dict": "ねこ", "jlpt": "N5"}),
        &free,
    ));
    assert_eq!(e, "meaning can't be empty");
}

/// A minimal valid field set for each addable target, from its field table.
fn minimal(file: DataFile, kind: Kind) -> Value {
    let mut v = Map::new();
    for f in add_fields(file, kind) {
        if f.optional || f.default.is_some() {
            continue;
        }
        let value = match (f.input, f.name) {
            (Input::Jlpt, _) => "N5".to_string(),
            (Input::Choice, _) => f.choices[0].to_string(),
            (Input::Form, _) => "te".to_string(),
            (Input::Slug, _) => "brand-new".to_string(),
            (Input::Kana, "dict") => "あたらしむ".to_string(),
            (Input::Kana, _) => "あたらしい".to_string(),
            _ => "text".to_string(),
        };
        v.insert(f.name.to_string(), Value::String(value));
    }
    if file == DataFile::Verbs && kind == Kind::Entry {
        v.insert("te".into(), json!("あたらしんで"));
        v.insert("example_form".into(), json!("te"));
    }
    Value::Object(v)
}

#[test]
fn every_addable_target_builds_against_real_data() {
    for (name, _) in addable_targets() {
        let (dataset, kind) = name.split_once('/').unwrap();
        let file = DataFile::parse_name(dataset).unwrap();
        let kind = Kind::parse(kind).unwrap();
        let bytes = std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap();
        let rows = extract(file, &bytes).unwrap();
        let parents = add_parents(file, kind);
        let parent = parents.first().map(|pk| {
            let row = rows.iter().find(|r| r.kind == *pk).unwrap();
            let entry = doc(file)[file.name()]
                .as_array()
                .unwrap()
                .iter()
                .find(|e| {
                    let id = match file {
                        DataFile::Verbs => e
                            .get("id")
                            .or(e.get("dict"))
                            .and_then(Value::as_str)
                            .map(str::to_string),
                        DataFile::Words => Some(format!(
                            "{}:{}",
                            e["class"].as_str().unwrap(),
                            e["dict"].as_str().unwrap()
                        )),
                        _ => e["id"].as_str().map(str::to_string),
                    };
                    id.as_deref() == Some(row.entry_id.as_str())
                })
                .unwrap()
                .clone();
            let value = if *pk == Kind::Entry {
                entry
            } else {
                find_part(&entry, *pk, &row.item_id).unwrap().clone()
            };
            (value, *pk)
        });
        let built = add(
            file,
            kind,
            parent.as_ref().map(|(v, k)| (v, *k)),
            minimal(file, kind),
            &free,
        );
        assert!(built.is_ok(), "{name}: {built:?}");
    }
}
