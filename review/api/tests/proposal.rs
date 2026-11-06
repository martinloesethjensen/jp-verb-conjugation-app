use review_api::data::DataFile;
use review_api::items::{extract, Kind};
use review_api::proposal::{build_change, check_furigana, fields, find_part, Input};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const LOCKED: &str = "can't be changed here; leave a note for Martin instead";

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

fn edits(value: Value) -> Map<String, Value> {
    value.as_object().unwrap().clone()
}

fn change(
    file: DataFile,
    kind: Kind,
    entry: &Value,
    id: &str,
    e: Value,
) -> Result<review_api::proposal::Change, String> {
    build_change(file, kind, entry, id, &edits(e), &form_ids())
}

#[test]
fn editing_a_verb_meaning_keeps_everything_else() {
    let tabe = verb("たべる");
    let c = change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"meaning": "to eat (a meal)"}),
    )
    .unwrap();
    let mut expected = tabe.clone();
    expected["meaning"] = json!("to eat (a meal)");
    assert_eq!(c.proposed, expected);
    assert_eq!(c.dropped_blanks, 0);
}

#[test]
fn locked_fields_are_refused() {
    let tabe = verb("たべる");
    for key in ["dict", "kanji", "id"] {
        let e = change(
            DataFile::Verbs,
            Kind::Entry,
            &tabe,
            "たべる",
            json!({key: "x"}),
        )
        .unwrap_err();
        assert_eq!(e, format!("{key} {LOCKED}"));
    }
    let word = doc(DataFile::Words)["words"][0].clone();
    let e = change(
        DataFile::Words,
        Kind::Entry,
        &word,
        "i-adjective:いい",
        json!({"class": "noun"}),
    )
    .unwrap_err();
    assert_eq!(e, format!("class {LOCKED}"));
    let example = tabe["examples"][0]["id"].as_str().unwrap();
    let e = change(
        DataFile::Verbs,
        Kind::Example,
        &tabe,
        example,
        json!({"id": "x"}),
    )
    .unwrap_err();
    assert_eq!(e, format!("id {LOCKED}"));
}

#[test]
fn a_field_not_in_the_table_is_refused() {
    let tsu = entry(DataFile::Counters, |c| c["id"] == "tsu");
    let e = change(
        DataFile::Counters,
        Kind::Entry,
        &tsu,
        "tsu",
        json!({"overrides": "x"}),
    )
    .unwrap_err();
    assert_eq!(e, format!("overrides {LOCKED}"));
}

#[test]
fn nothing_changed_and_empty_fields() {
    let tabe = verb("たべる");
    for same in ["to eat", "  to eat  "] {
        let e = change(
            DataFile::Verbs,
            Kind::Entry,
            &tabe,
            "たべる",
            json!({"meaning": same}),
        )
        .unwrap_err();
        assert_eq!(e, "nothing changed");
    }
    let e = change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"meaning": "  "}),
    )
    .unwrap_err();
    assert_eq!(e, "meaning can't be empty");

    let nin = entry(DataFile::Counters, |c| c["id"] == "nin");
    let c = change(
        DataFile::Counters,
        Kind::Pitfall,
        &nin,
        "pe3v3c",
        json!({"wrong": ""}),
    )
    .unwrap();
    assert!(c.proposed.get("wrong").is_none());
    assert!(c.proposed.get("heading").is_some());
}

#[test]
fn choices_are_checked() {
    let tabe = verb("たべる");
    let e = change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"jlpt": "N6"}),
    )
    .unwrap_err();
    assert!(e.contains("jlpt"), "{e}");
    let ok = change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"jlpt": "N4"}),
    )
    .unwrap();
    assert_eq!(ok.proposed["jlpt"], "N4");
    let tsu = entry(DataFile::Counters, |c| c["id"] == "tsu");
    let thing = tsu["things"][0]["id"].as_str().unwrap();
    let e = change(
        DataFile::Counters,
        Kind::Thing,
        &tsu,
        thing,
        json!({"fit": "best"}),
    )
    .unwrap_err();
    assert!(e.contains("fit"), "{e}");
}

#[test]
fn example_forms_are_checked() {
    let tabe = verb("たべる");
    let example = tabe["examples"][0]["id"].as_str().unwrap().to_string();
    let e = change(
        DataFile::Verbs,
        Kind::Example,
        &tabe,
        &example,
        json!({"form": "x"}),
    )
    .unwrap_err();
    assert_eq!(e, "there is no form called x");

    let shinu = verb("しぬ");
    let example = shinu["examples"][0]["id"].as_str().unwrap().to_string();
    let e = change(
        DataFile::Verbs,
        Kind::Example,
        &shinu,
        &example,
        json!({"form": "nasai"}),
    )
    .unwrap_err();
    assert_eq!(e, "しぬ has no nasai form");

    let other = tabe["examples"][0]["form"].as_str().unwrap();
    let form = if other == "te" { "masu_pos" } else { "te" };
    let ok = change(
        DataFile::Verbs,
        Kind::Example,
        &tabe,
        &example_of(&tabe),
        json!({"form": form}),
    )
    .unwrap();
    assert_eq!(ok.proposed["form"], form);
}

fn example_of(v: &Value) -> String {
    v["examples"][0]["id"].as_str().unwrap().to_string()
}

#[test]
fn particle_blanks_follow_the_sentence() {
    let point = entry(DataFile::Grammar, |g| g.to_string().contains("\"gbkyjx\""));
    let id = point["id"].as_str().unwrap().to_string();
    let part = find_part(&point, Kind::Example, "gbkyjx").unwrap().clone();
    assert_eq!(part["particle_blanks"].as_array().unwrap().len(), 2);
    let c = change(
        DataFile::Grammar,
        Kind::Example,
        &point,
        "gbkyjx",
        json!({"jp": "来月、日本に行こうと思っています。"}),
    )
    .unwrap();
    assert_eq!(c.dropped_blanks, 1, "{id}");
    let blanks = c.proposed["particle_blanks"].as_array().unwrap();
    assert_eq!(blanks.len(), 1);
    assert_eq!(blanks[0]["particle"], "と");

    let c = change(
        DataFile::Grammar,
        Kind::Example,
        &point,
        "gbkyjx",
        json!({"en": "Next month I plan to go to Japan, I think."}),
    )
    .unwrap();
    assert_eq!(c.dropped_blanks, 0);
    assert_eq!(c.proposed["particle_blanks"], part["particle_blanks"]);

    let c = change(
        DataFile::Grammar,
        Kind::Example,
        &point,
        "gbkyjx",
        json!({"jp": "全部ちがう。"}),
    )
    .unwrap();
    assert_eq!(c.dropped_blanks, 2);
    assert!(
        c.proposed.get("particle_blanks").is_none(),
        "an empty list is removed"
    );
}

#[test]
fn long_text_is_refused() {
    let tabe = verb("たべる");
    let e = change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"notes": "あ".repeat(2001)}),
    )
    .unwrap_err();
    assert_eq!(e, "notes is too long");
    assert!(change(
        DataFile::Verbs,
        Kind::Entry,
        &tabe,
        "たべる",
        json!({"notes": "あ".repeat(2000)})
    )
    .is_ok());
}

#[test]
fn a_part_that_isnt_there_is_refused() {
    let tabe = verb("たべる");
    let e = change(
        DataFile::Verbs,
        Kind::Example,
        &tabe,
        "nope",
        json!({"en": "x"}),
    )
    .unwrap_err();
    assert_eq!(e, "that isn't in the loaded data");
}

#[test]
fn the_field_table_covers_every_kind_in_the_data() {
    for file in [
        DataFile::Verbs,
        DataFile::Words,
        DataFile::Counters,
        DataFile::Grammar,
    ] {
        let bytes = std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap();
        let mut seen = BTreeSet::new();
        for row in extract(file, &bytes).unwrap() {
            if seen.insert(row.kind.as_str()) {
                assert!(
                    !fields(file, row.kind).is_empty(),
                    "{} {:?}",
                    file.name(),
                    row.kind
                );
            }
        }
    }
    let form = fields(DataFile::Verbs, Kind::Example)
        .iter()
        .find(|f| f.name == "form")
        .unwrap();
    assert_eq!(form.input, Input::Form);
}

#[test]
fn every_part_is_found_by_its_id() {
    for file in [DataFile::Verbs, DataFile::Counters, DataFile::Grammar] {
        let d = doc(file);
        let bytes = std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap();
        for row in extract(file, &bytes).unwrap() {
            if row.kind == Kind::Entry {
                continue;
            }
            let entry = d[file.name()]
                .as_array()
                .unwrap()
                .iter()
                .find(|e| {
                    e.get("id").and_then(Value::as_str).or(e["dict"].as_str())
                        == Some(&row.entry_id)
                })
                .unwrap();
            let part = find_part(entry, row.kind, &row.item_id).unwrap();
            assert_eq!(review_api::items::canonical_json(part), row.json);
        }
    }
}

#[test]
fn furigana_additions() {
    let known: BTreeMap<String, String> =
        serde_json::from_value(doc(DataFile::Furigana)["readings"].clone()).unwrap();
    assert!(!known.contains_key("鰐"));
    let add = |k: &str, v: &str| BTreeMap::from([(k.to_string(), v.to_string())]);
    assert_eq!(check_furigana(&add("鰐", "わに"), &known), Ok(()));
    assert_eq!(check_furigana(&add("鰐々", "わにわに"), &known), Ok(()));
    assert_eq!(
        check_furigana(&add("ねこ", "ねこ"), &known),
        Err("readings are for kanji: ねこ".into())
    );
    assert_eq!(
        check_furigana(&add("鰐", "ワニ"), &known),
        Err("a reading is written in hiragana: ワニ".into())
    );
    assert_eq!(
        check_furigana(&add("猫", "ねこ"), &known),
        Err("猫 already has a reading".into())
    );
    let many: BTreeMap<String, String> = (0..21)
        .map(|i| {
            (
                char::from_u32(0x4E00 + i).unwrap().to_string(),
                "あ".to_string(),
            )
        })
        .collect();
    assert!(check_furigana(&many, &BTreeMap::new()).is_err());
}
