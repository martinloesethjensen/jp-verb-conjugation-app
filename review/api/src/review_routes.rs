//! The review routes: approve, suggest, comment, queues and the owner's inbox. `app::handle` has already
//! checked who is asking and the `Origin`; these check the body and the target.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::data::DataFile;
use crate::items::Kind;
use crate::proposal::{build_change, check_furigana, MAX_TEXT};
use crate::review_store::{
    NewSuggestion, OwnerEdit, QueueFilter, QueueItem, ReviewStore, Suggestion, Target,
};
use crate::store::{Role, Store, StoreError};
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

pub const NOT_LOADED_ITEM: &str = "that isn't in the loaded data";
pub const STALE: &str = "this changed since you opened it; reload to see the new version";
pub const DECIDED: &str = "this suggestion has already been decided";
const UNAVAILABLE: &str = "the database is unavailable";

pub(crate) fn ok(status: u16, body: Value) -> ApiResponse {
    ApiResponse { status, body }
}

pub(crate) fn unavailable(_: StoreError) -> ApiResponse {
    error(500, UNAVAILABLE)
}

/// Unwraps a `Result<T, ApiResponse>`, returning the response early.
macro_rules! tri {
    ($e:expr) => {
        match $e {
            Ok(value) => value,
            Err(response) => return response,
        }
    };
}
pub(crate) use tri;

/// A dataset and kind that exist, else 400.
pub(crate) fn target(
    dataset: &str,
    kind: &str,
    id: &str,
) -> Result<(DataFile, Kind, Target), ApiResponse> {
    let file = DataFile::parse_name(dataset)
        .filter(|f| f.is_browsable())
        .ok_or_else(|| error(400, "unknown dataset"))?;
    let kind_value = Kind::parse(kind).ok_or_else(|| error(400, "unknown kind"))?;
    Ok((
        file,
        kind_value,
        Target {
            dataset: dataset.to_string(),
            kind: kind.to_string(),
            item_id: id.to_string(),
        },
    ))
}

/// The target's `(content_hash, entry_id, title)`, or 404 when it isn't loaded.
pub(crate) async fn loaded_target<S: ReviewStore>(
    store: &S,
    t: &Target,
) -> Result<(String, String, String), ApiResponse> {
    store
        .current_hash(t)
        .await
        .map_err(unavailable)?
        .ok_or_else(|| error(404, NOT_LOADED_ITEM))
}

/// Trimmed text of at most `MAX_TEXT` characters; `what` names it in the error.
pub(crate) fn text_field(raw: &str, what: &str) -> Result<String, ApiResponse> {
    let text = raw.trim();
    if text.chars().count() > MAX_TEXT {
        return Err(error(400, &format!("{what} is too long")));
    }
    Ok(text.to_string())
}

pub(crate) async fn suggestion_response<S: ReviewStore>(
    store: &S,
    id: i64,
    viewer: &str,
    status: u16,
) -> ApiResponse {
    match store.suggestion(id, viewer).await {
        Ok(Some(s)) => ok(status, json!(s)),
        Ok(None) => error(404, "no such suggestion"),
        Err(e) => unavailable(e),
    }
}

async fn approvals_response<S: ReviewStore>(
    store: &S,
    dataset: &str,
    entry_id: Option<&str>,
    viewer: &str,
) -> ApiResponse {
    let Some(entry_id) = entry_id else {
        return ok(200, json!({ "approvals": [] }));
    };
    match store.entry_review(dataset, entry_id, viewer).await {
        Ok((approvals, _)) => ok(200, json!({ "approvals": approvals })),
        Err(e) => unavailable(e),
    }
}

// --- GET /api/review ----------------------------------------------------------------------------

pub async fn review<S: ReviewStore>(
    dataset: Option<String>,
    id: Option<String>,
    by: &Principal,
    store: &S,
) -> ApiResponse {
    let file = tri!(dataset
        .as_deref()
        .and_then(DataFile::parse_name)
        .filter(|f| f.is_browsable())
        .ok_or_else(|| error(400, "unknown dataset")));
    let Some(id) = id else {
        return error(400, "which item? (id is missing)");
    };
    let parts = tri!(store.parts(file.name(), &id).await.map_err(unavailable));
    let (approvals, suggestions) = tri!(store
        .entry_review(file.name(), &id, &by.email)
        .await
        .map_err(unavailable));
    // Stamps: only for what the pipeline stamps, so other datasets cost no extra queries.
    let (mut stamp, mut stampable) = (None, false);
    if crate::stamp_routes::stampable(file, Kind::Entry) {
        let t = Target {
            dataset: file.name().to_string(),
            kind: Kind::Entry.as_str().to_string(),
            item_id: id.clone(),
        };
        stamp = tri!(store.pending_stamp(&t).await.map_err(unavailable));
        stampable = stamp.is_none() && crate::stamp_routes::ready(store, &t).await.is_ok();
    }
    ok(
        200,
        json!({ "parts": parts, "approvals": approvals, "suggestions": suggestions,
                "stamp": stamp, "stampable": stampable }),
    )
}

// --- Approvals -----------------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ApproveBody {
    dataset: String,
    kind: String,
    id: String,
    content_hash: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TargetBody {
    dataset: String,
    kind: String,
    id: String,
}

pub async fn approve<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: ApproveBody = tri!(parse(body));
    let (_, _, t) = tri!(target(&body.dataset, &body.kind, &body.id));
    let (hash, entry_id, _) = tri!(loaded_target(store, &t).await);
    if hash != body.content_hash {
        return error(409, STALE);
    }
    tri!(store
        .approve(&t, &hash, &by.email, now)
        .await
        .map_err(unavailable));
    approvals_response(store, &t.dataset, Some(&entry_id), &by.email).await
}

pub async fn withdraw_approval<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: TargetBody = tri!(parse(body));
    let (_, _, t) = tri!(target(&body.dataset, &body.kind, &body.id));
    let current = tri!(store.current_hash(&t).await.map_err(unavailable));
    tri!(store
        .unapprove(&t, &by.email, now)
        .await
        .map_err(unavailable));
    let entry_id = current.map(|(_, entry_id, _)| entry_id);
    approvals_response(store, &t.dataset, entry_id.as_deref(), &by.email).await
}

// --- Suggestions ---------------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SuggestBody {
    dataset: String,
    kind: String,
    id: String,
    base_hash: String,
    action: String,
    #[serde(default)]
    edits: Option<Map<String, Value>>,
    #[serde(default)]
    furigana: Option<BTreeMap<String, String>>,
    #[serde(default)]
    comment: Option<String>,
}

/// The form ids and furigana readings the loaded reference files define.
pub(crate) async fn reference_sets<S: Store>(
    store: &S,
) -> Result<(BTreeSet<String>, BTreeMap<String, String>), ApiResponse> {
    let stored = |name: &'static str| async move {
        store
            .snapshot_json(name)
            .await
            .map_err(unavailable)
            .map(|text| text.and_then(|t| serde_json::from_str::<Value>(&t).ok()))
    };
    let forms = stored("forms")
        .await?
        .map(|doc| {
            doc["forms"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|f| f["id"].as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    let readings = stored("furigana")
        .await?
        .and_then(|doc| serde_json::from_value(doc["readings"].clone()).ok())
        .unwrap_or_default();
    Ok((forms, readings))
}

/// The proposed item for a change: `edits` applied to the target's current JSON, plus checked
/// furigana. Returns `(proposed_json, furigana_json, dropped_blanks)`.
pub(crate) async fn proposed_change<S: Store>(
    store: &S,
    file: DataFile,
    kind: Kind,
    t: &Target,
    entry_id: &str,
    edits: &Map<String, Value>,
    furigana: Option<&BTreeMap<String, String>>,
) -> Result<(String, Option<String>, u32), ApiResponse> {
    let (json, _) = store
        .entry(&t.dataset, entry_id)
        .await
        .map_err(unavailable)?
        .ok_or_else(|| error(404, NOT_LOADED_ITEM))?;
    let entry: Value = serde_json::from_str(&json).map_err(|_| error(500, UNAVAILABLE))?;
    let (form_ids, readings) = reference_sets(store).await?;
    let change = build_change(file, kind, &entry, &t.item_id, edits, &form_ids)
        .map_err(|message| error(400, &message))?;
    let furigana = match furigana.filter(|f| !f.is_empty()) {
        Some(add) => {
            check_furigana(add, &readings).map_err(|message| error(400, &message))?;
            Some(serde_json::to_string(add).unwrap_or_default())
        }
        None => None,
    };
    Ok((change.proposed.to_string(), furigana, change.dropped_blanks))
}

pub async fn suggest<S: Store + ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: SuggestBody = tri!(parse(body));
    let (file, kind, t) = tri!(target(&body.dataset, &body.kind, &body.id));
    let (hash, entry_id, title) = tri!(loaded_target(store, &t).await);
    if hash != body.base_hash {
        return error(409, STALE);
    }
    let comment = tri!(text_field(body.comment.as_deref().unwrap_or(""), "comment"));
    let (proposed_json, furigana_json, dropped_blanks) = match body.action.as_str() {
        "change" => {
            let edits = body.edits.unwrap_or_default();
            if edits.is_empty() {
                return error(400, "nothing changed");
            }
            let (p, f, d) = tri!(
                proposed_change(
                    store,
                    file,
                    kind,
                    &t,
                    &entry_id,
                    &edits,
                    body.furigana.as_ref()
                )
                .await
            );
            (Some(p), f, d)
        }
        "delete" | "note" => {
            if body.edits.is_some() || body.furigana.is_some() {
                return error(400, "only a change carries edits or readings");
            }
            if body.action == "note" && comment.is_empty() {
                return error(400, "a note needs a comment");
            }
            (None, None, 0)
        }
        _ => return error(400, "unknown action"),
    };
    let new = NewSuggestion {
        action: body.action,
        target: t,
        entry_id,
        item_title: title,
        base_hash: hash,
        proposed_json,
        furigana_json,
        dropped_blanks,
        comment,
        parent_kind: None,
        parent_id: None,
        fingerprint: None,
    };
    let (id, created) = tri!(store
        .add_suggestion(&new, &by.email, now)
        .await
        .map_err(unavailable));
    suggestion_response(store, id, &by.email, if created { 201 } else { 200 }).await
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct IdBody {
    id: i64,
}

pub async fn withdraw_suggestion<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: IdBody = tri!(parse(body));
    match store.withdraw(body.id, &by.email, now).await {
        Ok(()) => suggestion_response(store, body.id, &by.email, 200).await,
        Err(StoreError::Conflict) => error(403, "only the person who suggested it can withdraw it"),
        Err(StoreError::NotFound) => error(409, DECIDED),
        Err(e) => unavailable(e),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CommentBody {
    suggestion_id: i64,
    body: String,
}

pub async fn comment<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: CommentBody = tri!(parse(body));
    let text = tri!(text_field(&body.body, "comment"));
    if text.is_empty() {
        return error(400, "a comment can't be empty");
    }
    match store
        .add_comment(body.suggestion_id, &text, &by.email, now)
        .await
    {
        Ok(()) => suggestion_response(store, body.suggestion_id, &by.email, 201).await,
        Err(StoreError::NotFound) => error(404, "no such suggestion"),
        Err(e) => unavailable(e),
    }
}

// --- Queues --------------------------------------------------------------------------------------

/// The most items in one queue, and the most pasted ids.
pub const MAX_QUEUE: usize = 500;
pub const MAX_QUEUE_TITLE: usize = 80;
/// How many items a preview lists.
const PREVIEW_ITEMS: usize = 50;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct QueueRequest {
    #[serde(default)]
    title: String,
    #[serde(default)]
    description: String,
    filter: QueueFilter,
    #[serde(default)]
    ids_text: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct QueueTargetBody {
    queue_id: i64,
    dataset: String,
    kind: String,
    id: String,
    #[serde(default)]
    note: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct QueueUpdateBody {
    id: i64,
    title: String,
    description: String,
    archived: bool,
}

/// The queue and its items as the viewer sees them; 404 when unknown, or archived for a reviewer.
pub(crate) async fn queue_response<S: ReviewStore>(
    store: &S,
    id: i64,
    by: &Principal,
    status: u16,
) -> ApiResponse {
    match store.queue(id, &by.email).await {
        Ok(Some((queue, _))) if queue.archived && by.role != Role::Admin => {
            error(404, "no such queue")
        }
        Ok(Some((queue, items))) => ok(status, json!({ "queue": queue, "items": items })),
        Ok(None) => error(404, "no such queue"),
        Err(e) => unavailable(e),
    }
}

pub async fn list_queues<S: ReviewStore>(
    by: &Principal,
    store: &S,
    include_archived: bool,
) -> ApiResponse {
    match store.queues(&by.email, include_archived).await {
        Ok(queues) => ok(200, json!({ "queues": queues })),
        Err(e) => unavailable(e),
    }
}

pub async fn get_queue<S: ReviewStore>(
    id: Option<String>,
    by: &Principal,
    store: &S,
) -> ApiResponse {
    let Some(id) = id.and_then(|id| id.parse::<i64>().ok()) else {
        return error(400, "which queue? (id is missing)");
    };
    queue_response(store, id, by, 200).await
}

/// The filter with the pasted ids added, and the pasted lines. The dataset must be browsable.
fn queue_filter(
    mut filter: QueueFilter,
    ids_text: &str,
) -> Result<(QueueFilter, Vec<String>), ApiResponse> {
    target(&filter.dataset, "entry", "")?;
    if filter.kinds.iter().any(|k| Kind::parse(k).is_none()) {
        return Err(error(400, "unknown kind"));
    }
    let lines: Vec<String> = ids_text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(str::to_string)
        .collect();
    if lines.len() > MAX_QUEUE {
        return Err(error(400, "paste at most 500 ids"));
    }
    filter.ids.extend(lines.iter().cloned());
    Ok((filter, lines))
}

/// The items a request picks, and the pasted lines that matched nothing.
async fn picked<S: ReviewStore>(
    store: &S,
    request: QueueRequest,
) -> Result<(QueueFilter, Vec<QueueItem>, Vec<String>, String, String), ApiResponse> {
    let (filter, lines) = queue_filter(request.filter, &request.ids_text)?;
    let items = store.preview_queue(&filter).await.map_err(unavailable)?;
    let unmatched = lines
        .into_iter()
        .filter(|line| !items.iter().any(|i| &i.item_id == line))
        .collect();
    Ok((filter, items, unmatched, request.title, request.description))
}

pub async fn preview_queue<S: ReviewStore>(body: &[u8], store: &S) -> ApiResponse {
    let request: QueueRequest = tri!(parse(body));
    let (_, items, unmatched, _, _) = tri!(picked(store, request).await);
    let first: Vec<&QueueItem> = items.iter().take(PREVIEW_ITEMS).collect();
    ok(
        200,
        json!({ "count": items.len(), "items": first, "unmatched": unmatched }),
    )
}

pub async fn create_queue<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let request: QueueRequest = tri!(parse(body));
    let (filter, items, _, title, description) = tri!(picked(store, request).await);
    let title = tri!(queue_title(&title));
    let description = tri!(text_field(&description, "description"));
    if items.is_empty() {
        return error(400, "nothing matches");
    }
    if items.len() > MAX_QUEUE {
        return error(400, "a queue holds at most 500 items; narrow the filter");
    }
    match store
        .add_queue(&title, &description, &filter, &by.email, now)
        .await
    {
        Ok(id) => queue_response(store, id, by, 201).await,
        Err(e) => unavailable(e),
    }
}

fn queue_title(raw: &str) -> Result<String, ApiResponse> {
    let title = raw.trim();
    if title.is_empty() {
        return Err(error(400, "a queue needs a title"));
    }
    if title.chars().count() > MAX_QUEUE_TITLE {
        return Err(error(400, "a queue title is at most 80 characters"));
    }
    Ok(title.to_string())
}

pub async fn update_queue<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: QueueUpdateBody = tri!(parse(body));
    let title = tri!(queue_title(&body.title));
    let description = tri!(text_field(&body.description, "description"));
    match store
        .update_queue(body.id, &title, &description, body.archived, &by.email, now)
        .await
    {
        Ok(()) => queue_response(store, body.id, by, 200).await,
        Err(StoreError::NotFound) => error(404, "no such queue"),
        Err(e) => unavailable(e),
    }
}

/// What a queue-item route does with its target.
pub enum QueueItemAction {
    Skip,
    Note,
    Remove,
}

pub async fn queue_item<S: ReviewStore>(
    action: QueueItemAction,
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: QueueTargetBody = tri!(parse(body));
    let (_, _, t) = tri!(target(&body.dataset, &body.kind, &body.id));
    let result = match action {
        QueueItemAction::Skip => store.skip(body.queue_id, &t, &by.email, now).await,
        QueueItemAction::Note => {
            let note = tri!(text_field(body.note.as_deref().unwrap_or(""), "note"));
            store
                .set_queue_note(body.queue_id, &t, &note, &by.email, now)
                .await
        }
        QueueItemAction::Remove => {
            store
                .remove_queue_item(body.queue_id, &t, &by.email, now)
                .await
        }
    };
    match result {
        Ok(()) => queue_response(store, body.queue_id, by, 200).await,
        Err(StoreError::NotFound) => error(404, "that isn't in this queue"),
        Err(e) => unavailable(e),
    }
}

// --- The owner's inbox ---------------------------------------------------------------------------

pub const ACCEPT_STALE: &str = "the data changed since this was suggested; use Edit then accept";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DecideBody {
    id: i64,
    decision: String,
    #[serde(default)]
    edits: Option<Map<String, Value>>,
    #[serde(default)]
    furigana: Option<BTreeMap<String, String>>,
    #[serde(default)]
    reply: Option<String>,
    #[serde(default)]
    confirm: bool,
}

/// The target's current JSON, from its entry: null when it left the data.
async fn current_json<S: Store>(
    store: &S,
    entries: &mut BTreeMap<(String, String), Option<Value>>,
    s: &Suggestion,
) -> Value {
    let key = (s.dataset.clone(), s.entry_id.clone());
    if !entries.contains_key(&key) {
        let entry = store
            .entry(&s.dataset, &s.entry_id)
            .await
            .ok()
            .flatten()
            .and_then(|(json, _)| serde_json::from_str::<Value>(&json).ok());
        entries.insert(key.clone(), entry);
    }
    let Some(entry) = entries[&key].as_ref() else {
        return Value::Null;
    };
    match Kind::parse(&s.kind) {
        Some(Kind::Entry) => entry.clone(),
        Some(kind) => crate::proposal::find_part(entry, kind, &s.item_id)
            .cloned()
            .unwrap_or(Value::Null),
        None => Value::Null,
    }
}

pub async fn inbox<S: Store + ReviewStore>(
    status: Option<String>,
    by: &Principal,
    store: &S,
) -> ApiResponse {
    let status = status.unwrap_or_else(|| "open".into());
    if !matches!(status.as_str(), "open" | "accepted" | "declined") {
        return error(400, "status is open, accepted or declined");
    }
    let suggestions = tri!(store.inbox(&status, &by.email).await.map_err(unavailable));
    let mut entries = BTreeMap::new();
    let mut out = Vec::with_capacity(suggestions.len());
    for s in suggestions {
        let current = current_json(store, &mut entries, &s).await;
        let mut value = json!(s);
        value["current"] = current;
        out.push(value);
    }
    ok(200, json!({ "suggestions": out }))
}

/// The warning for accepting the removal of a whole verb or word, which app data points at.
fn removal_warning(s: &Suggestion) -> Option<String> {
    let whole = s.action == "delete"
        && s.kind == "entry"
        && matches!(s.dataset.as_str(), "verbs" | "words");
    whole.then(|| {
        format!(
            "Saved favourites, quiz history and widgets that point at {} will be dropped when this is exported.",
            s.item_title
        )
    })
}

pub async fn decide<S: Store + ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: DecideBody = tri!(parse(body));
    let accept = match body.decision.as_str() {
        "accept" => true,
        "decline" => false,
        _ => return error(400, "decision is accept or decline"),
    };
    let reply = tri!(text_field(body.reply.as_deref().unwrap_or(""), "reply"));
    let s = match store.suggestion(body.id, &by.email).await {
        Ok(Some(s)) => s,
        Ok(None) => return error(404, "no such suggestion"),
        Err(e) => return unavailable(e),
    };
    if s.status != "open" {
        return error(409, DECIDED);
    }
    let edits = body.edits.filter(|e| !e.is_empty());
    let mut warning = None;
    let (mut admin_edit, mut furigana, mut base) = (None, None, None);
    if s.action == "add" {
        if accept {
            if s.gone {
                return error(404, crate::add_routes::PARENT_GONE);
            }
            if let Some(edits) = &edits {
                let (p, f) = tri!(
                    crate::add_routes::rebuild(store, &s, edits, body.furigana.as_ref()).await
                );
                (admin_edit, furigana) = (Some(p), f);
            }
        } else if edits.is_some() || body.furigana.is_some() {
            return error(400, "only an accept carries edits or readings");
        }
    } else if accept {
        if let Some(edits) = &edits {
            // An accepted removal with the owner's edit would leave export guessing which one wins.
            if s.action == "delete" {
                return error(
                    400,
                    "a removal can't be edited; decline it and suggest a change instead",
                );
            }
            let (file, kind, t) = tri!(target(&s.dataset, &s.kind, &s.item_id));
            let (hash, entry_id, _) = tri!(loaded_target(store, &t).await);
            base = Some(hash);
            let (p, f, _) = tri!(
                proposed_change(
                    store,
                    file,
                    kind,
                    &t,
                    &entry_id,
                    edits,
                    body.furigana.as_ref()
                )
                .await
            );
            (admin_edit, furigana) = (Some(p), f);
        } else if s.action == "change" && s.gone {
            return error(404, NOT_LOADED_ITEM);
        } else if s.action == "change" && s.stale {
            return error(409, ACCEPT_STALE);
        }
        warning = removal_warning(&s);
        if let Some(text) = &warning {
            if !body.confirm {
                return error(400, text);
            }
        }
    } else if edits.is_some() || body.furigana.is_some() {
        return error(400, "only an accept carries edits or readings");
    }
    match store
        .decide(
            s.id,
            accept,
            OwnerEdit {
                item_json: admin_edit.as_deref(),
                furigana_json: furigana.as_deref(),
                base_hash: base.as_deref(),
            },
            &by.email,
            now,
        )
        .await
    {
        Ok(()) => {}
        Err(StoreError::Conflict) => return error(409, DECIDED),
        Err(StoreError::NotFound) => return error(404, "no such suggestion"),
        Err(e) => return unavailable(e),
    }
    if !reply.is_empty() {
        tri!(store
            .add_comment(s.id, &reply, &by.email, now)
            .await
            .map_err(unavailable));
    }
    let mut response = suggestion_response(store, s.id, &by.email, 200).await;
    if let Some(text) = warning {
        response.body["warning"] = json!(text);
    }
    response
}
