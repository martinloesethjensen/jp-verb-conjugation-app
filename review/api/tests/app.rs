mod support;

use review_api::app::{handle, ApiRequest, ApiResponse, AppConfig};
use review_api::store::{NewUser, Role, Store};
use serde_json::{json, Value};
use support::source::FakeSource;
use support::sqlite::SqliteStore;
use support::*;

const T0: &str = "2026-10-29T12:00:00Z";
const OWNER: &str = "owner@example.com";
const SITE: &str = "https://review.martinloeseth.dev";
const ADMIN_ROUTES: [(&str, &str); 3] = [
    ("GET", "/api/admin/users"),
    ("POST", "/api/admin/users"),
    ("POST", "/api/admin/users/active"),
];
const ALL_ROUTES: [(&str, &str); 5] = [
    ("GET", "/api/me"),
    ("POST", "/api/me/name"),
    ("GET", "/api/admin/users"),
    ("POST", "/api/admin/users"),
    ("POST", "/api/admin/users/active"),
];

fn app_cfg() -> AppConfig {
    AppConfig {
        access: cfg(),
        site_origin: SITE.into(),
    }
}

async fn seeded() -> SqliteStore {
    let s = SqliteStore::new();
    s.conn
        .borrow()
        .execute(
            "INSERT INTO users (email, display_name, role, active, created_at, public_role) VALUES (?1, 'Martin', 'admin', 1, ?2, 'owner')",
            rusqlite::params![OWNER, T0],
        )
        .unwrap();
    let aiko = NewUser {
        email: "aiko@example.com".into(),
        display_name: "Aiko".into(),
        role: Role::Reviewer,
    };
    s.add_user(&aiko, OWNER, T0).await.unwrap();
    s
}

fn reviewer_token(email: &str) -> String {
    token(rs_header(), claims_for(Some(email), "reviewer-aud"))
}

fn admin_token(email: &str) -> String {
    token(rs_header(), claims_for(Some(email), "admin-aud"))
}

fn req(
    method: &str,
    path: &str,
    jwt: Option<String>,
    origin: Option<&str>,
    body: &str,
) -> ApiRequest {
    ApiRequest {
        method: method.into(),
        path: path.into(),
        origin: origin.map(str::to_string),
        query: String::new(),
        jwt,
        body: body.as_bytes().to_vec(),
    }
}

async fn call(store: &SqliteStore, request: ApiRequest) -> ApiResponse {
    handle(
        request,
        &app_cfg(),
        &[jwk()],
        store,
        &FakeSource::empty(),
        NOW,
        T0,
    )
    .await
}

async fn post_admin(store: &SqliteStore, path: &str, body: Value) -> ApiResponse {
    call(
        store,
        req(
            "POST",
            path,
            Some(admin_token(OWNER)),
            Some(SITE),
            &body.to_string(),
        ),
    )
    .await
}

#[tokio::test(flavor = "current_thread")]
async fn no_token_is_401() {
    let s = seeded().await;
    let response = call(&s, req("GET", "/api/me", None, None, "")).await;
    assert_eq!(response.status, 401);
    assert!(response.body["error"].is_string());
}

#[tokio::test(flavor = "current_thread")]
async fn a_forged_token_is_401() {
    let s = seeded().await;
    let forged = token_signed_by(
        other_key(),
        rs_header(),
        claims_for(Some(OWNER), "admin-aud"),
    );
    assert_eq!(
        call(&s, req("GET", "/api/admin/users", Some(forged), None, ""))
            .await
            .status,
        401
    );
}

#[tokio::test(flavor = "current_thread")]
async fn me_returns_the_signed_in_user() {
    let s = seeded().await;
    let response = call(
        &s,
        req(
            "GET",
            "/api/me",
            Some(reviewer_token("aiko@example.com")),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(response.status, 200);
    assert_eq!(
        response.body,
        json!({"email": "aiko@example.com", "display_name": "Aiko", "role": "reviewer",
               "public_role": "native", "public_name": null})
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_gets_403_on_every_admin_route() {
    let s = seeded().await;
    for jwt in [
        reviewer_token("aiko@example.com"),
        admin_token("aiko@example.com"),
    ] {
        for (method, path) in ADMIN_ROUTES {
            let response = call(&s, req(method, path, Some(jwt.clone()), Some(SITE), "{}")).await;
            assert_eq!(response.status, 403, "{method} {path}");
        }
    }
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_needs_the_admin_application_for_admin_routes() {
    let s = seeded().await;
    let pin = call(
        &s,
        req(
            "GET",
            "/api/admin/users",
            Some(reviewer_token(OWNER)),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(pin.status, 403);
    let passkey = call(
        &s,
        req(
            "GET",
            "/api/admin/users",
            Some(admin_token(OWNER)),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(passkey.status, 200);
    assert_eq!(
        passkey.body,
        json!({"users": [
            {"email": "aiko@example.com", "display_name": "Aiko", "role": "reviewer", "active": true,
             "public_role": "native", "public_name": null},
            {"email": OWNER, "display_name": "Martin", "role": "admin", "active": true,
             "public_role": "owner", "public_name": null},
        ]})
    );
}

#[tokio::test(flavor = "current_thread")]
async fn a_service_token_is_403_everywhere() {
    let s = seeded().await;
    for aud in ["reviewer-aud", "admin-aud"] {
        let jwt = token(rs_header(), claims_for(None, aud));
        for (method, path) in ALL_ROUTES {
            let response = call(&s, req(method, path, Some(jwt.clone()), Some(SITE), "{}")).await;
            assert_eq!(response.status, 403, "{aud} {method} {path}");
        }
    }
}

#[tokio::test(flavor = "current_thread")]
async fn unknown_paths_are_404_only_after_sign_in() {
    let s = seeded().await;
    assert_eq!(
        call(&s, req("GET", "/api/nope", None, None, ""))
            .await
            .status,
        401
    );
    let signed_in = call(
        &s,
        req(
            "GET",
            "/api/nope",
            Some(reviewer_token("aiko@example.com")),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(signed_in.status, 404);
}

#[tokio::test(flavor = "current_thread")]
async fn wrong_method_is_405() {
    let s = seeded().await;
    let response = call(
        &s,
        req(
            "DELETE",
            "/api/me",
            Some(reviewer_token("aiko@example.com")),
            Some(SITE),
            "",
        ),
    )
    .await;
    assert_eq!(response.status, 405);
}

#[tokio::test(flavor = "current_thread")]
async fn posts_need_the_site_origin() {
    let s = seeded().await;
    let body = json!({"email": "ken@example.com", "display_name": "Ken"}).to_string();
    for origin in [
        None,
        Some("https://evil.example"),
        Some("https://review.martinloeseth.dev.evil.example"),
    ] {
        let response = call(
            &s,
            req(
                "POST",
                "/api/admin/users",
                Some(admin_token(OWNER)),
                origin,
                &body,
            ),
        )
        .await;
        assert_eq!(response.status, 403, "{origin:?}");
        assert_eq!(
            response.body,
            json!({"error": "cross-site request refused"})
        );
    }
    let response = call(
        &s,
        req(
            "POST",
            "/api/admin/users",
            Some(admin_token(OWNER)),
            Some(SITE),
            &body,
        ),
    )
    .await;
    assert_eq!(response.status, 201);
}

#[tokio::test(flavor = "current_thread")]
async fn adding_a_reviewer() {
    let s = seeded().await;
    let added = post_admin(
        &s,
        "/api/admin/users",
        json!({"email": " Ken@Example.com ", "display_name": " Ken "}),
    )
    .await;
    assert_eq!(added.status, 201);
    assert_eq!(
        added.body,
        json!({"email": "ken@example.com", "display_name": "Ken", "role": "reviewer", "active": true,
               "public_role": "native", "public_name": null})
    );
    let again = post_admin(
        &s,
        "/api/admin/users",
        json!({"email": "ken@example.com", "display_name": "Ken"}),
    )
    .await;
    assert_eq!(
        (again.status, again.body),
        (409, json!({"error": "that email is already a reviewer"}))
    );
    let as_admin = post_admin(
        &s,
        "/api/admin/users",
        json!({"email": "ken2@example.com", "display_name": "Ken", "role": "admin"}),
    )
    .await;
    assert_eq!(as_admin.status, 400);
    for bad in [
        json!({"email": "ken3@example.com", "display_name": ""}),
        json!({"email": "ken3@example.com", "display_name": "   "}),
        json!({"email": "ken3@example.com", "display_name": "x".repeat(41)}),
        json!({"email": "nope", "display_name": "Ken"}),
        json!({"display_name": "Ken"}),
    ] {
        assert_eq!(
            post_admin(&s, "/api/admin/users", bad.clone()).await.status,
            400,
            "{bad}"
        );
    }
    let not_json = call(
        &s,
        req(
            "POST",
            "/api/admin/users",
            Some(admin_token(OWNER)),
            Some(SITE),
            "not json",
        ),
    )
    .await;
    assert_eq!(not_json.status, 400);
    let forty = post_admin(
        &s,
        "/api/admin/users",
        json!({"email": "k4@example.com", "display_name": "名".repeat(40)}),
    )
    .await;
    assert_eq!(forty.status, 201);
}

#[tokio::test(flavor = "current_thread")]
async fn deactivating_and_reactivating() {
    let s = seeded().await;
    let path = "/api/admin/users/active";
    let off = post_admin(
        &s,
        path,
        json!({"email": "Aiko@example.com", "active": false}),
    )
    .await;
    assert_eq!(off.status, 200);
    assert_eq!(off.body["active"], json!(false));
    let me = call(
        &s,
        req(
            "GET",
            "/api/me",
            Some(reviewer_token("aiko@example.com")),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(me.status, 403);
    assert_eq!(
        post_admin(
            &s,
            path,
            json!({"email": "aiko@example.com", "active": true})
        )
        .await
        .status,
        200
    );
    let me = call(
        &s,
        req(
            "GET",
            "/api/me",
            Some(reviewer_token("aiko@example.com")),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(me.status, 200);
    let myself = post_admin(&s, path, json!({"email": OWNER, "active": false})).await;
    assert_eq!(
        (myself.status, myself.body),
        (400, json!({"error": "you can't deactivate yourself"}))
    );
    assert_eq!(
        post_admin(
            &s,
            path,
            json!({"email": "nobody@example.com", "active": false})
        )
        .await
        .status,
        404
    );
}

async fn rename(
    store: &SqliteStore,
    jwt: String,
    origin: Option<&str>,
    body: Value,
) -> ApiResponse {
    call(
        store,
        req("POST", "/api/me/name", Some(jwt), origin, &body.to_string()),
    )
    .await
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_can_change_their_own_name() {
    let s = seeded().await;
    let response = rename(
        &s,
        reviewer_token("aiko@example.com"),
        Some(SITE),
        json!({"display_name": "  Aiko S.  "}),
    )
    .await;
    assert_eq!(response.status, 200);
    assert_eq!(
        response.body,
        json!({"email": "aiko@example.com", "display_name": "Aiko S.", "role": "reviewer",
               "public_role": "native", "public_name": null})
    );
    let me = call(
        &s,
        req(
            "GET",
            "/api/me",
            Some(reviewer_token("aiko@example.com")),
            None,
            "",
        ),
    )
    .await;
    assert_eq!(me.body["display_name"], json!("Aiko S."));
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_can_rename_from_either_application() {
    let s = seeded().await;
    assert_eq!(
        rename(
            &s,
            reviewer_token(OWNER),
            Some(SITE),
            json!({"display_name": "Martin J."})
        )
        .await
        .status,
        200
    );
    assert_eq!(
        rename(
            &s,
            admin_token(OWNER),
            Some(SITE),
            json!({"display_name": "Martin"})
        )
        .await
        .status,
        200
    );
}

#[tokio::test(flavor = "current_thread")]
async fn renaming_follows_the_usual_rules() {
    let s = seeded().await;
    let jwt = || reviewer_token("aiko@example.com");
    let body = json!({"display_name": "Aiko"});
    assert_eq!(rename(&s, jwt(), None, body.clone()).await.status, 403);
    assert_eq!(
        rename(&s, jwt(), Some("https://evil.example"), body.clone())
            .await
            .status,
        403
    );
    for bad in [
        json!({"display_name": ""}),
        json!({"display_name": "   "}),
        json!({"display_name": "x".repeat(41)}),
        json!({"display_name": "Aiko", "email": "owner@example.com"}),
        json!({}),
    ] {
        assert_eq!(
            rename(&s, jwt(), Some(SITE), bad.clone()).await.status,
            400,
            "{bad}"
        );
    }
    // Only ever your own name: the request names no one else, and the owner's name is unchanged.
    let users = call(
        &s,
        req(
            "GET",
            "/api/admin/users",
            Some(admin_token(OWNER)),
            None,
            "",
        ),
    )
    .await;
    assert!(users.body["users"]
        .as_array()
        .unwrap()
        .iter()
        .any(|u| u["display_name"] == "Martin"));
    let no_token = call(
        &s,
        req("POST", "/api/me/name", None, Some(SITE), &body.to_string()),
    )
    .await;
    assert_eq!(no_token.status, 401);
}

async fn me(store: &SqliteStore, email: &str) -> Value {
    call(
        store,
        req("GET", "/api/me", Some(reviewer_token(email)), None, ""),
    )
    .await
    .body
}

async fn public_name(store: &SqliteStore, body: Value) -> ApiResponse {
    call(
        store,
        req(
            "POST",
            "/api/me/public-name",
            Some(reviewer_token("aiko@example.com")),
            Some(SITE),
            &body.to_string(),
        ),
    )
    .await
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_chooses_a_public_name() {
    let s = seeded().await;
    let r = public_name(&s, json!({"public_name": "  Aiko  "})).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let body = me(&s, "aiko@example.com").await;
    assert_eq!(
        (body["public_name"].clone(), body["public_role"].clone()),
        (json!("Aiko"), json!("native"))
    );
    assert_eq!(
        public_name(&s, json!({"public_name": null})).await.status,
        200
    );
    assert_eq!(me(&s, "aiko@example.com").await["public_name"], Value::Null);
    assert_eq!(
        public_name(&s, json!({"public_name": "   "})).await.status,
        200
    );
    assert_eq!(me(&s, "aiko@example.com").await["public_name"], Value::Null);
    assert_eq!(
        public_name(&s, json!({"public_name": "x".repeat(41)}))
            .await
            .status,
        400
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_sets_a_reviewers_public_role() {
    let s = seeded().await;
    let body = json!({"email": "aiko@example.com", "public_role": "teacher"});
    let r = post_admin(&s, "/api/admin/users/role", body.clone()).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["public_role"], "teacher");
    assert_eq!(me(&s, "aiko@example.com").await["public_role"], "teacher");
    assert_eq!(me(&s, OWNER).await["public_role"], "owner");
    let as_reviewer = call(
        &s,
        req(
            "POST",
            "/api/admin/users/role",
            Some(reviewer_token("aiko@example.com")),
            Some(SITE),
            &body.to_string(),
        ),
    )
    .await;
    assert_eq!(as_reviewer.status, 403);
    let owner = post_admin(
        &s,
        "/api/admin/users/role",
        json!({"email": "aiko@example.com", "public_role": "owner"}),
    )
    .await;
    assert_eq!(
        (owner.status, owner.body["error"].as_str()),
        (400, Some("only the owner is credited as the owner"))
    );
    let unknown = post_admin(
        &s,
        "/api/admin/users/role",
        json!({"email": "nobody@example.com", "public_role": "native"}),
    )
    .await;
    assert_eq!(unknown.status, 404);
}

fn role_audit(s: &SqliteStore) -> Vec<String> {
    s.conn
        .borrow()
        .prepare("SELECT detail FROM audit_log WHERE action = 'user.role' ORDER BY id")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

#[tokio::test(flavor = "current_thread")]
async fn the_owner_makes_a_reviewer_a_teacher_and_back() {
    let s = seeded().await;
    let body = json!({"email": "aiko@example.com", "role": "teacher"});
    let r = post_admin(&s, "/api/admin/users/access", body).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.body["role"], "teacher");
    assert_eq!(r.body["public_role"], "native");
    let body = json!({"email": "aiko@example.com", "role": "reviewer"});
    let r = post_admin(&s, "/api/admin/users/access", body).await;
    assert_eq!(r.body["role"], "reviewer");
    assert_eq!(role_audit(&s), ["role=teacher", "role=reviewer"]);
}

#[tokio::test(flavor = "current_thread")]
async fn the_access_role_cannot_be_admin_or_touch_the_owner() {
    let s = seeded().await;
    let r = post_admin(
        &s,
        "/api/admin/users/access",
        json!({"email": "aiko@example.com", "role": "admin"}),
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("there is only one owner"))
    );
    let r = post_admin(
        &s,
        "/api/admin/users/access",
        json!({"email": OWNER, "role": "teacher"}),
    )
    .await;
    assert_eq!(
        (r.status, r.body["error"].as_str()),
        (400, Some("the owner's role can't change here"))
    );
    let r = post_admin(
        &s,
        "/api/admin/users/access",
        json!({"email": "nobody@example.com", "role": "teacher"}),
    )
    .await;
    assert_eq!(r.status, 404);
    let r = post_admin(
        &s,
        "/api/admin/users/access",
        json!({"email": "aiko@example.com", "role": "boss"}),
    )
    .await;
    assert_eq!(r.status, 400);
    assert!(role_audit(&s).is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_cannot_set_roles() {
    let s = seeded().await;
    let body = json!({"email": "aiko@example.com", "role": "teacher"});
    let r = call(
        &s,
        req(
            "POST",
            "/api/admin/users/access",
            Some(reviewer_token("aiko@example.com")),
            Some(SITE),
            &body.to_string(),
        ),
    )
    .await;
    assert_eq!(r.status, 403);
}
