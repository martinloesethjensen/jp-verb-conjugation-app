//! Turns a published data file into rows for the `items` table: one per entry (verb, word, counter,
//! grammar point) and one per object with a stable id (`scripts/stable_ids.py`'s `id_slots`).
//!
//! Rows keep the published JSON (walked from the raw value, not re-serialised from the strict types)
//! in the canonical form `update_data.review_hash` uses. A sub-item's hash covers its JSON; an
//! entry's covers only its authored fields (`entry_hash`), so it is the hash a review stamp records.

use crate::data::{check_entry, parse_value, DataFile};
use serde::Serialize;
use serde_json::value::RawValue;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::ops::Range;

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
    /// Document order across the whole file: `entry index * ENTRY_STRIDE + row within the entry`, so
    /// slices can be written separately and still sort in order.
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

/// The most published JSON one slice of a load handles. A slice keeps a Worker request well under
/// Workers Free's CPU limit; an entry bigger than this is a slice on its own.
pub const SLICE_BYTES: usize = 24_000;

/// Room for each entry's rows in `position`.
pub const ENTRY_STRIDE: u32 = 10_000;

struct Rows {
    file: DataFile,
    entry_index: u32,
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
            position: self.entry_index * ENTRY_STRIDE + self.rows.len() as u32,
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

/// One request's share of a load: a run of consecutive entries and where their JSON sits in the
/// file. Byte ranges are trusted only because every request re-checks the file's hash first.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct Slice {
    pub entries: Range<usize>,
    pub bytes: Range<usize>,
}

/// The top level of a browsable file with its entries left as raw JSON, after checking everything
/// else (version, description, groups…) against the strict types with an empty entry list.
fn raw_entries(file: DataFile, bytes: &[u8]) -> Result<Vec<&RawValue>, String> {
    let top: BTreeMap<String, &RawValue> =
        serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    let mut rest = serde_json::Map::new();
    let mut entries = None;
    for (key, raw) in &top {
        if key == file.name() {
            entries =
                Some(serde_json::from_str::<Vec<&RawValue>>(raw.get()).map_err(|e| e.to_string())?);
            rest.insert(key.clone(), Value::Array(Vec::new()));
        } else {
            rest.insert(
                key.clone(),
                serde_json::from_str(raw.get()).map_err(|e| e.to_string())?,
            );
        }
    }
    parse_value(file, &Value::Object(rest))?;
    entries.ok_or_else(|| format!("missing field `{}`", file.name()))
}

/// The slices a load processes one request at a time: consecutive entries whose published JSON adds
/// up to at most `SLICE_BYTES`. Checks the whole file's top level against the strict types. A pure
/// function of the bytes, so every request of a load agrees. Furigana and forms (checked whole
/// here) have none.
pub fn slices(file: DataFile, bytes: &[u8]) -> Result<Vec<Slice>, String> {
    if !file.is_browsable() {
        let doc: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
        parse_value(file, &doc)?;
        return Ok(Vec::new());
    }
    let entries = raw_entries(file, bytes)?;
    let base = bytes.as_ptr() as usize;
    // Where an entry's JSON sits in `bytes`: RawValue borrows from the input, so this is exact.
    let span = |raw: &RawValue| {
        let start = raw.get().as_ptr() as usize - base;
        start..start + raw.get().len()
    };
    let mut out = Vec::new();
    let (mut start, mut size) = (0, 0);
    for (i, raw) in entries.iter().enumerate() {
        let len = raw.get().len();
        if i > start && size + len > SLICE_BYTES {
            out.push(Slice {
                entries: start..i,
                bytes: span(entries[start]).start..span(entries[i - 1]).end,
            });
            (start, size) = (i, 0);
        }
        size += len;
    }
    if start < entries.len() {
        let last = entries.len() - 1;
        out.push(Slice {
            entries: start..entries.len(),
            bytes: span(entries[start]).start..span(entries[last]).end,
        });
    }
    Ok(out)
}

/// The rows for one slice, each entry checked against the strict types. Only the slice's own bytes
/// are parsed; they must hold exactly `slice.entries.len()` whole entries.
pub fn extract_slice(file: DataFile, bytes: &[u8], slice: &Slice) -> Result<Vec<ItemRow>, String> {
    if !file.is_browsable() {
        return Ok(Vec::new());
    }
    let region = bytes
        .get(slice.bytes.clone())
        .ok_or("the slice is outside the file")?;
    let region = std::str::from_utf8(region).map_err(|_| "the slice isn't UTF-8".to_string())?;
    let entries: Vec<Value> = serde_json::from_str(&format!("[{region}]"))
        .map_err(|_| "the slice isn't a run of whole entries".to_string())?;
    if entries.len() != slice.entries.len() {
        return Err("the slice isn't a run of whole entries".to_string());
    }
    let mut out = Rows {
        file,
        entry_index: 0,
        rows: Vec::new(),
    };
    let mut rows = Vec::new();
    for (offset, entry) in entries.iter().enumerate() {
        check_entry(file, entry)?;
        out.entry_index = (slice.entries.start + offset) as u32;
        out.rows.clear();
        entry_rows(&mut out, file, entry);
        rows.append(&mut out.rows);
    }
    Ok(rows)
}

/// The rows for the whole file, or the strict parser's error. Furigana and forms have no rows.
pub fn extract(file: DataFile, bytes: &[u8]) -> Result<Vec<ItemRow>, String> {
    let mut rows = Vec::new();
    for slice in slices(file, bytes)? {
        rows.extend(extract_slice(file, bytes, &slice)?);
    }
    Ok(rows)
}

fn entry_rows(out: &mut Rows, file: DataFile, entry: &Value) {
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
        DataFile::Furigana | DataFile::Forms => {}
    }
}
