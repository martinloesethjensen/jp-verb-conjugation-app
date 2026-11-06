//! The API: one function from a request to a response, so every rule is tested natively. The Worker glue
//! only translates to and from workers-rs.
//!
//! Order of checks: the Access token (401), the route (404), the method (405), who is asking (403), the
//! `Origin` of anything that changes state (403), then the body (400). A route not in `ROUTES` doesn't exist.

use crate::access::{verify, AccessConfig, Jwk};
use crate::auth::{authorize, normalize_email, Need, Principal};
use crate::data::DataFile;
use crate::items::{extract_slice, slices};
use crate::manifest::{self, TRUSTED_KEYS};
use crate::review_routes::{self, QueueItemAction};
use crate::review_store::ReviewStore;
use crate::source::Source;
use crate::store::{NewUser, Role, SnapshotFile, SnapshotLoad, Store, StoreError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub struct ApiRequest {
    pub method: String,
    pub path: String,
    pub origin: Option<String>,
    /// The raw query string, without `?`.
    pub query: String,
    /// The `Cf-Access-Jwt-Assertion` header.
    pub jwt: Option<String>,
    pub body: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ApiResponse {
    pub status: u16,
    pub body: Value,
}

pub struct AppConfig {
    pub access: AccessConfig,
    /// `https://review.martinloeseth.dev`; state-changing requests must come from it.
    pub site_origin: String,
}

#[derive(Clone, Copy)]
enum Handler {
    Snapshot,
    Items,
    Item,
    Reference,
    LoadBegin,
    LoadSlice,
    LoadFinish,
    Me,
    Rename,
    ListUsers,
    AddUser,
    SetActive,
    Review,
    Approve,
    WithdrawApproval,
    Suggest,
    WithdrawSuggestion,
    Comment,
    Queues,
    Queue,
    Skip,
    AdminQueues,
    PreviewQueue,
    CreateQueue,
    UpdateQueue,
    QueueNote,
    RemoveQueueItem,
    Inbox,
    Decide,
}

struct Route {
    method: &'static str,
    path: &'static str,
    need: Need,
    handler: Handler,
}

/// Every route and what it needs. The single place access is declared.
const ROUTES: &[Route] = &[
    Route {
        method: "GET",
        path: "/api/snapshot",
        need: Need::Reviewer,
        handler: Handler::Snapshot,
    },
    Route {
        method: "GET",
        path: "/api/items",
        need: Need::Reviewer,
        handler: Handler::Items,
    },
    Route {
        method: "GET",
        path: "/api/item",
        need: Need::Reviewer,
        handler: Handler::Item,
    },
    Route {
        method: "GET",
        path: "/api/reference",
        need: Need::Reviewer,
        handler: Handler::Reference,
    },
    Route {
        method: "POST",
        path: "/api/admin/snapshot/begin",
        need: Need::Admin,
        handler: Handler::LoadBegin,
    },
    Route {
        method: "POST",
        path: "/api/admin/snapshot/slice",
        need: Need::Admin,
        handler: Handler::LoadSlice,
    },
    Route {
        method: "POST",
        path: "/api/admin/snapshot/finish",
        need: Need::Admin,
        handler: Handler::LoadFinish,
    },
    Route {
        method: "GET",
        path: "/api/me",
        need: Need::Reviewer,
        handler: Handler::Me,
    },
    Route {
        method: "POST",
        path: "/api/me/name",
        need: Need::Reviewer,
        handler: Handler::Rename,
    },
    Route {
        method: "GET",
        path: "/api/admin/users",
        need: Need::Admin,
        handler: Handler::ListUsers,
    },
    Route {
        method: "POST",
        path: "/api/admin/users",
        need: Need::Admin,
        handler: Handler::AddUser,
    },
    Route {
        method: "POST",
        path: "/api/admin/users/active",
        need: Need::Admin,
        handler: Handler::SetActive,
    },
    Route {
        method: "GET",
        path: "/api/review",
        need: Need::Reviewer,
        handler: Handler::Review,
    },
    Route {
        method: "POST",
        path: "/api/approve",
        need: Need::Reviewer,
        handler: Handler::Approve,
    },
    Route {
        method: "POST",
        path: "/api/approve/withdraw",
        need: Need::Reviewer,
        handler: Handler::WithdrawApproval,
    },
    Route {
        method: "POST",
        path: "/api/suggest",
        need: Need::Reviewer,
        handler: Handler::Suggest,
    },
    Route {
        method: "POST",
        path: "/api/suggest/withdraw",
        need: Need::Reviewer,
        handler: Handler::WithdrawSuggestion,
    },
    Route {
        method: "POST",
        path: "/api/comment",
        need: Need::Reviewer,
        handler: Handler::Comment,
    },
    Route {
        method: "GET",
        path: "/api/queues",
        need: Need::Reviewer,
        handler: Handler::Queues,
    },
    Route {
        method: "GET",
        path: "/api/queue",
        need: Need::Reviewer,
        handler: Handler::Queue,
    },
    Route {
        method: "POST",
        path: "/api/queue/skip",
        need: Need::Reviewer,
        handler: Handler::Skip,
    },
    Route {
        method: "GET",
        path: "/api/admin/queues",
        need: Need::Admin,
        handler: Handler::AdminQueues,
    },
    Route {
        method: "POST",
        path: "/api/admin/queues/preview",
        need: Need::Admin,
        handler: Handler::PreviewQueue,
    },
    Route {
        method: "POST",
        path: "/api/admin/queues",
        need: Need::Admin,
        handler: Handler::CreateQueue,
    },
    Route {
        method: "POST",
        path: "/api/admin/queues/update",
        need: Need::Admin,
        handler: Handler::UpdateQueue,
    },
    Route {
        method: "POST",
        path: "/api/admin/queues/note",
        need: Need::Admin,
        handler: Handler::QueueNote,
    },
    Route {
        method: "POST",
        path: "/api/admin/queues/remove",
        need: Need::Admin,
        handler: Handler::RemoveQueueItem,
    },
    Route {
        method: "GET",
        path: "/api/admin/inbox",
        need: Need::Admin,
        handler: Handler::Inbox,
    },
    Route {
        method: "POST",
        path: "/api/admin/decide",
        need: Need::Admin,
        handler: Handler::Decide,
    },
];

pub const MAX_DISPLAY_NAME: usize = 40;

pub(crate) fn error(status: u16, message: &str) -> ApiResponse {
    ApiResponse {
        status,
        body: json!({ "error": message }),
    }
}

fn store_error(e: StoreError) -> ApiResponse {
    match e {
        StoreError::Conflict => error(409, "that email is already a reviewer"),
        StoreError::NotFound => error(404, "no reviewer has that email"),
        StoreError::Backend(_) => error(500, "the database is unavailable"),
    }
}

pub async fn handle<S: Store + ReviewStore, R: Source>(
    req: ApiRequest,
    cfg: &AppConfig,
    keys: &[Jwk],
    store: &S,
    source: &R,
    now: i64,
    today: &str,
) -> ApiResponse {
    let Some(jwt) = req.jwt.as_deref() else {
        return error(401, "sign in first");
    };
    let Ok((claims, audience)) = verify(jwt, keys, &cfg.access, now) else {
        return error(401, "sign in first");
    };
    let candidates: Vec<&Route> = ROUTES.iter().filter(|r| r.path == req.path).collect();
    if candidates.is_empty() {
        return error(404, "no such endpoint");
    }
    let Some(route) = candidates.into_iter().find(|r| r.method == req.method) else {
        return error(405, "method not allowed");
    };
    let Ok(principal) = authorize(&claims, audience, route.need, store).await else {
        return error(403, "this account can't do that");
    };
    if !matches!(req.method.as_str(), "GET" | "HEAD")
        && req.origin.as_deref() != Some(cfg.site_origin.as_str())
    {
        return error(403, "cross-site request refused");
    }
    match route.handler {
        Handler::Snapshot => snapshot(store).await,
        Handler::Items => items(&req.query, store).await,
        Handler::Item => item(&req.query, store).await,
        Handler::Reference => reference(store).await,
        Handler::LoadBegin => load_begin(&req.body, &principal, store, source, today).await,
        Handler::LoadSlice => load_slice(&req.body, store, source).await,
        Handler::LoadFinish => load_finish(&req.body, &principal, store, source, today).await,
        Handler::Me => me_response(&principal.email, &principal.display_name, principal.role),
        Handler::Rename => rename(&req.body, &principal, store, today).await,
        Handler::ListUsers => match store.users().await {
            Ok(users) => ApiResponse {
                status: 200,
                body: json!({ "users": users }),
            },
            Err(e) => store_error(e),
        },
        Handler::AddUser => add_user(&req.body, &principal, store, today).await,
        Handler::SetActive => set_active(&req.body, &principal, store, today).await,
        Handler::Review => {
            let (dataset, id) = (param(&req.query, "dataset"), param(&req.query, "id"));
            review_routes::review(dataset, id, &principal, store).await
        }
        Handler::Approve => review_routes::approve(&req.body, &principal, store, today).await,
        Handler::WithdrawApproval => {
            review_routes::withdraw_approval(&req.body, &principal, store, today).await
        }
        Handler::Suggest => review_routes::suggest(&req.body, &principal, store, today).await,
        Handler::WithdrawSuggestion => {
            review_routes::withdraw_suggestion(&req.body, &principal, store, today).await
        }
        Handler::Comment => review_routes::comment(&req.body, &principal, store, today).await,
        Handler::Queues => review_routes::list_queues(&principal, store, false).await,
        Handler::Queue => {
            review_routes::get_queue(param(&req.query, "id"), &principal, store).await
        }
        Handler::Skip => {
            review_routes::queue_item(QueueItemAction::Skip, &req.body, &principal, store, today)
                .await
        }
        Handler::AdminQueues => review_routes::list_queues(&principal, store, true).await,
        Handler::PreviewQueue => review_routes::preview_queue(&req.body, store).await,
        Handler::CreateQueue => {
            review_routes::create_queue(&req.body, &principal, store, today).await
        }
        Handler::UpdateQueue => {
            review_routes::update_queue(&req.body, &principal, store, today).await
        }
        Handler::QueueNote => {
            review_routes::queue_item(QueueItemAction::Note, &req.body, &principal, store, today)
                .await
        }
        Handler::RemoveQueueItem => {
            review_routes::queue_item(QueueItemAction::Remove, &req.body, &principal, store, today)
                .await
        }
        Handler::Inbox => {
            review_routes::inbox(param(&req.query, "status"), &principal, store).await
        }
        Handler::Decide => review_routes::decide(&req.body, &principal, store, today).await,
    }
}

fn me_response(email: &str, display_name: &str, role: Role) -> ApiResponse {
    ApiResponse {
        status: 200,
        body: json!({ "email": email, "display_name": display_name, "role": role }),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RenameBody {
    display_name: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AddUserBody {
    email: String,
    display_name: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SetActiveBody {
    email: String,
    active: bool,
}

pub(crate) fn parse<T: for<'de> Deserialize<'de>>(body: &[u8]) -> Result<T, ApiResponse> {
    serde_json::from_slice(body).map_err(|_| error(400, "the request body is not valid"))
}

fn email_field(raw: &str) -> Result<String, ApiResponse> {
    normalize_email(raw).ok_or_else(|| error(400, "that isn't an email address"))
}

async fn user_response<S: Store>(store: &S, email: &str, status: u16) -> ApiResponse {
    match store.user(email).await {
        Ok(Some(user)) => ApiResponse {
            status,
            body: json!(user),
        },
        Ok(None) => store_error(StoreError::NotFound),
        Err(e) => store_error(e),
    }
}

/// Trimmed, 1 to 40 characters.
fn display_name_field(raw: &str) -> Result<String, ApiResponse> {
    let name = raw.trim().to_string();
    let length = name.chars().count();
    if length == 0 || length > MAX_DISPLAY_NAME {
        return Err(error(400, "the display name must be 1 to 40 characters"));
    }
    Ok(name)
}

/// Changes the caller's own site name; the request can't name anyone else.
async fn rename<S: Store>(body: &[u8], by: &Principal, store: &S, today: &str) -> ApiResponse {
    let body: RenameBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    let name = match display_name_field(&body.display_name) {
        Ok(name) => name,
        Err(response) => return response,
    };
    match store
        .set_display_name(&by.email, &name, &by.email, today)
        .await
    {
        Ok(()) => me_response(&by.email, &name, by.role),
        Err(e) => store_error(e),
    }
}

async fn add_user<S: Store>(body: &[u8], by: &Principal, store: &S, today: &str) -> ApiResponse {
    let body: AddUserBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    let email = match email_field(&body.email) {
        Ok(email) => email,
        Err(response) => return response,
    };
    let display_name = match display_name_field(&body.display_name) {
        Ok(name) => name,
        Err(response) => return response,
    };
    let user = NewUser {
        email: email.clone(),
        display_name,
        role: Role::Reviewer,
    };
    match store.add_user(&user, &by.email, today).await {
        Ok(()) => user_response(store, &email, 201).await,
        Err(e) => store_error(e),
    }
}

async fn set_active<S: Store>(body: &[u8], by: &Principal, store: &S, today: &str) -> ApiResponse {
    let body: SetActiveBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    let email = match email_field(&body.email) {
        Ok(email) => email,
        Err(response) => return response,
    };
    if email == by.email {
        return error(400, "you can't deactivate yourself");
    }
    match store
        .set_active(&email, body.active, &by.email, today)
        .await
    {
        Ok(()) => user_response(store, &email, 200).await,
        Err(e) => store_error(e),
    }
}

// --- Published data -----------------------------------------------------------------------------

const NOT_LOADED: &str = "Martin hasn't loaded this data yet.";

fn param(query: &str, name: &str) -> Option<String> {
    form_urlencoded::parse(query.as_bytes())
        .find(|(key, _)| key == name)
        .map(|(_, value)| value.into_owned())
}

fn browsable(query: &str) -> Result<DataFile, ApiResponse> {
    param(query, "dataset")
        .and_then(|name| DataFile::parse_name(&name))
        .filter(|file| file.is_browsable())
        .ok_or_else(|| error(400, "unknown dataset"))
}

async fn loaded<S: Store>(store: &S, file: DataFile) -> Result<SnapshotFile, ApiResponse> {
    match store.snapshot_file(file.name()).await {
        Ok(Some(snapshot)) => Ok(snapshot),
        Ok(None) => Err(error(404, NOT_LOADED)),
        Err(e) => Err(store_error(e)),
    }
}

async fn snapshot<S: Store>(store: &S) -> ApiResponse {
    match store.snapshot_files().await {
        Ok(mut files) => {
            let order = |name: &str| DataFile::ALL.iter().position(|f| f.name() == name);
            files.sort_by_key(|f| order(&f.name));
            ApiResponse {
                status: 200,
                body: json!({ "files": files }),
            }
        }
        Err(e) => store_error(e),
    }
}

async fn items<S: Store + ReviewStore>(query: &str, store: &S) -> ApiResponse {
    let file = match browsable(query) {
        Ok(file) => file,
        Err(response) => return response,
    };
    let snapshot = match loaded(store, file).await {
        Ok(snapshot) => snapshot,
        Err(response) => return response,
    };
    let (entries, counts) = match (
        store.entries(file.name()).await,
        store.review_counts(file.name()).await,
    ) {
        (Ok(entries), Ok(counts)) => (entries, counts),
        (Err(e), _) | (_, Err(e)) => return store_error(e),
    };
    let counts: std::collections::HashMap<String, (u32, u32)> = counts
        .into_iter()
        .map(|(id, approved, open)| (id, (approved, open)))
        .collect();
    let items: Vec<Value> = entries
        .into_iter()
        .map(|item| {
            let (approved, open) = counts.get(&item.item_id).copied().unwrap_or((0, 0));
            let targets = item.parts + 1;
            let mut value = json!(item);
            value["approved"] = json!(approved);
            value["open"] = json!(open);
            value["targets"] = json!(targets);
            value
        })
        .collect();
    ApiResponse {
        status: 200,
        body: json!({ "dataset": file.name(), "version": snapshot.version, "items": items }),
    }
}

async fn item<S: Store>(query: &str, store: &S) -> ApiResponse {
    let file = match browsable(query) {
        Ok(file) => file,
        Err(response) => return response,
    };
    let Some(id) = param(query, "id") else {
        return error(400, "which item? (id is missing)");
    };
    let snapshot = match loaded(store, file).await {
        Ok(snapshot) => snapshot,
        Err(response) => return response,
    };
    match store.entry(file.name(), &id).await {
        Ok(Some((json, content_hash))) => {
            let item: Value = serde_json::from_str(&json).unwrap_or(Value::Null);
            ApiResponse {
                status: 200,
                body: json!({
                    "dataset": file.name(),
                    "version": snapshot.version,
                    "id": id,
                    "content_hash": content_hash,
                    "item": item,
                }),
            }
        }
        Ok(None) => error(404, "no such item"),
        Err(e) => store_error(e),
    }
}

async fn reference<S: Store>(store: &S) -> ApiResponse {
    let stored = |name: &'static str| async move {
        store
            .snapshot_json(name)
            .await
            .ok()
            .flatten()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok())
    };
    let readings = stored("furigana")
        .await
        .map(|doc| doc["readings"].clone())
        .unwrap_or_else(|| json!({}));
    let mut forms = serde_json::Map::new();
    if let Some(doc) = stored("forms").await {
        for form in doc["forms"].as_array().into_iter().flatten() {
            if let (Some(id), Some(label)) = (form["id"].as_str(), form["label"].as_str()) {
                forms.insert(id.to_string(), json!(label));
            }
        }
    }
    let fields: serde_json::Map<String, Value> = crate::proposal::editable_targets()
        .into_iter()
        .map(|(name, fields)| (name, json!(fields)))
        .collect();
    ApiResponse {
        status: 200,
        body: json!({ "readings": readings, "forms": forms, "fields": fields }),
    }
}

// --- Loading published data, one request at a time ----------------------------------------------
//
// Workers Free allows ~10 ms of CPU per request, so a load is begin → one request per slice → finish.
// Every request re-verifies the published file (signature, ref, hash) before trusting anything.

const FETCH_FAILED: &str = "couldn't fetch the published data; try again in a minute";
const NOT_RUNNING: &str = "this load is no longer running; start again";
const CHANGED: &str = "the published data changed while loading; start again";

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BeginBody {
    file: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SliceBody {
    load_id: String,
    slice: u32,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FinishBody {
    load_id: String,
}

/// What `begin` hands the page: how many slice requests to make.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct LoadStarted {
    pub load_id: String,
    pub file: String,
    pub version: String,
    pub slices: usize,
}

/// The signed manifest's entry for `file` and the file's bytes, after checking the signature, the
/// ref and the file's SHA-256 (with the source's hasher: Web Crypto in the Worker).
async fn published<R: Source>(
    file: DataFile,
    source: &R,
    keys: &[&str],
) -> Result<(manifest::Entry, Vec<u8>), String> {
    let name = file.file_name();
    let manifest_bytes = source
        .get(&manifest::manifest_url())
        .await
        .map_err(|_| FETCH_FAILED.to_string())?;
    let signature = source
        .get(&manifest::signature_url())
        .await
        .map_err(|_| FETCH_FAILED.to_string())?;
    let signature = String::from_utf8_lossy(&signature);
    let manifest = manifest::verify(&manifest_bytes, &signature, keys).map_err(|e| match e {
        manifest::ManifestError::BadSignature => {
            // Usually a cache race right after a data PR merges, not tampering: GitHub can serve
            // the new manifest with the old signature for a few minutes.
            "the published manifest doesn't match Martin's signature. Right after a data PR merges, GitHub can briefly serve an old signature; try again in a few minutes".to_string()
        }
        _ => "the published manifest is malformed".to_string(),
    })?;
    let entry = manifest
        .entry(file)
        .ok_or_else(|| format!("the manifest has no entry for {name}"))?;
    let url = manifest::file_url(file, &entry)
        .map_err(|_| format!("the manifest has an invalid ref for {name}"))?;
    let bytes = source
        .get(&url)
        .await
        .map_err(|_| FETCH_FAILED.to_string())?;
    if source.sha256(&bytes).await != entry.sha256 {
        return Err(format!(
            "{name} doesn't match its signed manifest; try again in a minute"
        ));
    }
    Ok((entry, bytes))
}

/// Refuses a version older than the one already loaded (a replayed manifest or a reset branch).
async fn not_older<S: Store>(store: &S, file: DataFile, version: &str) -> Result<(), String> {
    let loaded = store
        .snapshot_file(file.name())
        .await
        .map_err(|_| "the database is unavailable".to_string())?;
    match loaded {
        Some(current) if manifest::is_older(version, &current.version) => Err(format!(
            "{} {version} is older than the loaded {}",
            file.file_name(),
            current.version
        )),
        _ => Ok(()),
    }
}

/// The load `load_id`, with its file re-verified and still the version and hash it began with.
async fn running<S: Store, R: Source>(
    load_id: &str,
    store: &S,
    source: &R,
    keys: &[&str],
) -> Result<(SnapshotLoad, DataFile, Vec<u8>), (u16, String)> {
    let load = store
        .load(load_id)
        .await
        .map_err(|_| (500, "the database is unavailable".to_string()))?
        .ok_or((409, NOT_RUNNING.to_string()))?;
    let file = DataFile::parse_name(&load.name).ok_or((409, NOT_RUNNING.to_string()))?;
    let (entry, bytes) = published(file, source, keys).await.map_err(|e| (502, e))?;
    if entry.version != load.version || entry.sha256 != load.sha256 {
        return Err((409, CHANGED.to_string()));
    }
    Ok((load, file, bytes))
}

/// `<dataset>-<16 random hex digits>`: unique even for two loads begun in the same second.
fn new_load_id(file: DataFile) -> Result<String, String> {
    let mut random = [0u8; 8];
    getrandom::getrandom(&mut random)
        .map_err(|_| "couldn't start the load; try again".to_string())?;
    let hex: String = random.iter().map(|b| format!("{b:02x}")).collect();
    Ok(format!("{}-{hex}", file.name()))
}

/// Starts loading `file`: verifies it, checks its top level, splits it into slices and records the
/// load (discarding any unfinished load of the same file). The error is the owner's message.
pub async fn begin_load<S: Store, R: Source>(
    file: DataFile,
    store: &S,
    source: &R,
    actor: &str,
    now: &str,
) -> Result<LoadStarted, String> {
    begin_load_with_keys(file, store, source, TRUSTED_KEYS, actor, now).await
}

/// `begin_load` with the trusted keys as a parameter, for tests that sign with their own key.
pub async fn begin_load_with_keys<S: Store, R: Source>(
    file: DataFile,
    store: &S,
    source: &R,
    keys: &[&str],
    actor: &str,
    now: &str,
) -> Result<LoadStarted, String> {
    let name = file.file_name();
    let (entry, bytes) = published(file, source, keys).await?;
    not_older(store, file, &entry.version).await?;
    let slices =
        slices(file, &bytes).map_err(|e| format!("{name} doesn't fit the data schema: {e}"))?;
    let load = SnapshotLoad {
        load_id: new_load_id(file)?,
        name: file.name().to_string(),
        version: entry.version.clone(),
        sha256: entry.sha256,
        git_ref: entry.git_ref,
        slices,
        started_by: actor.to_string(),
        started_at: now.to_string(),
    };
    store
        .begin_load(&load)
        .await
        .map_err(|_| "the database is unavailable".to_string())?;
    Ok(LoadStarted {
        load_id: load.load_id,
        file: load.name,
        version: load.version,
        slices: load.slices.len(),
    })
}

/// Loads slice `index` of a running load into staging. Repeating a slice replaces it.
pub async fn load_slice_with_keys<S: Store, R: Source>(
    load_id: &str,
    index: u32,
    store: &S,
    source: &R,
    keys: &[&str],
) -> Result<usize, (u16, String)> {
    let (load, file, bytes) = running(load_id, store, source, keys).await?;
    let slice = load
        .slices
        .get(index as usize)
        .ok_or((400, "no such part of the file".to_string()))?;
    let rows = extract_slice(file, &bytes, slice).map_err(|e| {
        (
            502,
            format!("{} doesn't fit the data schema: {e}", file.file_name()),
        )
    })?;
    store
        .stage_slice(&load, index, &rows)
        .await
        .map_err(|_| (500, "couldn't save this part; try again".to_string()))?;
    Ok(rows.len())
}

/// Swaps a fully staged load in for the dataset's current rows, in one batch.
pub async fn finish_load_with_keys<S: Store, R: Source>(
    load_id: &str,
    store: &S,
    source: &R,
    keys: &[&str],
    actor: &str,
    now: &str,
) -> Result<SnapshotFile, (u16, String)> {
    let (load, file, bytes) = running(load_id, store, source, keys).await?;
    let name = file.file_name();
    let done = store
        .slices_done(load_id)
        .await
        .map_err(|_| (500, "the database is unavailable".to_string()))?;
    if done as usize != load.slices.len() {
        return Err((
            409,
            format!("not every part of {name} was loaded; start again"),
        ));
    }
    not_older(store, file, &load.version)
        .await
        .map_err(|e| (502, e))?;
    let json = if file.is_browsable() {
        None
    } else {
        Some(String::from_utf8(bytes).map_err(|_| (502, format!("{name} isn't UTF-8")))?)
    };
    let snapshot = SnapshotFile {
        name: load.name.clone(),
        version: load.version.clone(),
        sha256: load.sha256.clone(),
        git_ref: load.git_ref.clone(),
        item_count: load.slices.iter().map(|s| s.entries.len() as u32).sum(),
        imported_at: now.to_string(),
        imported_by: actor.to_string(),
    };
    store
        .finish_load(&load, &snapshot, json.as_deref(), actor, now)
        .await
        .map_err(|e| match e {
            StoreError::NotFound => (409, NOT_RUNNING.to_string()),
            _ => (
                500,
                "couldn't save the data; the previous version is still loaded".to_string(),
            ),
        })?;
    Ok(snapshot)
}

async fn load_begin<S: Store, R: Source>(
    body: &[u8],
    by: &Principal,
    store: &S,
    source: &R,
    today: &str,
) -> ApiResponse {
    let body: BeginBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    let Some(file) = DataFile::parse_name(&body.file) else {
        return error(400, "unknown data file");
    };
    match begin_load(file, store, source, &by.email, today).await {
        Ok(started) => ApiResponse {
            status: 200,
            body: json!(started),
        },
        Err(message) => error(502, &message),
    }
}

async fn load_slice<S: Store, R: Source>(body: &[u8], store: &S, source: &R) -> ApiResponse {
    let body: SliceBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    match load_slice_with_keys(&body.load_id, body.slice, store, source, TRUSTED_KEYS).await {
        Ok(rows) => ApiResponse {
            status: 200,
            body: json!({ "load_id": body.load_id, "slice": body.slice, "rows": rows }),
        },
        Err((status, message)) => error(status, &message),
    }
}

async fn load_finish<S: Store, R: Source>(
    body: &[u8],
    by: &Principal,
    store: &S,
    source: &R,
    today: &str,
) -> ApiResponse {
    let body: FinishBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    match finish_load_with_keys(&body.load_id, store, source, TRUSTED_KEYS, &by.email, today).await
    {
        Ok(snapshot) => ApiResponse {
            status: 200,
            body: json!(snapshot),
        },
        Err((status, message)) => error(status, &message),
    }
}
