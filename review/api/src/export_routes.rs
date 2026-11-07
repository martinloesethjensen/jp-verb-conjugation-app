//! Export: what `make review-pull` reads. `GET /api/export` answers only the export service token;
//! `GET /api/admin/export` is the same batch for the owner's Export page. Plain SELECTs: every rewrite of
//! the data happens in Python on the owner's Mac.

use crate::app::{parse, ApiResponse};
use crate::auth::Principal;
use crate::data::DataFile;
use crate::items::Kind;
use crate::proposal::fields;
use crate::review_routes::{ok, tri, unavailable};
use crate::review_store::{ExportRow, ReviewStore};
use crate::store::Store;
use serde::Deserialize;
use serde_json::{json, Map, Value};

/// The keys a change may set or remove: its form's fields, plus `particle_blanks` where the form edits a
/// sentence (a changed `jp` keeps only the blanks that still match).
pub fn editable(file: DataFile, kind: Kind) -> Vec<&'static str> {
    let table = fields(file, kind);
    let mut names: Vec<&'static str> = table.iter().map(|f| f.name).collect();
    if table.iter().any(|f| f.name == "jp") {
        names.push("particle_blanks");
    }
    names
}

fn json_or_null(text: Option<&str>) -> Value {
    text.and_then(|t| serde_json::from_str(t).ok())
        .unwrap_or(Value::Null)
}

fn suggestion_json(r: &ExportRow) -> Value {
    let keys = (r.action == "change")
        .then(|| DataFile::parse_name(&r.dataset).zip(Kind::parse(&r.kind)))
        .flatten()
        .map(|(file, kind)| json!(editable(file, kind)))
        .unwrap_or(Value::Null);
    let item = if matches!(r.action.as_str(), "change" | "add") {
        json_or_null(r.item_json.as_deref())
    } else {
        Value::Null
    };
    json!({
        "id": r.id, "action": r.action, "dataset": r.dataset, "kind": r.kind, "item_id": r.item_id,
        "entry_id": r.entry_id, "parent_kind": r.parent_kind, "parent_id": r.parent_id,
        "item_title": r.item_title, "item": item, "editable": keys,
        "furigana": json_or_null(r.furigana_json.as_deref()), "comment": r.comment,
        "credit": { "role": r.credit_role, "name": r.credit_name }, "decided_at": r.decided_at,
        "stale": r.stale != 0,
    })
}

pub async fn batch<S: Store + ReviewStore>(store: &S) -> ApiResponse {
    let files = tri!(store.snapshot_files().await.map_err(unavailable));
    let (suggestions, stamps) = tri!(store.export_batch().await.map_err(unavailable));
    let files: Map<String, Value> = files
        .into_iter()
        .map(|f| (f.name, Value::String(f.sha256)))
        .collect();
    let suggestions: Vec<Value> = suggestions.iter().map(suggestion_json).collect();
    ok(
        200,
        json!({ "files": files, "suggestions": suggestions, "stamps": stamps }),
    )
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MarkBody {
    suggestions: Vec<i64>,
    stamps: Vec<i64>,
}

pub async fn mark<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: MarkBody = tri!(parse(body));
    match store
        .mark_exported(&body.suggestions, &body.stamps, &by.email, now)
        .await
    {
        Ok((suggestions, stamps)) => {
            ok(200, json!({ "suggestions": suggestions, "stamps": stamps }))
        }
        Err(e) => unavailable(e),
    }
}
