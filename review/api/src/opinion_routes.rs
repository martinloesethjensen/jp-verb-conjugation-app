//! Second opinions: a teacher or the owner asks one person which of an item's open suggestions reads
//! better. `app::handle` has already checked who is asking and the `Origin`; these check the body, the
//! target and the people involved. Emails never leave the Worker: people are named or numbered.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::review_routes::{loaded_target, ok, target, text_field, tri, unavailable};
use crate::review_store::{ReviewStore, Suggestion, Target};
use crate::store::StoreError;
use serde::Deserialize;
use serde_json::json;

const NOT_ASKER: &str = "only teachers and the owner can ask for an opinion";
const ALREADY_ASKED: &str = "someone was already asked about this item";
const NOTHING_OPEN: &str = "nothing open to give an opinion on";
const NO_SUCH_REVIEWER: &str = "no such reviewer";
const DECIDED: &str = "already decided";
const CLOSED: &str = "that request was already answered or cancelled";
const OWN_PICK: &str = "you can't pick your own suggestion";

fn may_ask(by: &Principal) -> Result<(), ApiResponse> {
    if by.role.can_ask_opinion() {
        Ok(())
    } else {
        Err(error(403, NOT_ASKER))
    }
}

/// The item's open suggestions an opinion is about: changes, removals and additions, not notes.
async fn open_suggestions<S: ReviewStore>(
    store: &S,
    t: &Target,
    entry_id: &str,
    viewer: &str,
) -> Result<Vec<Suggestion>, ApiResponse> {
    let (_, all) = store
        .entry_review(&t.dataset, entry_id, viewer)
        .await
        .map_err(unavailable)?;
    Ok(all
        .into_iter()
        .filter(|s| {
            s.status == "open" && s.action != "note" && s.kind == t.kind && s.item_id == t.item_id
        })
        .collect())
}

// --- GET /api/opinion/candidates ----------------------------------------------------------------

pub async fn candidates<S: ReviewStore>(
    dataset: Option<String>,
    kind: Option<String>,
    id: Option<String>,
    by: &Principal,
    store: &S,
) -> ApiResponse {
    tri!(may_ask(by));
    let (Some(dataset), Some(kind), Some(id)) = (dataset, kind, id) else {
        return error(400, "which item? (dataset, kind and id)");
    };
    let (_, _, t) = tri!(target(&dataset, &kind, &id));
    let list = tri!(store
        .opinion_candidates(&t, &by.email)
        .await
        .map_err(unavailable));
    ok(200, json!({ "candidates": list }))
}

// --- POST /api/opinion/ask ----------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AskBody {
    dataset: String,
    kind: String,
    id: String,
    user: i64,
    question: String,
}

pub async fn ask<S: ReviewStore>(body: &[u8], by: &Principal, store: &S, now: &str) -> ApiResponse {
    tri!(may_ask(by));
    let body: AskBody = tri!(parse(body));
    let question = tri!(text_field(&body.question, "the question"));
    let (_, _, t) = tri!(target(&body.dataset, &body.kind, &body.id));
    let (_, entry_id, _) = tri!(loaded_target(store, &t).await);
    if tri!(open_suggestions(store, &t, &entry_id, &by.email).await).is_empty() {
        return error(409, NOTHING_OPEN);
    }
    let asked = tri!(store.user_by_number(body.user).await.map_err(unavailable));
    let Some((email, _, true)) = asked else {
        return error(400, NO_SUCH_REVIEWER);
    };
    if email == by.email {
        return error(400, "you can't ask yourself");
    }
    // The candidates leave out the authors of the item's open suggestions.
    let candidates = tri!(store
        .opinion_candidates(&t, &by.email)
        .await
        .map_err(unavailable));
    if !candidates.iter().any(|c| c.user == body.user) {
        return error(400, "they wrote one of these suggestions");
    }
    match store
        .ask_opinion(&t, &email, &question, &by.email, now)
        .await
    {
        Ok(id) => ok(201, json!({ "id": id })),
        Err(StoreError::Conflict) => error(409, ALREADY_ASKED),
        Err(e) => unavailable(e),
    }
}

// --- POST /api/opinion/cancel -------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CancelBody {
    id: i64,
}

pub async fn cancel<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: CancelBody = tri!(parse(body));
    let Some(request) = tri!(store.opinion(body.id, &by.email).await.map_err(unavailable)) else {
        return error(404, "no such request");
    };
    if !request.mine_asked {
        return error(403, "only the person who asked can cancel");
    }
    if request.closed_at.is_some() {
        return error(409, DECIDED);
    }
    match store.cancel_opinion(body.id, &by.email, now).await {
        Ok(()) => ok(200, json!({})),
        Err(StoreError::NotFound) => error(409, CLOSED),
        Err(StoreError::Conflict) => error(403, "only the person who asked can cancel"),
        Err(e) => unavailable(e),
    }
}

// --- POST /api/opinion/answer -------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AnswerBody {
    id: i64,
    pick: Option<i64>,
    body: String,
}

pub async fn answer<S: ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: AnswerBody = tri!(parse(body));
    let text = tri!(text_field(&body.body, "the answer"));
    let Some(request) = tri!(store.opinion(body.id, &by.email).await.map_err(unavailable)) else {
        return error(404, "no such request");
    };
    if !request.mine_to_answer {
        return error(403, "only the person asked can answer");
    }
    if request.answered_at.is_some() || request.cancelled_at.is_some() {
        return error(409, CLOSED);
    }
    // Closed with the item's last open suggestion: the item was decided.
    if request.closed_at.is_some() {
        return error(409, DECIDED);
    }
    if !request.waiting {
        return error(409, DECIDED);
    }
    match body.pick {
        None if text.is_empty() => return error(400, "say why neither works"),
        Some(pick) => {
            let t = Target {
                dataset: request.dataset.clone(),
                kind: request.kind.clone(),
                item_id: request.item_id.clone(),
            };
            let open = tri!(open_suggestions(store, &t, &request.entry_id, &by.email).await);
            match open.iter().find(|s| s.id == pick) {
                None => return error(400, "pick one of the open suggestions"),
                Some(s) if s.mine => return error(400, OWN_PICK),
                Some(_) => {}
            }
        }
        None => {}
    }
    match store
        .answer_opinion(body.id, body.pick, &text, &by.email, now)
        .await
    {
        Ok(()) => ok(200, json!({})),
        Err(StoreError::NotFound) => error(409, CLOSED),
        Err(StoreError::Conflict) => error(400, "pick one of the open suggestions"),
        Err(e) => unavailable(e),
    }
}
