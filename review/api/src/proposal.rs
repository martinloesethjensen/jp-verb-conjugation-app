//! Building a reviewer's proposed item from the fields they edited, and checking it. Pure, so every rule
//! is tested natively.
//!
//! A reviewer edits only the fields in `fields`; everything else is carried over from the current item.
//! Ids (and the spellings that ids are built from) are frozen: those keys are `locked`, and a reviewer
//! who thinks one is wrong leaves a note instead.

use crate::data::{
    check_entry, Collocation, CounterExample, CounterPitfall, CounterThing, DataFile,
    GrammarExample, GrammarPitfall, Usage, VerbExample,
};
use crate::items::Kind;
use serde::Serialize;
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Input {
    /// One line.
    Text,
    /// Several lines.
    Long,
    /// N5–N1.
    Jlpt,
    /// One of `choices`.
    Choice,
    /// A form id from `forms.json`.
    Form,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Field {
    pub name: &'static str,
    pub input: Input,
    pub optional: bool,
    pub choices: &'static [&'static str],
}

/// The most characters in one field, comment or reply.
pub const MAX_TEXT: usize = 2000;
/// The most furigana readings one suggestion may add.
pub const MAX_READINGS: usize = 20;

const JLPT: &[&str] = &["N5", "N4", "N3", "N2", "N1"];
const VERB_TYPES: &[&str] = &["ru", "u", "irr."];
const VERB_LABELS: &[&str] = &["Ru-verb", "U-verb", "Irregular"];
const TE_GROUPS: &[&str] = &["ide", "ite", "nde", "shite", "tte"];
const FITS: &[&str] = &["primary", "casual", "acceptable"];

const fn field(name: &'static str, input: Input) -> Field {
    Field {
        name,
        input,
        optional: false,
        choices: match input {
            Input::Jlpt => JLPT,
            _ => &[],
        },
    }
}

const fn optional(f: Field) -> Field {
    Field {
        optional: true,
        ..f
    }
}

const fn choice(name: &'static str, choices: &'static [&'static str]) -> Field {
    Field {
        name,
        input: Input::Choice,
        optional: false,
        choices,
    }
}

const JP_EN: &[Field] = &[field("jp", Input::Text), field("en", Input::Text)];
const PITFALL: &[Field] = &[
    field("heading", Input::Text),
    field("explanation", Input::Long),
    optional(field("wrong", Input::Text)),
];

/// The fields a reviewer may edit on a target. Empty: the target can't be edited.
const VERB_ENTRY: &[Field] = &[
    choice("type", VERB_TYPES),
    choice("label", VERB_LABELS),
    field("meaning", Input::Text),
    field("description", Input::Long),
    field("notes", Input::Long),
    field("jlpt", Input::Jlpt),
    optional(choice("teGroup", TE_GROUPS)),
];
const VERB_EXAMPLE: &[Field] = &[
    field("form", Input::Form),
    field("jp", Input::Text),
    field("en", Input::Text),
];
const WORD_ENTRY: &[Field] = &[
    field("meaning", Input::Text),
    field("jlpt", Input::Jlpt),
    optional(field("kanji", Input::Text)),
];
const COUNTER_ENTRY: &[Field] = &[
    field("counter", Input::Text),
    field("reading", Input::Text),
    field("meaning", Input::Text),
    field("jlpt", Input::Jlpt),
];
const COUNTER_THING: &[Field] = &[
    field("word", Input::Text),
    field("kana", Input::Text),
    field("meaning", Input::Text),
    choice("fit", FITS),
];
const GRAMMAR_ENTRY: &[Field] = &[
    field("title", Input::Text),
    field("summary", Input::Long),
    field("jlpt", Input::Jlpt),
];
const GRAMMAR_USAGE: &[Field] = &[
    field("heading", Input::Text),
    field("explanation", Input::Long),
    optional(field("jlpt", Input::Jlpt)),
];

pub fn fields(file: DataFile, kind: Kind) -> &'static [Field] {
    match (file, kind) {
        (DataFile::Verbs, Kind::Entry) => VERB_ENTRY,
        (DataFile::Verbs, Kind::Example) => VERB_EXAMPLE,
        (DataFile::Verbs, Kind::Collocation) => JP_EN,
        (DataFile::Words, Kind::Entry) => WORD_ENTRY,
        (DataFile::Counters, Kind::Entry) => COUNTER_ENTRY,
        (DataFile::Counters, Kind::Thing) => COUNTER_THING,
        (DataFile::Counters, Kind::Example) => JP_EN,
        (DataFile::Counters, Kind::Pitfall) => PITFALL,
        (DataFile::Grammar, Kind::Entry) => GRAMMAR_ENTRY,
        (DataFile::Grammar, Kind::Usage) => GRAMMAR_USAGE,
        (DataFile::Grammar, Kind::Example) => JP_EN,
        (DataFile::Grammar, Kind::Pitfall) => PITFALL,
        _ => &[],
    }
}

/// Keys that are frozen because ids are built from them.
pub fn locked(file: DataFile, kind: Kind) -> &'static [&'static str] {
    match (file, kind) {
        (DataFile::Verbs, Kind::Entry) => &["dict", "kanji", "id"],
        (DataFile::Words, Kind::Entry) => &["class", "dict"],
        _ => &["id"],
    }
}

/// Every `(dataset, kind)` a reviewer can edit, as `"verbs/entry"`.
pub fn editable_targets() -> Vec<(String, &'static [Field])> {
    let mut out = Vec::new();
    for file in [
        DataFile::Verbs,
        DataFile::Words,
        DataFile::Counters,
        DataFile::Grammar,
    ] {
        for kind in [
            Kind::Entry,
            Kind::Example,
            Kind::Collocation,
            Kind::Usage,
            Kind::Pitfall,
            Kind::Thing,
        ] {
            let f = fields(file, kind);
            if !f.is_empty() {
                out.push((format!("{}/{}", file.name(), kind.as_str()), f));
            }
        }
    }
    out
}

/// The lists inside an entry (and inside its usages, pitfalls and contrasts) where parts of `kind` sit,
/// following `items::entry_rows`.
fn lists_of(entry: &Value, kind: Kind) -> Vec<&Value> {
    let key = match kind {
        Kind::Entry => return Vec::new(),
        Kind::Example => "examples",
        Kind::Collocation => "collocations",
        Kind::Usage => "usages",
        Kind::Pitfall => "pitfalls",
        Kind::Thing => "things",
    };
    let mut out: Vec<&Value> = entry.get(key).into_iter().collect();
    if kind == Kind::Example {
        for section in ["usages", "pitfalls", "contrasts"] {
            for owner in entry
                .get(section)
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                out.extend(owner.get("examples"));
            }
        }
    }
    out
}

/// The part of `kind` with the stable `id` inside `entry`.
pub fn find_part<'a>(entry: &'a Value, kind: Kind, id: &str) -> Option<&'a Value> {
    lists_of(entry, kind)
        .into_iter()
        .filter_map(Value::as_array)
        .flatten()
        .find(|part| part.get("id").and_then(Value::as_str) == Some(id))
}

#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    /// The whole proposed item: the entry, or the part.
    pub proposed: Value,
    /// Particle blanks that no longer sit at their offset and were dropped.
    pub dropped_blanks: u32,
}

pub fn locked_message(key: &str) -> String {
    format!("{key} can't be changed here; leave a note for Martin instead")
}

/// The proposed item for `item_id` (the entry itself for `Kind::Entry`) with `edits` applied, checked.
/// The error is the message a reviewer sees.
pub fn build_change(
    file: DataFile,
    kind: Kind,
    entry: &Value,
    item_id: &str,
    edits: &Map<String, Value>,
    form_ids: &BTreeSet<String>,
) -> Result<Change, String> {
    let current = if kind == Kind::Entry {
        entry
    } else {
        find_part(entry, kind, item_id).ok_or("that isn't in the loaded data")?
    };
    let mut proposed = current
        .as_object()
        .cloned()
        .ok_or("that isn't in the loaded data")?;
    let table = fields(file, kind);
    for (key, value) in edits {
        let field = table
            .iter()
            .find(|f| f.name == key)
            .filter(|_| !locked(file, kind).contains(&key.as_str()))
            .ok_or_else(|| locked_message(key))?;
        let text = match value {
            Value::String(text) => text.trim(),
            Value::Null => "",
            _ => return Err(format!("{key} must be text")),
        };
        if text.chars().count() > MAX_TEXT {
            return Err(format!("{key} is too long"));
        }
        if text.is_empty() {
            if !field.optional {
                return Err(format!("{key} can't be empty"));
            }
            proposed.remove(key);
            continue;
        }
        if matches!(field.input, Input::Choice | Input::Jlpt) && !field.choices.contains(&text) {
            return Err(format!(
                "{key} must be one of: {}",
                field.choices.join(", ")
            ));
        }
        proposed.insert(key.clone(), Value::String(text.to_string()));
    }
    let mut proposed = Value::Object(proposed);
    if &proposed == current {
        return Err("nothing changed".into());
    }
    if file == DataFile::Verbs && kind == Kind::Example && proposed["form"] != current["form"] {
        let form = proposed["form"].as_str().unwrap_or_default();
        if !form_ids.contains(form) {
            return Err(format!("there is no form called {form}"));
        }
        let has = entry["forms"][form]
            .as_str()
            .is_some_and(|value| !value.is_empty());
        if !has {
            let dict = entry["dict"].as_str().unwrap_or_default();
            return Err(format!("{dict} has no {form} form"));
        }
    }
    let dropped_blanks = keep_matching_blanks(&mut proposed, current);
    let schema = |e: String| format!("doesn't fit the data schema: {e}");
    match kind {
        Kind::Entry => check_entry(file, &proposed).map_err(schema)?,
        _ => check_part(file, kind, &proposed).map_err(schema)?,
    }
    Ok(Change {
        proposed,
        dropped_blanks,
    })
}

/// When `jp` changed, keeps the blanks whose particle still starts at their code-point offset and
/// drops the rest (removing an emptied list, which the schema refuses). Returns how many were dropped.
fn keep_matching_blanks(proposed: &mut Value, current: &Value) -> u32 {
    if proposed["jp"] == current["jp"] {
        return 0;
    }
    let jp: Vec<char> = proposed["jp"]
        .as_str()
        .unwrap_or_default()
        .chars()
        .collect();
    let Some(blanks) = proposed
        .get_mut("particle_blanks")
        .and_then(Value::as_array_mut)
    else {
        return 0;
    };
    let before = blanks.len();
    blanks.retain(|blank| {
        let particle: Vec<char> = blank["particle"]
            .as_str()
            .unwrap_or_default()
            .chars()
            .collect();
        let at = blank["at"].as_u64().map(|n| n as usize);
        at.and_then(|at| jp.get(at..at + particle.len()))
            .is_some_and(|run| run == particle.as_slice())
    });
    let dropped = (before - blanks.len()) as u32;
    if blanks.is_empty() {
        if let Some(map) = proposed.as_object_mut() {
            map.remove("particle_blanks");
        }
    }
    dropped
}

fn check_part(file: DataFile, kind: Kind, part: &Value) -> Result<(), String> {
    fn strict<'a, T: serde::Deserialize<'a>>(value: &'a Value) -> Result<(), String> {
        T::deserialize(value).map(drop).map_err(|e| e.to_string())
    }
    match (file, kind) {
        (DataFile::Verbs, Kind::Example) => strict::<VerbExample>(part),
        (DataFile::Verbs, Kind::Collocation) => strict::<Collocation>(part),
        (DataFile::Counters, Kind::Thing) => strict::<CounterThing>(part),
        (DataFile::Counters, Kind::Example) => strict::<CounterExample>(part),
        (DataFile::Counters, Kind::Pitfall) => strict::<CounterPitfall>(part),
        (DataFile::Grammar, Kind::Usage) => strict::<Usage>(part),
        (DataFile::Grammar, Kind::Example) => strict::<GrammarExample>(part),
        (DataFile::Grammar, Kind::Pitfall) => strict::<GrammarPitfall>(part),
        _ => Err(format!("{} has no {}", file.name(), kind.as_str())),
    }
}

fn is_kanji(c: char) -> bool {
    matches!(c,
        '々' | '\u{3400}'..='\u{4DBF}' | '\u{4E00}'..='\u{9FFF}' | '\u{F900}'..='\u{FAFF}'
        | '\u{20000}'..='\u{2FA1F}')
}

fn is_hiragana(c: char) -> bool {
    matches!(c, '\u{3041}'..='\u{309F}' | 'ー')
}

/// Checks furigana readings a suggestion adds: each key a run of kanji not in `known`, each value
/// hiragana, at most `MAX_READINGS`.
pub fn check_furigana(
    add: &BTreeMap<String, String>,
    known: &BTreeMap<String, String>,
) -> Result<(), String> {
    if add.len() > MAX_READINGS {
        return Err(format!("at most {MAX_READINGS} readings per suggestion"));
    }
    for (key, value) in add {
        if key.is_empty() || !key.chars().all(is_kanji) {
            return Err(format!("readings are for kanji: {key}"));
        }
        if known.contains_key(key) {
            return Err(format!("{key} already has a reading"));
        }
        if value.is_empty() || !value.chars().all(is_hiragana) {
            return Err(format!("a reading is written in hiragana: {value}"));
        }
    }
    Ok(())
}
