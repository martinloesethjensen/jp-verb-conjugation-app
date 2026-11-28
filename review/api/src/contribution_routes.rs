//! "Your contributions": the viewer's own approvals and suggestions, grouped by where they stand. Names
//! only: no email leaves the Worker, and nobody else's rows are read.

use crate::app::ApiResponse;
use crate::auth::Principal;
use crate::review_routes::{current_json, ok, tri, unavailable};
use crate::review_store::{Contribution, ReleaseInfo, ReviewStore};
use crate::store::Store;
use serde_json::{json, Value};
use std::collections::BTreeMap;

pub async fn contributions<S: Store + ReviewStore>(by: &Principal, store: &S) -> ApiResponse {
    let all = tri!(store.contributions(&by.email).await.map_err(unavailable));
    let credit = tri!(store.user(&by.email).await.map_err(unavailable));

    let mut entries = BTreeMap::new();
    let mut accepted = Vec::new();
    let mut waiting = Vec::new();
    let mut declined = Vec::new();
    let mut released: Vec<(ReleaseInfo, Vec<Value>)> = Vec::new();
    let mut per_dataset: BTreeMap<String, (u32, u32)> = BTreeMap::new();
    for (dataset, n) in &all.approvals {
        per_dataset.entry(dataset.clone()).or_default().0 = *n;
    }
    let (mut suggested, mut accepted_n, mut live) = (0u32, 0u32, 0u32);
    for c in all.suggestions {
        let s = &c.suggestion;
        suggested += 1;
        per_dataset.entry(s.dataset.clone()).or_default().1 += 1;
        if s.status == "accepted" {
            accepted_n += 1;
        }
        let before = if s.status == "open" || s.status == "declined" {
            // An open suggestion shows the item as it is now; a declined one was never applied, so the
            // current item is its baseline too.
            match current_json(store, &mut entries, s).await {
                Value::Null => None,
                v => Some(v),
            }
        } else {
            c.before.clone()
        };
        let value = change(&c, before);
        match (&c.release, s.status.as_str()) {
            (Some(r), _) => {
                live += 1;
                match released.iter_mut().find(|(known, _)| known.id == r.id) {
                    Some((_, list)) => list.push(value),
                    None => released.push((r.clone(), vec![value])),
                }
            }
            (None, "accepted") => accepted.push(value),
            (None, "open") => waiting.push(value),
            (None, "declined") => declined.push(value),
            _ => {}
        }
    }
    // Newest release first; the backfill row last.
    released.sort_by_key(|(r, _)| (r.earlier, std::cmp::Reverse(r.id)));
    let releases: Vec<Value> = released
        .into_iter()
        .map(|(r, changes)| json!({ "label": r.label, "loaded_at": r.loaded_at, "changes": changes }))
        .collect();
    let datasets: Vec<Value> = per_dataset
        .into_iter()
        .map(|(dataset, (approved, suggested))| {
            json!({ "dataset": dataset, "approved": approved, "suggested": suggested })
        })
        .collect();
    let approved: u32 = all.approvals.iter().map(|(_, n)| n).sum();
    ok(
        200,
        json!({
            "counts": { "approved": approved, "suggested": suggested, "accepted": accepted_n, "live": live },
            "credit": {
                "name": credit.as_ref().and_then(|u| u.public_name.clone()),
                "role": credit.as_ref().map_or("native", |u| u.public_role.as_str()),
            },
            "releases": releases,
            "accepted": accepted,
            "waiting": waiting,
            "declined": declined,
            "datasets": datasets,
        }),
    )
}

/// One change, with the inbox suggestion's fields (no author: it is the viewer's own).
fn change(c: &Contribution, before: Option<Value>) -> Value {
    let s = &c.suggestion;
    json!({
        "id": s.id,
        "action": s.action,
        "dataset": s.dataset,
        "kind": s.kind,
        "item_id": s.item_id,
        "entry_id": s.entry_id,
        "parent_kind": s.parent_kind,
        "parent_id": s.parent_id,
        "item_title": s.item_title,
        "proposed": s.proposed,
        "admin_edit": s.admin_edit,
        "furigana": s.furigana,
        "comment": s.comment,
        "created_at": s.created_at,
        "decided_at": s.decided_at,
        "before": before,
        "replies": c.replies,
        "reason": c.reason,
    })
}
