use review_api::data::{parse, DataFile};
use serde::Deserialize;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// Fixtures that break only a `pattern`. The Rust types mirror enums, required and unknown keys,
/// not patterns (update_data.py enforces those before anything is published).
const PATTERN_ONLY: &[&str] = &["grammar usage with a malformed id"];

/// Published files the review site does not serve, so it has no Rust type for them: kanji.json is
/// KanjiVG and KANJIDIC2 data, not content teachers review.
const NOT_SERVED: &[&str] = &["kanji"];

fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

#[derive(Deserialize)]
struct Fixture {
    name: String,
    dataset: String,
    doc: serde_json::Value,
}

fn fixtures() -> Vec<Fixture> {
    serde_json::from_slice(&std::fs::read(format!("{ROOT}/schema/fixtures/invalid.json")).unwrap())
        .unwrap()
}

#[test]
fn every_published_file_parses() {
    for file in DataFile::ALL {
        if let Err(e) = parse(file, &real(file)) {
            panic!("{}: {e}", file.file_name());
        }
    }
}

#[test]
fn the_shared_invalid_fixtures_are_rejected() {
    let fixtures = fixtures();
    assert!(fixtures.len() >= 10);
    for fixture in fixtures {
        if PATTERN_ONLY.contains(&fixture.name.as_str())
            || NOT_SERVED.contains(&fixture.dataset.as_str())
        {
            continue;
        }
        let file = DataFile::parse_name(&fixture.dataset).unwrap();
        assert!(
            parse(file, fixture.doc.to_string().as_bytes()).is_err(),
            "{}",
            fixture.name
        );
    }
}

#[test]
fn names_and_order() {
    assert_eq!(
        DataFile::ALL.map(|f| f.file_name()),
        [
            "furigana.json",
            "forms.json",
            "words.json",
            "counters.json",
            "grammar.json",
            "verbs.json"
        ]
    );
    assert_eq!(DataFile::parse_name("verbs"), Some(DataFile::Verbs));
    assert_eq!(DataFile::parse_name("verbs.json"), None);
    assert_eq!(DataFile::parse_name("../verbs"), None);
    assert!(DataFile::Counters.is_browsable() && !DataFile::Forms.is_browsable());
    assert!(!DataFile::Furigana.is_browsable());
}

#[test]
fn an_unknown_key_anywhere_is_rejected() {
    let mut doc: serde_json::Value = serde_json::from_slice(&real(DataFile::Counters)).unwrap();
    doc["counters"][0]["things"][0]["romaji"] = "x".into();
    assert!(parse(DataFile::Counters, doc.to_string().as_bytes()).is_err());
}

#[test]
fn a_missing_verb_kanji_is_like_null() {
    let mut doc: serde_json::Value = serde_json::from_slice(&real(DataFile::Verbs)).unwrap();
    doc["verbs"][0].as_object_mut().unwrap().remove("kanji");
    doc["verbs"][1]["kanji"] = serde_json::Value::Null;
    assert!(parse(DataFile::Verbs, doc.to_string().as_bytes()).is_ok());
}

#[test]
fn a_native_stamp_with_a_name_parses() {
    let mut doc: serde_json::Value = serde_json::from_slice(&real(DataFile::Counters)).unwrap();
    doc["counters"][0]["review"] = serde_json::json!({
        "by": "native", "on": "2026-11-07", "sha256": "a".repeat(64), "name": "Aiko"
    });
    assert!(parse(DataFile::Counters, doc.to_string().as_bytes()).is_ok());
}

#[test]
fn stamps_parse_on_verbs_examples_and_words() {
    let stamp = serde_json::json!({"by": "native", "on": "2026-11-08", "sha256": "a".repeat(64), "name": "Aiko"});
    let mut verbs: serde_json::Value = serde_json::from_slice(&real(DataFile::Verbs)).unwrap();
    verbs["verbs"][0]["review"] = stamp.clone();
    verbs["verbs"][0]["examples"][0]["review"] = stamp.clone();
    parse(DataFile::Verbs, verbs.to_string().as_bytes()).unwrap();
    let mut words: serde_json::Value = serde_json::from_slice(&real(DataFile::Words)).unwrap();
    words["words"][0]["review"] = stamp.clone();
    parse(DataFile::Words, words.to_string().as_bytes()).unwrap();
    words["words"][0]["review"]["extra"] = serde_json::json!(1);
    assert!(parse(DataFile::Words, words.to_string().as_bytes()).is_err());
}
