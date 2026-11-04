//! The API: one function from a request to a response, so every rule is tested natively. The Worker glue
//! only translates to and from workers-rs.
//!
//! Order of checks: the Access token (401), the route (404), the method (405), who is asking (403), the
//! `Origin` of anything that changes state (403), then the body (400). A route not in `ROUTES` doesn't exist.

use crate::access::{verify, AccessConfig, Jwk};
use crate::auth::{authorize, normalize_email, Need, Principal};
use crate::data::DataFile;
use crate::items::extract;
use crate::manifest::{self, TRUSTED_KEYS};
use crate::source::Source;
use crate::store::{NewUser, Role, SnapshotFile, Store, StoreError};
use serde::Deserialize;
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
    LoadFile,
    Me,
    Rename,
    ListUsers,
    AddUser,
    SetActive,
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
        path: "/api/admin/snapshot",
        need: Need::Admin,
        handler: Handler::LoadFile,
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
];

pub const MAX_DISPLAY_NAME: usize = 40;

fn error(status: u16, message: &str) -> ApiResponse {
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

pub async fn handle<S: Store, R: Source>(
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
        Handler::LoadFile => load_file(&req.body, &principal, store, source, today).await,
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

fn parse<T: for<'de> Deserialize<'de>>(body: &[u8]) -> Result<T, ApiResponse> {
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

async fn items<S: Store>(query: &str, store: &S) -> ApiResponse {
    let file = match browsable(query) {
        Ok(file) => file,
        Err(response) => return response,
    };
    let snapshot = match loaded(store, file).await {
        Ok(snapshot) => snapshot,
        Err(response) => return response,
    };
    match store.entries(file.name()).await {
        Ok(items) => ApiResponse {
            status: 200,
            body: json!({ "dataset": file.name(), "version": snapshot.version, "items": items }),
        },
        Err(e) => store_error(e),
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
    ApiResponse {
        status: 200,
        body: json!({ "readings": readings, "forms": forms }),
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LoadFileBody {
    file: String,
}

async fn load_file<S: Store, R: Source>(
    body: &[u8],
    by: &Principal,
    store: &S,
    source: &R,
    today: &str,
) -> ApiResponse {
    let body: LoadFileBody = match parse(body) {
        Ok(body) => body,
        Err(response) => return response,
    };
    let Some(file) = DataFile::parse_name(&body.file) else {
        return error(400, "unknown data file");
    };
    match import_file(file, store, source, &by.email, today).await {
        Ok(snapshot) => ApiResponse {
            status: 200,
            body: json!(snapshot),
        },
        Err(message) => error(502, &message),
    }
}

/// Loads one published file into the snapshot, checked against the signed manifest. The error is
/// the message the owner sees; on error the previous snapshot of that file stays as it was.
pub async fn import_file<S: Store, R: Source>(
    file: DataFile,
    store: &S,
    source: &R,
    actor: &str,
    now: &str,
) -> Result<SnapshotFile, String> {
    import_file_with_keys(file, store, source, TRUSTED_KEYS, actor, now).await
}

/// `import_file` with the trusted keys as a parameter, for tests that sign with their own key.
pub async fn import_file_with_keys<S: Store, R: Source>(
    file: DataFile,
    store: &S,
    source: &R,
    keys: &[&str],
    actor: &str,
    now: &str,
) -> Result<SnapshotFile, String> {
    const FETCH: &str = "couldn't fetch the published data; try again in a minute";
    let name = file.file_name();
    let manifest_bytes = source
        .get(&manifest::manifest_url())
        .await
        .map_err(|_| FETCH.to_string())?;
    let signature = source
        .get(&manifest::signature_url())
        .await
        .map_err(|_| FETCH.to_string())?;
    let signature = String::from_utf8_lossy(&signature);
    let manifest = manifest::verify(&manifest_bytes, &signature, keys).map_err(|e| match e {
        manifest::ManifestError::BadSignature => {
            "the published manifest isn't signed by Martin's key".to_string()
        }
        _ => "the published manifest is malformed".to_string(),
    })?;
    let entry = manifest
        .entry(file)
        .ok_or_else(|| format!("the manifest has no entry for {name}"))?;
    let url = manifest::file_url(file, &entry)
        .map_err(|_| format!("the manifest has an invalid ref for {name}"))?;
    let bytes = source.get(&url).await.map_err(|_| FETCH.to_string())?;
    if manifest::sha256_hex(&bytes) != entry.sha256 {
        return Err(format!(
            "{name} doesn't match its signed manifest; try again in a minute"
        ));
    }
    if let Some(current) = store
        .snapshot_file(file.name())
        .await
        .map_err(|_| "the database is unavailable".to_string())?
    {
        if manifest::is_older(&entry.version, &current.version) {
            return Err(format!(
                "{name} {} is older than the loaded {}",
                entry.version, current.version
            ));
        }
    }
    let rows =
        extract(file, &bytes).map_err(|e| format!("{name} doesn't fit the data schema: {e}"))?;
    let json = if file.is_browsable() {
        None
    } else {
        Some(String::from_utf8(bytes.clone()).map_err(|_| format!("{name} isn't UTF-8"))?)
    };
    let snapshot = SnapshotFile {
        name: file.name().to_string(),
        version: entry.version,
        sha256: entry.sha256,
        git_ref: entry.git_ref,
        item_count: rows.len() as u32,
        imported_at: now.to_string(),
        imported_by: actor.to_string(),
    };
    store
        .replace_snapshot(&snapshot, json.as_deref(), &rows, actor, now)
        .await
        .map_err(|_| "couldn't save the data; the previous version is still loaded".to_string())?;
    Ok(snapshot)
}
