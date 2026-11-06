use review_api::data::DataFile;
use review_api::items::{canonical_json, content_hash, entry_hash, extract, Kind};
use serde_json::{json, Value};
use std::collections::HashSet;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

fn doc(file: DataFile) -> Value {
    serde_json::from_slice(&real(file)).unwrap()
}

/// Objects inside entries whose "id" looks like a stable id (6 characters from the id alphabet).
/// Grammar contrasts' own ids name other grammar points (slugs), so they don't match.
fn stable_id_objects(file: DataFile) -> usize {
    fn is_stable(id: &str) -> bool {
        id.len() == 6
            && id
                .chars()
                .all(|c| matches!(c, 'a'..='k' | 'm'..='n' | 'p'..='z' | '2'..='9'))
    }
    fn walk(v: &Value, top: bool) -> usize {
        match v {
            Value::Object(m) => {
                let me = !top && m.get("id").and_then(Value::as_str).is_some_and(is_stable);
                usize::from(me) + m.values().map(|x| walk(x, false)).sum::<usize>()
            }
            Value::Array(a) => a.iter().map(|x| walk(x, false)).sum(),
            _ => 0,
        }
    }
    let d = doc(file);
    let key = file.name();
    d[key]
        .as_array()
        .unwrap()
        .iter()
        .map(|entry| walk(entry, true))
        .sum()
}

#[test]
fn every_entry_and_stable_id_slot_becomes_a_row() {
    for file in [
        DataFile::Verbs,
        DataFile::Words,
        DataFile::Counters,
        DataFile::Grammar,
    ] {
        let rows = extract(file, &real(file)).unwrap();
        let entries = doc(file)[file.name()].as_array().unwrap().len();
        assert_eq!(
            rows.iter().filter(|r| r.kind == Kind::Entry).count(),
            entries,
            "{}",
            file.name()
        );
        assert_eq!(
            rows.iter().filter(|r| r.kind != Kind::Entry).count(),
            stable_id_objects(file),
            "{}",
            file.name()
        );
        assert!(
            rows.windows(2).all(|w| w[0].position < w[1].position),
            "{}: positions",
            file.name()
        );
    }
}

#[test]
fn sub_item_counts_match_pythons_id_slots() {
    // len(stable_ids.id_slots(name, doc)) on today's data, so a missed or extra slot kind shows up.
    for (file, slots) in [
        (DataFile::Verbs, 690),
        (DataFile::Counters, 325),
        (DataFile::Grammar, 412),
    ] {
        let rows = extract(file, &real(file)).unwrap();
        assert_eq!(
            rows.iter().filter(|r| r.kind != Kind::Entry).count(),
            slots,
            "{}",
            file.name()
        );
    }
}

#[test]
fn ids_follow_the_app() {
    let verbs = extract(DataFile::Verbs, &real(DataFile::Verbs)).unwrap();
    let entry_ids: HashSet<_> = verbs
        .iter()
        .filter(|r| r.kind == Kind::Entry)
        .map(|r| r.item_id.as_str())
        .collect();
    assert!(entry_ids.contains("きる:切る") && entry_ids.contains("たべる"));
    let words = extract(DataFile::Words, &real(DataFile::Words)).unwrap();
    assert_eq!(words[0].item_id, "i-adjective:いい");
}

#[test]
fn titles_parents_and_kinds() {
    let verbs = extract(DataFile::Verbs, &real(DataFile::Verbs)).unwrap();
    let taberu = verbs
        .iter()
        .find(|r| r.kind == Kind::Entry && r.item_id == "たべる")
        .unwrap();
    assert_eq!(
        (
            taberu.title.as_str(),
            taberu.subtitle.as_str(),
            taberu.jlpt.as_deref()
        ),
        ("たべる (食べる)", "to eat", Some("N5"))
    );
    let verbs_doc = doc(DataFile::Verbs);
    let first_example = &verbs_doc["verbs"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["dict"] == "たべる")
        .unwrap()["examples"][0];
    let row = verbs
        .iter()
        .find(|r| r.item_id == first_example["id"])
        .unwrap();
    assert_eq!(row.kind, Kind::Example);
    assert_eq!(row.title, first_example["jp"]);
    assert_eq!(row.subtitle, first_example["en"]);
    assert_eq!(
        (row.parent_id.as_deref(), row.entry_id.as_str()),
        (Some("たべる"), "たべる")
    );
    assert_eq!(
        serde_json::from_str::<Value>(&row.json).unwrap(),
        *first_example
    );
    assert_eq!(
        verbs
            .iter()
            .filter(|r| r.entry_id == "たべる" && r.kind == Kind::Collocation)
            .count(),
        3
    );

    let counters = extract(DataFile::Counters, &real(DataFile::Counters)).unwrap();
    let hon = counters
        .iter()
        .find(|r| r.kind == Kind::Entry && r.item_id == "hon")
        .unwrap();
    assert_eq!(hon.title, "本 (ほん)");

    // A pitfall example's parent is its pitfall; a contrast example's parent is the grammar point.
    let grammar = extract(DataFile::Grammar, &real(DataFile::Grammar)).unwrap();
    let g = doc(DataFile::Grammar);
    for point in g["grammar"].as_array().unwrap() {
        for pitfall in point["pitfalls"].as_array().unwrap() {
            for ex in pitfall["examples"].as_array().into_iter().flatten() {
                let row = grammar.iter().find(|r| r.item_id == ex["id"]).unwrap();
                assert_eq!(row.parent_id.as_deref(), pitfall["id"].as_str());
            }
        }
        for contrast in point["contrasts"].as_array().into_iter().flatten() {
            for ex in contrast["examples"].as_array().unwrap() {
                let row = grammar.iter().find(|r| r.item_id == ex["id"]).unwrap();
                assert_eq!(row.parent_id.as_deref(), point["id"].as_str());
            }
        }
    }
}

#[test]
fn ids_are_unique_per_kind_within_a_dataset() {
    for file in [
        DataFile::Verbs,
        DataFile::Words,
        DataFile::Counters,
        DataFile::Grammar,
    ] {
        let rows = extract(file, &real(file)).unwrap();
        let unique: HashSet<_> = rows.iter().map(|r| (r.kind, r.item_id.clone())).collect();
        assert_eq!(unique.len(), rows.len(), "{}", file.name());
    }
}

#[test]
fn the_canonical_hash_matches_pythons() {
    let v = json!({"b": "食べる", "a": [1, {"d": null, "c": true}], "e": "tab\there \"q\" é/"});
    assert_eq!(
        canonical_json(&v),
        r#"{"a":[1,{"c":true,"d":null}],"b":"食べる","e":"tab\there \"q\" é/"}"#
    );
    // hashlib.sha256(json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode())
    assert_eq!(
        content_hash(&v),
        "a3fb9eb6dbd996bf350939af5c1138e9146ef766cb49c3a6d2c8dea4b167f1be"
    );
}

#[test]
fn reference_files_have_no_rows_and_bad_files_fail() {
    assert!(extract(DataFile::Furigana, &real(DataFile::Furigana))
        .unwrap()
        .is_empty());
    assert!(extract(DataFile::Forms, &real(DataFile::Forms))
        .unwrap()
        .is_empty());
    assert!(extract(DataFile::Verbs, b"{}").is_err());
    assert!(extract(DataFile::Furigana, b"[]").is_err());
}

#[test]
fn entry_hashes_match_pythons_review_hash() {
    // update_data.review_hash(entry, COUNTER_GENERATED) and review_hash(point) on these objects.
    let counter = json!({"id": "hon", "counter": "本", "meaning": "long things", "readings": {"1": ["いっぽん"]},
        "changed": ["1"], "distractors": {"5": ["ごぼん"]}, "review": {"by": "owner", "on": "2026-11-01", "sha256": "x"},
        "things": [{"id": "abcdef", "word": "鉛筆"}]});
    assert_eq!(
        entry_hash(DataFile::Counters, &counter),
        "ba0886a564d3ba1e93d05dc2853fc32780872fbe51a99c6f0e317b037f8cf84a"
    );
    let point = json!({"id": "node", "title": "〜ので", "review": {"by": "teacher", "on": "2026-11-01", "sha256": "y"},
        "usages": [{"id": "bcdefg", "heading": "h"}]});
    assert_eq!(
        entry_hash(DataFile::Grammar, &point),
        "dcdd3cfda031b902c8a427e2f2b62a8a24e387bf3aa092d0dc8999782035f59e"
    );
}

#[test]
fn a_verb_or_word_hash_covers_only_its_authored_fields() {
    // Generated forms, examples and collocations (which carry their own hashes) don't change it;
    // the meaning does. A review stamp never does.
    let verbs = doc(DataFile::Verbs);
    let verb = &verbs["verbs"][0];
    let base = entry_hash(DataFile::Verbs, verb);
    let mut changed = verb.clone();
    changed["forms"]["te"] = json!("x");
    changed["examples"] = json!([]);
    changed["collocations"] = json!([]);
    changed["review"] = json!({"by": "owner", "on": "2026-11-01", "sha256": "z"});
    assert_eq!(entry_hash(DataFile::Verbs, &changed), base);
    changed["meaning"] = json!("something else");
    assert_ne!(entry_hash(DataFile::Verbs, &changed), base);
    let words = doc(DataFile::Words);
    let mut word = words["words"][0].clone();
    let base = entry_hash(DataFile::Words, &word);
    word["forms"]["te"] = json!("x");
    assert_eq!(entry_hash(DataFile::Words, &word), base);
}

#[test]
fn entry_rows_carry_the_entry_hash_and_sub_items_their_own() {
    for file in [DataFile::Verbs, DataFile::Counters, DataFile::Grammar] {
        let rows = extract(file, &real(file)).unwrap();
        for row in &rows {
            let value: Value = serde_json::from_str(&row.json).unwrap();
            let expected = if row.kind == Kind::Entry {
                entry_hash(file, &value)
            } else {
                content_hash(&value)
            };
            assert_eq!(
                row.content_hash,
                expected,
                "{} {}",
                file.name(),
                row.item_id
            );
        }
    }
}
