//! The owner's stamps: a fully approved entry becomes a `review` stamp at the next export. A reviewer's
//! approval alone never changes the app (spec, question 1); the stamp names the most senior reviewer involved.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::data::DataFile;
use crate::items::Kind;
use crate::review_routes::{loaded_target, ok, target, tri, unavailable};
use crate::review_store::{NewStamp, ReviewStore, Target};
use serde::Deserialize;
use serde_json::json;

pub const NOT_STAMPABLE: &str = "only counters and grammar points take a stamp for now";
pub const NEEDS_APPROVALS: &str = "every part needs an approval first";
pub const OPEN_SUGGESTIONS: &str = "settle its open suggestions first";

/// What the data pipeline stamps today (`update_data.check_reviews`). Plan 7 adds verbs, words and examples.
pub fn stampable(file: DataFile, kind: Kind) -> bool {
    kind == Kind::Entry && matches!(file, DataFile::Counters | DataFile::Grammar)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct EntryBody {
    dataset: String,
    id: String,
}

/// The entry's target, refusing what can't be stamped.
fn stamp_target(body: &[u8]) -> Result<Target, ApiResponse> {
    let body: EntryBody = parse(body)?;
    let (file, kind, t) = target(&body.dataset, "entry", &body.id)?;
    if !stampable(file, kind) {
        return Err(error(400, NOT_STAMPABLE));
    }
    Ok(t)
}

/// Who a stamp of the entry would name, `(email, public role)`, or the 409 that says why it can't be stamped.
pub(crate) async fn ready<S: ReviewStore>(
    store: &S,
    dataset: &str,
    entry_id: &str,
) -> Result<(String, String), ApiResponse> {
    let r = store
        .stamp_readiness(dataset, entry_id)
        .await
        .map_err(unavailable)?;
    let (Some(reviewer), Some(role)) = (r.reviewer, r.reviewer_role) else {
        return Err(error(409, NEEDS_APPROVALS));
    };
    if r.missing > 0 {
        return Err(error(409, NEEDS_APPROVALS));
    }
    if r.open > 0 {
        return Err(error(409, OPEN_SUGGESTIONS));
    }
    Ok((reviewer, role))
}

pub async fn stamp<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let t = tri!(stamp_target(body));
    let (hash, entry_id, title) = tri!(loaded_target(store, &t).await);
    if let Some(existing) = tri!(store.pending_stamp(&t).await.map_err(unavailable)) {
        return ok(200, json!(existing));
    }
    let (reviewer, by_role) = tri!(ready(store, &t.dataset, &entry_id).await);
    let new = NewStamp {
        target: t.clone(),
        entry_id,
        item_title: title,
        content_hash: hash,
        by_role,
        reviewer,
    };
    tri!(store
        .add_stamp(&new, &by.email, now)
        .await
        .map_err(unavailable));
    match store.pending_stamp(&t).await {
        Ok(Some(made)) => ok(201, json!(made)),
        Ok(None) => error(500, "the database is unavailable"),
        Err(e) => unavailable(e),
    }
}

pub async fn withdraw<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let t = tri!(stamp_target(body));
    match store.withdraw_stamp(&t, &by.email, now).await {
        Ok(true) => ok(200, json!({ "withdrawn": true })),
        Ok(false) => error(404, "there is no stamp waiting for export on that"),
        Err(e) => unavailable(e),
    }
}

pub async fn ready_list<S: ReviewStore>(store: &S) -> ApiResponse {
    match store.ready_to_stamp().await {
        Ok(entries) => ok(200, json!({ "entries": entries })),
        Err(e) => unavailable(e),
    }
}
