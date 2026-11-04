//! Turns a published data file into rows for the `items` table: one per entry (verb, word, counter,
//! grammar point) and one per object with a stable id (`scripts/stable_ids.py`'s `id_slots`).
//!
//! Rows keep the published JSON (walked from the raw value, not re-serialised from the strict types)
//! in the canonical form `update_data.review_hash` uses. A sub-item's hash covers its JSON; an
//! entry's covers only its authored fields (`entry_hash`), so it is the hash a review stamp records.

use crate::data::{parse_value, DataFile};
use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    Entry,
    Example,
    Collocation,
    Usage,
    Pitfall,
    Thing,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Entry => "entry",
            Kind::Example => "example",
            Kind::Collocation => "collocation",
            Kind::Usage => "usage",
            Kind::Pitfall => "pitfall",
            Kind::Thing => "thing",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct ItemRow {
    pub kind: Kind,
    pub item_id: String,
    /// The object this one sits in: the entry, or the usage or pitfall around an example.
    pub parent_id: Option<String>,
    /// The entry this row belongs to (its own id for an entry).
    pub entry_id: String,
    /// Document order across the whole file, from 0.
    pub position: u32,
    pub title: String,
    pub subtitle: String,
    pub jlpt: Option<String>,
    pub content_hash: String,
    /// The item's own canonical JSON; an entry's includes its sub-items.
    pub json: String,
}

/// Keys sorted, no whitespace, non-ASCII as-is: the bytes of Python's
/// `json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
pub fn canonical_json(value: &Value) -> String {
    let mut out = String::new();
    write_canonical(value, &[], &mut out);
    out
}

/// Writes `value` canonically, leaving out the top-level keys in `skip`.
fn write_canonical(value: &Value, skip: &[&str], out: &mut String) {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> =
                map.keys().filter(|k| !skip.contains(&k.as_str())).collect();
            keys.sort();
            out.push('{');
            for (i, key) in keys.into_iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                out.push_str(&Value::String(key.clone()).to_string());
                out.push(':');
                write_canonical(&map[key], &[], out);
            }
            out.push('}');
        }
        Value::Array(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push(',');
                }
                write_canonical(item, &[], out);
            }
            out.push(']');
        }
        // Strings, numbers, booleans and null serialise the same way in both languages.
        other => out.push_str(&other.to_string()),
    }
}

pub fn content_hash(value: &Value) -> String {
    sha256_hex(canonical_json(value).as_bytes())
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Keys an entry's hash leaves out: the `review` stamp itself, fields `update_data.py` generates, and
/// sub-items that carry their own hashes. Counters and grammar match `update_data.review_hash`
/// (with `COUNTER_GENERATED`); verbs and words follow the review-site design (authored fields only,
/// not their examples).
fn excluded_from_entry_hash(file: DataFile) -> &'static [&'static str] {
    match file {
        DataFile::Counters => &["review", "readings", "changed", "distractors"],
        DataFile::Grammar => &["review"],
        DataFile::Verbs => &["review", "forms", "examples", "collocations"],
        DataFile::Words => &["review", "forms"],
        DataFile::Furigana | DataFile::Forms => &["review"],
    }
}

/// The hash of an entry's authored content: what a review of the entry vouches for.
pub fn entry_hash(file: DataFile, entry: &Value) -> String {
    let mut out = String::new();
    write_canonical(entry, excluded_from_entry_hash(file), &mut out);
    sha256_hex(out.as_bytes())
}

fn text(v: &Value, key: &str) -> String {
    v.get(key)
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn opt_text(v: &Value, key: &str) -> Option<String> {
    v.get(key).and_then(Value::as_str).map(str::to_string)
}

fn list<'a>(v: &'a Value, key: &str) -> impl Iterator<Item = &'a Value> {
    v.get(key).and_then(Value::as_array).into_iter().flatten()
}

/// `dict (kanji)`, or `dict` without kanji.
fn dict_title(v: &Value) -> String {
    match opt_text(v, "kanji") {
        Some(kanji) => format!("{} ({kanji})", text(v, "dict")),
        None => text(v, "dict"),
    }
}

struct Rows {
    file: DataFile,
    rows: Vec<ItemRow>,
}

impl Rows {
    #[allow(clippy::too_many_arguments)]
    fn push(
        &mut self,
        kind: Kind,
        item_id: String,
        parent_id: Option<&str>,
        entry_id: &str,
        title: String,
        subtitle: String,
        jlpt: Option<String>,
        value: &Value,
    ) {
        // The canonical JSON is built once: stored as-is, and hashed for a sub-item.
        let json = canonical_json(value);
        let content_hash = if kind == Kind::Entry {
            entry_hash(self.file, value)
        } else {
            sha256_hex(json.as_bytes())
        };
        self.rows.push(ItemRow {
            kind,
            item_id,
            parent_id: parent_id.map(str::to_string),
            entry_id: entry_id.to_string(),
            position: self.rows.len() as u32,
            title,
            subtitle,
            jlpt,
            content_hash,
            json,
        });
    }

    fn entry(&mut self, id: &str, title: String, subtitle: String, value: &Value) {
        let jlpt = opt_text(value, "jlpt");
        self.push(
            Kind::Entry,
            id.to_string(),
            None,
            id,
            title,
            subtitle,
            jlpt,
            value,
        );
    }

    /// Example sentences: title jp, subtitle en.
    fn examples(&mut self, kind: Kind, owner: &Value, key: &str, parent: &str, entry: &str) {
        for ex in list(owner, key) {
            let (title, subtitle) = (text(ex, "jp"), text(ex, "en"));
            self.push(
                kind,
                text(ex, "id"),
                Some(parent),
                entry,
                title,
                subtitle,
                None,
                ex,
            );
        }
    }

    /// Usages or pitfalls (heading, explanation) and the examples inside them.
    fn sections(&mut self, kind: Kind, owner: &Value, key: &str, entry: &str) {
        for section in list(owner, key) {
            let id = text(section, "id");
            let jlpt = opt_text(section, "jlpt");
            let (title, subtitle) = (text(section, "heading"), text(section, "explanation"));
            self.push(
                kind,
                id.clone(),
                Some(entry),
                entry,
                title,
                subtitle,
                jlpt,
                section,
            );
            self.examples(Kind::Example, section, "examples", &id, entry);
        }
    }
}

/// The rows for `file`, or the strict parser's error. Furigana and forms have no rows.
pub fn extract(file: DataFile, bytes: &[u8]) -> Result<Vec<ItemRow>, String> {
    let doc: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    parse_value(file, &doc)?;
    if !file.is_browsable() {
        return Ok(Vec::new());
    }
    let mut out = Rows {
        file,
        rows: Vec::new(),
    };
    for entry in list(&doc, file.name()) {
        match file {
            DataFile::Verbs => {
                let id = opt_text(entry, "id").unwrap_or_else(|| text(entry, "dict"));
                out.entry(&id, dict_title(entry), text(entry, "meaning"), entry);
                out.examples(Kind::Example, entry, "examples", &id, &id);
                out.examples(Kind::Collocation, entry, "collocations", &id, &id);
            }
            DataFile::Words => {
                let id = format!("{}:{}", text(entry, "class"), text(entry, "dict"));
                out.entry(&id, dict_title(entry), text(entry, "meaning"), entry);
            }
            DataFile::Counters => {
                let id = text(entry, "id");
                let title = format!("{} ({})", text(entry, "counter"), text(entry, "reading"));
                out.entry(&id, title, text(entry, "meaning"), entry);
                for thing in list(entry, "things") {
                    let (title, subtitle) = (text(thing, "word"), text(thing, "meaning"));
                    let thing_id = text(thing, "id");
                    out.push(
                        Kind::Thing,
                        thing_id,
                        Some(&id),
                        &id,
                        title,
                        subtitle,
                        None,
                        thing,
                    );
                }
                out.examples(Kind::Example, entry, "examples", &id, &id);
                out.sections(Kind::Pitfall, entry, "pitfalls", &id);
            }
            DataFile::Grammar => {
                let id = text(entry, "id");
                out.entry(&id, text(entry, "title"), text(entry, "summary"), entry);
                out.sections(Kind::Usage, entry, "usages", &id);
                out.sections(Kind::Pitfall, entry, "pitfalls", &id);
                // A contrast's own id names another grammar point; its examples belong to this one.
                for contrast in list(entry, "contrasts") {
                    out.examples(Kind::Example, contrast, "examples", &id, &id);
                }
            }
            DataFile::Furigana | DataFile::Forms => unreachable!("not browsable"),
        }
    }
    Ok(out.rows)
}
