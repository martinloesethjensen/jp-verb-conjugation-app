//! Settings and onboarding progress: read them, change one or more at a time.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::review_routes::{ok, tri, unavailable};
use crate::store::{SettingsChange, Store, TIPS};
use serde_json::json;

pub async fn settings<S: Store>(by: &Principal, store: &S) -> ApiResponse {
    let settings = tri!(store.settings(&by.email).await.map_err(unavailable));
    ok(200, json!(settings))
}

pub async fn change<S: Store>(body: &[u8], by: &Principal, store: &S, now: &str) -> ApiResponse {
    let change: SettingsChange = tri!(parse(body));
    if change.is_empty() {
        return error(400, "nothing to change");
    }
    if let Some(tip) = &change.dismiss_tip {
        if !TIPS.contains(&tip.as_str()) {
            return error(400, "no tip has that id");
        }
    }
    let current = tri!(store.settings(&by.email).await.map_err(unavailable));
    let next = current.apply(&change, now);
    tri!(store
        .save_settings(&by.email, &next)
        .await
        .map_err(unavailable));
    ok(200, json!(next))
}
