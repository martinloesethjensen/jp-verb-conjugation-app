//! Suggesting new items: `POST /api/add` and `GET /api/additions`, and what `decide` needs to accept an
//! addition with the owner's edits. Shares its checks with the review routes.

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::data::DataFile;
use crate::items::Kind;
use crate::proposal::{
    add_fields_of, add_title, build_add, check_furigana, find_part, random_stable_id,
    stable_ids_of, AddError, Taken,
};
use crate::review_routes::{
    loaded_target, ok, reference_sets, suggestion_response, target, text_field, tri, unavailable,
    NOT_LOADED_ITEM,
};
use crate::review_store::{NewSuggestion, ReviewStore, Suggestion, Target};
use crate::store::Store;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};

pub const PARENT_GONE: &str = "the place this was added to isn't in the loaded data";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ParentRef {
    kind: String,
    id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AddBody {
    dataset: String,
    kind: String,
    #[serde(default)]
    parent: Option<ParentRef>,
    fields: Map<String, Value>,
    #[serde(default)]
    furigana: Option<BTreeMap<String, String>>,
    #[serde(default)]
    comment: Option<String>,
}

/// A loaded parent: its JSON, its kind and its entry's id. 404 when it isn't loaded.
async fn parent_of<S: Store + ReviewStore>(
    store: &S,
    dataset: &str,
    kind: &str,
    id: &str,
) -> Result<(Value, Kind, String), ApiResponse> {
    let (_, parent_kind, t) = target(dataset, kind, id)?;
    let (_, entry_id, _) = loaded_target(store, &t).await?;
    let (json, _) = store
        .entry(dataset, &entry_id)
        .await
        .map_err(unavailable)?
        .ok_or_else(|| error(404, NOT_LOADED_ITEM))?;
    let entry: Value =
        serde_json::from_str(&json).map_err(|_| error(500, "the database is unavailable"))?;
    let value = if parent_kind == Kind::Entry {
        entry
    } else {
        find_part(&entry, parent_kind, id)
            .cloned()
            .ok_or_else(|| error(404, NOT_LOADED_ITEM))?
    };
    Ok((value, parent_kind, entry_id))
}

/// How an id is used, from the dataset's loaded ids and addition ids. `own` ids (an addition being
/// rebuilt keeps its ids) count as free.
fn taken_by<'a>(
    loaded: &'a BTreeSet<String>,
    suggested: &'a BTreeSet<String>,
    own: &'a [String],
) -> impl Fn(&str) -> Taken + 'a {
    move |id| {
        if own.iter().any(|o| o == id) {
            Taken::Free
        } else if loaded.contains(id) {
            Taken::Loaded
        } else if suggested.contains(id) {
            Taken::Suggested
        } else {
            Taken::Free
        }
    }
}

fn add_error(e: AddError) -> ApiResponse {
    match e {
        AddError::Invalid(message) => error(400, &message),
        AddError::Conflict { message, .. } => error(409, &message),
    }
}

/// Checked readings for new kanji, as JSON, or `None` when there are none.
fn readings_json(
    furigana: Option<&BTreeMap<String, String>>,
    known: &BTreeMap<String, String>,
) -> Result<Option<String>, ApiResponse> {
    match furigana.filter(|f| !f.is_empty()) {
        Some(add) => {
            check_furigana(add, known).map_err(|message| error(400, &message))?;
            Ok(Some(serde_json::to_string(add).unwrap_or_default()))
        }
        None => Ok(None),
    }
}

pub async fn add<S: Store + ReviewStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: AddBody = tri!(parse(body));
    let (file, kind, _) = tri!(target(&body.dataset, &body.kind, ""));
    let parent = match &body.parent {
        Some(p) => Some(tri!(parent_of(store, &body.dataset, &p.kind, &p.id).await)),
        None => None,
    };
    let (loaded, suggested) = tri!(store.ids_taken(&body.dataset).await.map_err(unavailable));
    let (form_ids, readings) = tri!(reference_sets(store).await);
    let taken = taken_by(&loaded, &suggested, &[]);
    let built = build_add(
        file,
        kind,
        parent.as_ref().map(|(value, k, _)| (value, *k)),
        &body.fields,
        &form_ids,
        &mut random_stable_id,
        &taken,
    );
    let new = match built {
        Ok(new) => new,
        // A double tap on a new entry: the reviewer's own open addition of the same id comes back.
        Err(AddError::Conflict { message, id }) if suggested.contains(&id) => {
            if let Ok(Some(existing)) = store.open_add_for(&body.dataset, kind.as_str(), &id).await
            {
                if let Ok(Some(s)) = store.suggestion(existing, &by.email).await {
                    if s.mine {
                        return ok(200, json!(s));
                    }
                }
            }
            return error(409, &message);
        }
        Err(e) => return add_error(e),
    };
    let furigana_json = tri!(readings_json(body.furigana.as_ref(), &readings));
    let comment = tri!(text_field(body.comment.as_deref().unwrap_or(""), "comment"));
    let entry_id = parent
        .as_ref()
        .map(|(_, _, entry_id)| entry_id.clone())
        .unwrap_or_else(|| new.item_id.clone());
    let suggestion = NewSuggestion {
        action: "add".into(),
        target: Target {
            dataset: body.dataset.clone(),
            kind: body.kind.clone(),
            item_id: new.item_id.clone(),
        },
        entry_id,
        item_title: add_title(file, kind, &new.item),
        base_hash: String::new(),
        proposed_json: Some(new.item.to_string()),
        furigana_json,
        dropped_blanks: 0,
        comment,
        parent_kind: body.parent.as_ref().map(|p| p.kind.clone()),
        parent_id: body.parent.as_ref().map(|p| p.id.clone()),
        fingerprint: Some(new.fingerprint),
    };
    let (id, created) = tri!(store
        .add_suggestion(&suggestion, &by.email, now)
        .await
        .map_err(unavailable));
    suggestion_response(store, id, &by.email, if created { 201 } else { 200 }).await
}

pub async fn additions<S: ReviewStore>(
    dataset: Option<String>,
    by: &Principal,
    store: &S,
) -> ApiResponse {
    let file = tri!(dataset
        .as_deref()
        .and_then(DataFile::parse_name)
        .filter(|f| f.is_browsable())
        .ok_or_else(|| error(400, "unknown dataset")));
    match store.additions(file.name(), &by.email).await {
        Ok(suggestions) => ok(200, json!({ "suggestions": suggestions })),
        Err(e) => unavailable(e),
    }
}

/// An addition rebuilt with the owner's edits, keeping its ids: `(item_json, furigana_json)`.
pub(crate) async fn rebuild<S: Store + ReviewStore>(
    store: &S,
    s: &Suggestion,
    edits: &Map<String, Value>,
    furigana: Option<&BTreeMap<String, String>>,
) -> Result<(String, Option<String>), ApiResponse> {
    let (file, kind, _) = target(&s.dataset, &s.kind, "")?;
    let proposed = s
        .proposed
        .as_ref()
        .ok_or_else(|| error(409, "this suggestion has nothing to edit"))?;
    let parent = match (&s.parent_kind, &s.parent_id) {
        (Some(k), Some(id)) => Some(
            parent_of(store, &s.dataset, k, id)
                .await
                .map_err(|_| error(404, PARENT_GONE))?,
        ),
        _ => None,
    };
    let mut fields = add_fields_of(file, kind, proposed);
    for (key, value) in edits {
        fields.insert(key.clone(), value.clone());
    }
    let mut own = stable_ids_of(file, kind, proposed);
    let mut next = own.clone().into_iter();
    own.push(s.item_id.clone());
    let (loaded, suggested) = store.ids_taken(&s.dataset).await.map_err(unavailable)?;
    let (form_ids, readings) = reference_sets(store).await?;
    let taken = taken_by(&loaded, &suggested, &own);
    let new = build_add(
        file,
        kind,
        parent.as_ref().map(|(value, k, _)| (value, *k)),
        &fields,
        &form_ids,
        &mut || next.next().unwrap_or_else(random_stable_id),
        &taken,
    )
    .map_err(add_error)?;
    let furigana_json = readings_json(furigana, &readings)?;
    Ok((new.item.to_string(), furigana_json))
}
