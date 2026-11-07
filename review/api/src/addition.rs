//! Building a suggested new item: a new part (example, common phrase, thing, usage, pitfall) or a new entry
//! (verb, word, counter, grammar point). Pure, so every rule is tested natively.
//!
//! The item gets its ids now and keeps them through export: a part a fresh stable id (as
//! `scripts/stable_ids.py` makes them), a verb its kana or `kana:kanji`, a word `class:dict`, a counter or
//! grammar point the slug the reviewer typed. Fields `update_data.py` generates get empty placeholders so
//! the strict types pass; the site has no conjugation engine.

use crate::data::{check_entry, DataFile};
use crate::items::{canonical_json, Kind};
use crate::proposal::{
    check_part, check_verb_form, choice, field, field_value, fields, locked_message, optional,
    Field, Input, TE_GROUPS, VERB_TYPES,
};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

/// The characters of a stable id (no l, o, 0 or 1), as `stable_ids.ALPHABET`.
pub const STABLE_ID_ALPHABET: &[u8] = b"abcdefghijkmnpqrstuvwxyz23456789";
const ID_TRIES: usize = 8;

/// Whether an id is in use in the dataset, and how.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Taken {
    Free,
    /// A loaded item uses it.
    Loaded,
    /// An open or accepted addition uses it.
    Suggested,
}

/// Why an addition can't be built. `Conflict` is a duplicate entry id (409), naming the id; `Invalid` a
/// bad field (400).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AddError {
    Invalid(String),
    Conflict { message: String, id: String },
}

impl From<String> for AddError {
    fn from(message: String) -> Self {
        AddError::Invalid(message)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct NewItem {
    /// The whole new item, ids included.
    pub item: Value,
    /// The new item's own id (a stable id, or the new entry's id).
    pub item_id: String,
    /// The canonical JSON of the item without any `id`, for spotting a repeated submission.
    pub fingerprint: String,
}

const fn kana(name: &'static str) -> Field {
    field(name, Input::Kana)
}

const BASIC_FORMS: [&str; 9] = [
    "masu_pos",
    "masu_neg",
    "masu_past",
    "masu_past_neg",
    "te",
    "short_pos",
    "short_neg",
    "short_past",
    "short_past_neg",
];

const VERB_ADD: &[Field] = &[
    kana("dict"),
    optional(field("kanji", Input::Text)),
    choice("type", VERB_TYPES),
    field("meaning", Input::Text),
    field("description", Input::Long),
    field("notes", Input::Long),
    field("jlpt", Input::Jlpt),
    optional(choice("teGroup", TE_GROUPS)),
    kana("masu_pos"),
    kana("masu_neg"),
    kana("masu_past"),
    kana("masu_past_neg"),
    kana("te"),
    kana("short_pos"),
    kana("short_neg"),
    kana("short_past"),
    kana("short_past_neg"),
    field("example_form", Input::Form),
    field("example_jp", Input::Text),
    field("example_en", Input::Text),
];

const WORD_ADD: &[Field] = &[
    choice("class", &["i-adjective", "na-adjective", "noun"]),
    kana("dict"),
    optional(field("kanji", Input::Text)),
    field("meaning", Input::Text),
    field("jlpt", Input::Jlpt),
];

const COUNTER_ADD: &[Field] = &[
    field("id", Input::Slug),
    field("counter", Input::Text),
    kana("reading"),
    field("meaning", Input::Text),
    field("jlpt", Input::Jlpt),
    choice("sound", &["h-b", "h-p", "irregular", "k", "plain", "s"]),
    Field {
        default: Some("number"),
        ..field("symbol", Input::Text)
    },
];

const GRAMMAR_ADD: &[Field] = &[
    field("id", Input::Slug),
    field("title", Input::Text),
    field("summary", Input::Long),
    field("jlpt", Input::Jlpt),
    field("usage_heading", Input::Text),
    field("usage_explanation", Input::Long),
    field("example_jp", Input::Text),
    field("example_en", Input::Text),
];

const GRAMMAR_USAGE_ADD: &[Field] = &[
    field("heading", Input::Text),
    field("explanation", Input::Long),
    optional(field("jlpt", Input::Jlpt)),
    field("example_jp", Input::Text),
    field("example_en", Input::Text),
];

/// The fields an add form asks for. Empty: nothing of that kind can be added in that dataset.
pub fn add_fields(file: DataFile, kind: Kind) -> &'static [Field] {
    match (file, kind) {
        (DataFile::Verbs, Kind::Entry) => VERB_ADD,
        (DataFile::Words, Kind::Entry) => WORD_ADD,
        (DataFile::Counters, Kind::Entry) => COUNTER_ADD,
        (DataFile::Grammar, Kind::Entry) => GRAMMAR_ADD,
        (DataFile::Grammar, Kind::Usage) => GRAMMAR_USAGE_ADD,
        (file, kind) if !add_parents(file, kind).is_empty() => fields(file, kind),
        _ => &[],
    }
}

/// The kinds a new part of `kind` may be added to. Empty for entries (and for what can't be added).
pub fn add_parents(file: DataFile, kind: Kind) -> &'static [Kind] {
    match (file, kind) {
        (DataFile::Verbs, Kind::Example | Kind::Collocation) => &[Kind::Entry],
        (DataFile::Counters, Kind::Thing | Kind::Pitfall) => &[Kind::Entry],
        (DataFile::Counters, Kind::Example) => &[Kind::Entry, Kind::Pitfall],
        (DataFile::Grammar, Kind::Usage | Kind::Pitfall) => &[Kind::Entry],
        (DataFile::Grammar, Kind::Example) => &[Kind::Usage, Kind::Pitfall],
        _ => &[],
    }
}

/// Every `(dataset, kind)` that can be added, as `"verbs/example"`.
pub fn addable_targets() -> Vec<(String, &'static [Field])> {
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
            let table = add_fields(file, kind);
            if !table.is_empty() {
                out.push((format!("{}/{}", file.name(), kind.as_str()), table));
            }
        }
    }
    out
}

/// A random stable id (it may be taken; `build_add` checks).
pub fn random_stable_id() -> String {
    let mut bytes = [0u8; 6];
    // A failure leaves zeros, which `taken` rejects after the first try or two.
    let _ = getrandom::getrandom(&mut bytes);
    bytes
        .iter()
        .map(|b| STABLE_ID_ALPHABET[(*b as usize) % STABLE_ID_ALPHABET.len()] as char)
        .collect()
}

/// Picks stable ids that no loaded item, other addition or earlier pick uses.
struct Ids<'a> {
    next: &'a mut dyn FnMut() -> String,
    taken: &'a dyn Fn(&str) -> Taken,
    picked: BTreeSet<String>,
}

impl Ids<'_> {
    fn fresh(&mut self) -> Result<String, AddError> {
        for _ in 0..ID_TRIES {
            let candidate = (self.next)();
            if (self.taken)(&candidate) == Taken::Free && self.picked.insert(candidate.clone()) {
                return Ok(candidate);
            }
        }
        Err(AddError::Invalid(
            "couldn't pick a new id; try again".into(),
        ))
    }
}

/// An entry id that must be free: `Loaded` and `Suggested` are conflicts.
fn free_entry_id(id: String, taken: &dyn Fn(&str) -> Taken) -> Result<String, AddError> {
    match taken(&id) {
        Taken::Free => Ok(id),
        Taken::Loaded => Err(AddError::Conflict {
            message: format!("{id} is already in the data"),
            id,
        }),
        Taken::Suggested => Err(AddError::Conflict {
            message: format!(
                "someone already suggested adding {id}; reply on their suggestion instead"
            ),
            id,
        }),
    }
}

/// The submitted fields under the table's rules: unknown keys refused, defaults filled, empty optional
/// fields left out.
fn values(
    table: &[Field],
    submitted: &Map<String, Value>,
) -> Result<BTreeMap<&'static str, String>, String> {
    if let Some(key) = submitted
        .keys()
        .find(|k| !table.iter().any(|f| f.name == *k))
    {
        return Err(locked_message(key));
    }
    let mut out = BTreeMap::new();
    for f in table {
        let given = submitted.get(f.name).cloned().unwrap_or(Value::Null);
        let empty = given.as_str().is_none_or(|t| t.trim().is_empty());
        let value = match f.default {
            Some(default) if empty => Value::String(default.into()),
            _ => given,
        };
        if let Some(text) = field_value(f, f.name, &value)? {
            out.insert(f.name, text);
        }
    }
    Ok(out)
}

/// Removes every `id` key, at any depth.
fn without_ids(value: &Value) -> Value {
    match value {
        Value::Object(map) => Value::Object(
            map.iter()
                .filter(|(k, _)| k.as_str() != "id")
                .map(|(k, v)| (k.clone(), without_ids(v)))
                .collect(),
        ),
        Value::Array(items) => Value::Array(items.iter().map(without_ids).collect()),
        other => other.clone(),
    }
}

/// An item without its ids, as canonical JSON: two submissions of the same new item match on it.
pub fn fingerprint_of(item: &Value) -> String {
    canonical_json(&without_ids(item))
}

/// The error for a new verb whose kana and kanji match `loaded`, the verb already under that kana.
pub fn same_loaded_verb(loaded: &Value, submitted: &Map<String, Value>) -> Option<AddError> {
    let text = |v: Option<&Value>| v.and_then(Value::as_str).unwrap_or("").trim().to_string();
    let (dict, kanji) = (text(submitted.get("dict")), text(submitted.get("kanji")));
    (!kanji.is_empty() && text(loaded.get("dict")) == dict && text(loaded.get("kanji")) == kanji)
        .then(|| AddError::Conflict {
            message: format!("{dict} ({kanji}) is already in the data"),
            id: dict.clone(),
        })
}

/// The new item for `kind` in `file`, built from the reviewer's fields. `parent` is where a part goes (the
/// parent object and its kind); entries take none. `next_id` yields candidate stable ids and `taken` says
/// whether an id is in use.
pub fn build_add(
    file: DataFile,
    kind: Kind,
    parent: Option<(&Value, Kind)>,
    submitted: &Map<String, Value>,
    form_ids: &BTreeSet<String>,
    next_id: &mut dyn FnMut() -> String,
    taken: &dyn Fn(&str) -> Taken,
) -> Result<NewItem, AddError> {
    let table = add_fields(file, kind);
    let allowed = add_parents(file, kind);
    let placed = match parent {
        None => kind == Kind::Entry && !table.is_empty(),
        Some((_, parent_kind)) => allowed.contains(&parent_kind),
    };
    if !placed {
        return Err(AddError::Invalid(format!(
            "{} can't be added there",
            kind.as_str()
        )));
    }
    let v = values(table, submitted)?;
    let text = |name: &str| v.get(name).cloned().unwrap_or_default();
    let mut ids = Ids {
        next: next_id,
        taken,
        picked: BTreeSet::new(),
    };

    let (item, item_id) = match (file, kind) {
        (DataFile::Verbs, Kind::Entry) => {
            let dict = text("dict");
            let kanji = v.get("kanji").cloned();
            let item_id = match (taken(&dict), &kanji) {
                (Taken::Loaded, Some(kanji)) => free_entry_id(format!("{dict}:{kanji}"), taken)?,
                (Taken::Loaded, None) => {
                    return Err(AddError::Invalid(format!(
                        "{dict} is already a verb; add its kanji so the new one gets its own id"
                    )))
                }
                _ => free_entry_id(dict.clone(), taken)?,
            };
            let forms: Map<String, Value> = BASIC_FORMS
                .iter()
                .map(|name| (name.to_string(), Value::String(text(name))))
                .collect();
            let example_form = text("example_form");
            check_verb_form(
                &dict,
                &Value::Object(forms.clone()),
                &example_form,
                form_ids,
            )?;
            let label = match text("type").as_str() {
                "ru" => "Ru-verb",
                "u" => "U-verb",
                _ => "Irregular",
            };
            let mut verb = json!({
                "type": text("type"), "label": label, "dict": dict, "meaning": text("meaning"),
                "description": text("description"), "notes": text("notes"), "jlpt": text("jlpt"),
                "forms": forms,
                "examples": [{"id": ids.fresh()?, "form": example_form, "jp": text("example_jp"),
                              "en": text("example_en")}],
            });
            if let Some(kanji) = kanji {
                verb["kanji"] = json!(kanji);
            }
            if let Some(group) = v.get("teGroup") {
                verb["teGroup"] = json!(group);
            }
            if item_id != dict {
                verb["id"] = json!(item_id);
            }
            (verb, item_id)
        }
        (DataFile::Words, Kind::Entry) => {
            let item_id = free_entry_id(format!("{}:{}", text("class"), text("dict")), taken)?;
            let mut word = json!({"class": text("class"), "dict": text("dict"), "meaning": text("meaning"),
                                  "jlpt": text("jlpt"), "forms": {}});
            if let Some(kanji) = v.get("kanji") {
                word["kanji"] = json!(kanji);
            }
            (word, item_id)
        }
        (DataFile::Counters, Kind::Entry) => {
            let item_id = free_entry_id(text("id"), taken)?;
            let counter = json!({
                "id": item_id, "counter": text("counter"), "reading": text("reading"),
                "meaning": text("meaning"), "jlpt": text("jlpt"), "sound": text("sound"),
                "symbol": text("symbol"), "overrides": {}, "things": [], "examples": [], "pitfalls": [],
                "related": [], "readings": {}, "changed": [], "distractors": {},
            });
            (counter, item_id)
        }
        (DataFile::Grammar, Kind::Entry) => {
            let item_id = free_entry_id(text("id"), taken)?;
            let point = json!({
                "id": item_id, "title": text("title"), "summary": text("summary"), "jlpt": text("jlpt"),
                "usages": [{"id": ids.fresh()?, "heading": text("usage_heading"),
                            "explanation": text("usage_explanation"),
                            "examples": [{"id": ids.fresh()?, "jp": text("example_jp"), "en": text("example_en")}]}],
                "attachment": [], "conjugations": [], "pitfalls": [], "related": [],
            });
            (point, item_id)
        }
        (DataFile::Grammar, Kind::Usage) => {
            let id = ids.fresh()?;
            let mut usage = json!({
                "id": id, "heading": text("heading"), "explanation": text("explanation"),
                "examples": [{"id": ids.fresh()?, "jp": text("example_jp"), "en": text("example_en")}],
            });
            if let Some(level) = v.get("jlpt") {
                usage["jlpt"] = json!(level);
            }
            (usage, id)
        }
        _ => {
            let id = ids.fresh()?;
            let mut part: Map<String, Value> = v
                .iter()
                .map(|(k, val)| (k.to_string(), Value::String(val.clone())))
                .collect();
            part.insert("id".into(), Value::String(id.clone()));
            if file == DataFile::Verbs && kind == Kind::Example {
                let (verb, _) = parent.expect("checked above");
                let dict = verb["dict"].as_str().unwrap_or_default();
                check_verb_form(dict, &verb["forms"], &text("form"), form_ids)?;
            }
            (Value::Object(part), id)
        }
    };

    let schema = |e: String| AddError::Invalid(format!("doesn't fit the data schema: {e}"));
    match kind {
        Kind::Entry => check_entry(file, &item).map_err(schema)?,
        _ => check_part(file, kind, &item).map_err(schema)?,
    }
    let fingerprint = fingerprint_of(&item);
    Ok(NewItem {
        item,
        item_id,
        fingerprint,
    })
}

/// How the new item is titled in lists: an entry as the site titles it, an example or common phrase by its
/// sentence, a usage or pitfall by its heading, a thing by its word.
pub fn add_title(file: DataFile, kind: Kind, item: &Value) -> String {
    let text = |key: &str| item[key].as_str().unwrap_or_default().to_string();
    match (file, kind) {
        (DataFile::Verbs | DataFile::Words, Kind::Entry) => match item["kanji"].as_str() {
            Some(kanji) => format!("{} ({kanji})", text("dict")),
            None => text("dict"),
        },
        (DataFile::Counters, Kind::Entry) => format!("{} ({})", text("counter"), text("reading")),
        (DataFile::Grammar, Kind::Entry) => text("title"),
        (_, Kind::Usage | Kind::Pitfall) => text("heading"),
        (_, Kind::Thing) => text("word"),
        _ => text("jp"),
    }
}

/// Where each add-only field sits in a built item, so a proposal can be turned back into form fields.
fn field_path(file: DataFile, kind: Kind, name: &str) -> Vec<String> {
    let path = |parts: &[&str]| parts.iter().map(|p| p.to_string()).collect();
    match (file, kind, name) {
        (DataFile::Verbs, Kind::Entry, form) if BASIC_FORMS.contains(&form) => {
            path(&["forms", form])
        }
        (DataFile::Verbs, Kind::Entry, "example_form") => path(&["examples", "0", "form"]),
        (
            DataFile::Verbs | DataFile::Grammar,
            Kind::Entry | Kind::Usage,
            "example_jp" | "example_en",
        ) => {
            let key = &name["example_".len()..];
            if (file, kind) == (DataFile::Grammar, Kind::Entry) {
                path(&["usages", "0", "examples", "0", key])
            } else {
                path(&["examples", "0", key])
            }
        }
        (DataFile::Grammar, Kind::Entry, "usage_heading" | "usage_explanation") => {
            path(&["usages", "0", &name["usage_".len()..]])
        }
        _ => path(&[name]),
    }
}

/// The add form's fields for a built item: the inverse of `build_add`, so the owner's edits can be applied
/// to a proposal and built again.
pub fn add_fields_of(file: DataFile, kind: Kind, item: &Value) -> Map<String, Value> {
    add_fields(file, kind)
        .iter()
        .filter_map(|f| {
            let value = field_path(file, kind, f.name)
                .iter()
                .try_fold(item, |v, key| match key.parse::<usize>() {
                    Ok(i) => v.get(i),
                    Err(_) => v.get(key.as_str()),
                })?;
            value
                .as_str()
                .map(|text| (f.name.to_string(), Value::String(text.to_string())))
        })
        .collect()
}

/// The stable ids a built item holds, in the order `build_add` assigns them, so a rebuild keeps them.
pub fn stable_ids_of(file: DataFile, kind: Kind, item: &Value) -> Vec<String> {
    let id = |v: &Value| v["id"].as_str().map(str::to_string);
    let ids = match (file, kind) {
        (DataFile::Verbs, Kind::Entry) => vec![id(&item["examples"][0])],
        (DataFile::Grammar, Kind::Entry) => vec![
            id(&item["usages"][0]),
            id(&item["usages"][0]["examples"][0]),
        ],
        (DataFile::Grammar, Kind::Usage) => vec![id(item), id(&item["examples"][0])],
        (_, Kind::Entry) => vec![],
        _ => vec![id(item)],
    };
    ids.into_iter().flatten().collect()
}
