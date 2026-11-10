//! Reply alerts: what happened in the threads someone is part of, and marking threads read.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::review_routes::{ok, tri, unavailable};
use crate::review_store::ReviewStore;
use serde::Deserialize;
use serde_json::json;

/// How many events the bell and the Replies page show.
pub const REPLIES_SHOWN: u32 = 50;
/// The most threads one request marks read.
pub const MAX_READ_IDS: usize = 200;

pub async fn replies<S: ReviewStore>(by: &Principal, store: &S) -> ApiResponse {
    let (list, unread) = tri!(store
        .replies(&by.email, REPLIES_SHOWN)
        .await
        .map_err(unavailable));
    ok(200, json!({ "unread": unread, "replies": list }))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ReadBody {
    #[serde(default)]
    ids: Option<Vec<i64>>,
    #[serde(default)]
    all: bool,
}

pub async fn read<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: ReadBody = tri!(parse(body));
    let ids = match (body.ids, body.all) {
        (None, true) => tri!(store.unread_threads(&by.email).await.map_err(unavailable)),
        (Some(ids), false) if (1..=MAX_READ_IDS).contains(&ids.len()) => ids,
        _ => return error(400, "send ids (1 to 200 suggestions) or all"),
    };
    tri!(store
        .mark_read(&by.email, &ids, now)
        .await
        .map_err(unavailable));
    let unread = tri!(store.unread_count(&by.email).await.map_err(unavailable));
    ok(200, json!({ "unread": unread }))
}
