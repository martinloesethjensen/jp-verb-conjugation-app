//! The API: one function from a request to a response, so every rule is tested natively. The Worker glue
//! only translates to and from workers-rs.
//!
//! Order of checks: the Access token (401), the route (404), the method (405), who is asking (403), the
//! `Origin` of anything that changes state (403), then the body (400). A route not in `ROUTES` doesn't exist.

use crate::access::{verify, AccessConfig, Jwk};
use crate::auth::{authorize, normalize_email, Need, Principal};
use crate::store::{NewUser, Role, Store, StoreError};
use serde::Deserialize;
use serde_json::{json, Value};

pub struct ApiRequest {
    pub method: String,
    pub path: String,
    pub origin: Option<String>,
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

pub async fn handle<S: Store>(
    req: ApiRequest,
    cfg: &AppConfig,
    keys: &[Jwk],
    store: &S,
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
