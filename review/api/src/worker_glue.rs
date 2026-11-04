//! The Worker entry point: turns a workers-rs request into an `ApiRequest`, keeps the team's keys, and
//! sends `handle`'s answer back. No rule lives here; they are all in `app`, `auth` and `access`.

use crate::access::{parse_certs, token_kid, AccessConfig, KeyCache};
use crate::app::{handle, ApiRequest, ApiResponse, AppConfig};
use crate::d1::D1Store;
use crate::source::Source;
use serde_json::json;
use std::cell::RefCell;
use worker::{
    event, js_sys, Context, Env, Fetch, Headers, Method, Request, RequestInit, Response, Result,
    Url,
};

/// Published files from raw.githubusercontent.com. Only the URLs `manifest.rs` builds are fetched.
struct FetchSource;

impl Source for FetchSource {
    async fn get(&self, url: &str) -> std::result::Result<Vec<u8>, String> {
        let fetch = async {
            let headers = Headers::new();
            headers.set("User-Agent", "kotobatable-review")?;
            let mut init = RequestInit::new();
            init.with_headers(headers);
            let request = Request::new_with_init(url, &init)?;
            let mut response = Fetch::Request(request).send().await?;
            if response.status_code() != 200 {
                return Err(worker::Error::RustError(format!(
                    "{} {url}",
                    response.status_code()
                )));
            }
            response.bytes().await
        };
        fetch.await.map_err(|e| e.to_string())
    }
}

thread_local! {
    static KEYS: RefCell<KeyCache> = RefCell::new(KeyCache::default());
}

fn respond(api: ApiResponse) -> Result<Response> {
    let mut response = Response::from_json(&api.body)?.with_status(api.status);
    let headers = response.headers_mut();
    headers.set("Content-Type", "application/json; charset=utf-8")?;
    headers.set("Cache-Control", "no-store")?;
    headers.set("X-Content-Type-Options", "nosniff")?;
    Ok(response)
}

fn config(env: &Env) -> Option<AppConfig> {
    let secret = |name: &str| env.secret(name).map(|s| s.to_string()).unwrap_or_default();
    Some(AppConfig {
        access: AccessConfig::new(
            &secret("ACCESS_TEAM_DOMAIN"),
            &secret("ACCESS_AUD"),
            &secret("ACCESS_ADMIN_AUD"),
        )?,
        site_origin: env
            .var("SITE_ORIGIN")
            .ok()
            .map(|v| v.to_string())
            .filter(|s| !s.is_empty())?,
    })
}

/// Refreshes the cached keys when `KeyCache::begin_fetch` says so. The claim is made before the fetch is
/// awaited, so concurrent requests don't all fetch; a failed fetch keeps the old keys.
async fn ensure_keys(cfg: &AccessConfig, jwt: Option<&str>, now: i64) {
    let kid = jwt.and_then(|t| token_kid(t).ok()).unwrap_or_default();
    if !KEYS.with(|k| k.borrow_mut().begin_fetch(&kid, now)) {
        return;
    }
    let fetched = async {
        let url = Url::parse(&cfg.certs_url()).ok()?;
        let mut response = Fetch::Url(url).send().await.ok()?;
        if response.status_code() != 200 {
            return None;
        }
        parse_certs(&response.text().await.ok()?).ok()
    }
    .await;
    if let Some(keys) = fetched {
        KEYS.with(|k| k.borrow_mut().store(keys, now));
    }
}

#[event(fetch)]
async fn fetch(mut req: Request, env: Env, _ctx: Context) -> Result<Response> {
    let Some(cfg) = config(&env) else {
        return respond(ApiResponse {
            status: 500,
            body: json!({"error": "the site is not configured"}),
        });
    };
    let now_ms = js_sys::Date::now();
    let now = (now_ms / 1000.0) as i64;
    let today: String = js_sys::Date::new(&now_ms.into()).to_iso_string().into();
    let headers = req.headers();
    let jwt = headers.get("Cf-Access-Jwt-Assertion")?;
    let origin = headers.get("Origin")?;
    let method = req.method();
    let body = match method {
        Method::Get | Method::Head => Vec::new(),
        _ => req.bytes().await.unwrap_or_default(),
    };
    ensure_keys(&cfg.access, jwt.as_deref(), now).await;
    let keys = KEYS.with(|k| k.borrow().keys.clone());
    let api = ApiRequest {
        method: method.to_string(),
        path: req.path(),
        origin,
        query: req.url()?.query().unwrap_or_default().to_string(),
        jwt,
        body,
    };
    let store = D1Store { db: env.d1("DB")? };
    respond(handle(api, &cfg, &keys, &store, &FetchSource, now, &today).await)
}
