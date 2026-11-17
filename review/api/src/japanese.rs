//! Which edits are Japanese text: what a native may decide (polish step 3b). Pure, so the rule is tested
//! natively and runs the same for `/api/decide` and the inbox's `japanese_only`.

use serde_json::Value;
use std::collections::BTreeSet;

/// Fields holding Japanese text. Kept equal to the web's `JAPANESE_FIELDS` in
/// `review/web/src/lib/labels.ts` by a test.
pub const JAPANESE_FIELDS: &[&str] = &[
    "jp",
    "counter",
    "reading",
    "word",
    "kana",
    "wrong",
    "kanji",
    "dict",
    "example_jp",
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

/// Not a field anyone edits: blanks are dropped when a `jp` edit moves their particle, and export marks
/// them again.
const DERIVED: &[&str] = &["particle_blanks"];

pub fn is_japanese_field(name: &str) -> bool {
    JAPANESE_FIELDS.contains(&name)
}

/// The keys whose values differ between two items (a key on one side only counts), leaving out derived
/// keys. Empty unless both are objects.
pub fn edited_fields(proposed: &Value, current: &Value) -> BTreeSet<String> {
    let (Some(a), Some(b)) = (proposed.as_object(), current.as_object()) else {
        return BTreeSet::new();
    };
    a.keys()
        .chain(b.keys())
        .filter(|key| !DERIVED.contains(&key.as_str()) && a.get(*key) != b.get(*key))
        .cloned()
        .collect()
}

/// Something changed, and every changed field is Japanese text. False when either item is missing.
pub fn japanese_only(proposed: &Value, current: &Value) -> bool {
    let edited = edited_fields(proposed, current);
    !edited.is_empty() && edited.iter().all(|key| is_japanese_field(key))
}
