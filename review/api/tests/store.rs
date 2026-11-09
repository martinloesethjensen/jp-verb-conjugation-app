mod support;

use review_api::access::{Audience, Claims};
use review_api::auth::{authorize, normalize_email, Denied, Need, Principal};
use review_api::store::{NewUser, Role, Store, StoreError};
use support::sqlite::SqliteStore;

const T0: &str = "2026-10-29T12:00:00Z";
const OWNER: &str = "owner@example.com";

fn reviewer(email: &str, name: &str) -> NewUser {
    NewUser {
        email: email.into(),
        display_name: name.into(),
        role: Role::Reviewer,
    }
}

/// The owner as admin (the row the owner inserts by hand), Aiko active, Ken inactive.
async fn seeded() -> SqliteStore {
    let s = SqliteStore::new();
    s.conn
        .borrow()
        .execute(
            "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, 'Martin', 'admin', 1, ?2)",
            rusqlite::params![OWNER, T0],
        )
        .unwrap();
    s.add_user(&reviewer("aiko@example.com", "Aiko"), OWNER, T0)
        .await
        .unwrap();
    s.add_user(&reviewer("ken@example.com", "Ken"), OWNER, T0)
        .await
        .unwrap();
    s.set_active("ken@example.com", false, OWNER, T0)
        .await
        .unwrap();
    s
}

fn claims(email: Option<&str>) -> Claims {
    Claims {
        email: email.map(str::to_string),
        common_name: None,
        aud: vec!["reviewer-aud".into()],
        iss: "https://team.cloudflareaccess.com".into(),
        exp: 0,
        nbf: None,
        iat: None,
    }
}

fn audit_rows(s: &SqliteStore) -> Vec<(String, String, String, String)> {
    let conn = s.conn.borrow();
    let mut st = conn
        .prepare("SELECT actor, action, target, detail FROM audit_log ORDER BY id")
        .unwrap();
    st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

#[tokio::test(flavor = "current_thread")]
async fn users_round_trip_and_emails_are_lowercased_by_the_caller() {
    let s = SqliteStore::new();
    s.add_user(&reviewer("aiko@example.com", "Aiko"), OWNER, T0)
        .await
        .unwrap();
    let aiko = s.user("aiko@example.com").await.unwrap().unwrap();
    assert_eq!(
        (aiko.display_name.as_str(), aiko.role, aiko.active),
        ("Aiko", Role::Reviewer, true)
    );
    assert_eq!(s.user("nobody@example.com").await.unwrap(), None);
    assert_eq!(
        normalize_email("  Aiko@Example.COM "),
        Some("aiko@example.com".into())
    );
}

#[tokio::test(flavor = "current_thread")]
async fn users_are_listed_by_display_name() {
    let s = seeded().await;
    let names: Vec<String> = s
        .users()
        .await
        .unwrap()
        .into_iter()
        .map(|u| u.display_name)
        .collect();
    assert_eq!(names, ["Aiko", "Ken", "Martin"]);
}

#[tokio::test(flavor = "current_thread")]
async fn the_database_refuses_mixed_case_emails_and_unknown_roles() {
    let s = SqliteStore::new();
    let conn = s.conn.borrow();
    let insert = "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, 'A', ?2, 1, ?3)";
    assert!(conn
        .execute(insert, rusqlite::params!["A@x.com", "reviewer", T0])
        .is_err());
    assert!(conn
        .execute(insert, rusqlite::params!["a@x.com", "owner", T0])
        .is_err());
}

#[tokio::test(flavor = "current_thread")]
async fn adding_twice_is_a_conflict() {
    let s = seeded().await;
    assert_eq!(
        s.add_user(&reviewer("aiko@example.com", "Aiko"), OWNER, T0)
            .await,
        Err(StoreError::Conflict)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn set_active_on_an_unknown_user_is_not_found() {
    let s = seeded().await;
    assert_eq!(
        s.set_active("nobody@example.com", false, OWNER, T0).await,
        Err(StoreError::NotFound)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn changes_write_audit_rows() {
    let s = SqliteStore::new();
    s.add_user(&reviewer("aiko@example.com", "Aiko"), OWNER, T0)
        .await
        .unwrap();
    s.set_active("aiko@example.com", false, OWNER, T0)
        .await
        .unwrap();
    assert_eq!(
        audit_rows(&s),
        [
            (
                OWNER.into(),
                "user.add".into(),
                "aiko@example.com".into(),
                "role=reviewer".into()
            ),
            (
                OWNER.into(),
                "user.active".into(),
                "aiko@example.com".into(),
                "active=0".into()
            ),
        ]
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_audit_log_is_insert_only() {
    let s = seeded().await;
    let conn = s.conn.borrow();
    for sql in ["UPDATE audit_log SET actor = 'x'", "DELETE FROM audit_log"] {
        let error = conn.execute(sql, []).unwrap_err().to_string();
        assert!(error.contains("audit_log is insert-only"), "{sql}: {error}");
    }
}

#[test]
fn bad_emails_are_rejected() {
    let longest = "x".repeat(250) + "@b.c"; // 254 characters: the limit, still fine
    assert_eq!(normalize_email(&longest).as_deref(), Some(longest.as_str()));
    let long = "x".repeat(251) + "@b.c";
    for e in [
        "",
        "a",
        "a@",
        "@b",
        "a@b@c",
        "a b@c",
        "a\t@b",
        long.as_str(),
    ] {
        assert_eq!(normalize_email(e), None, "{e:?}");
    }
}

#[tokio::test(flavor = "current_thread")]
async fn a_reviewer_may_use_reviewer_routes() {
    let s = seeded().await;
    let p = authorize(
        &claims(Some("aiko@example.com")),
        Audience::Reviewer,
        Need::Reviewer,
        &s,
    )
    .await;
    assert_eq!(
        p,
        Ok(Principal {
            email: "aiko@example.com".into(),
            display_name: "Aiko".into(),
            role: Role::Reviewer
        })
    );
}

#[tokio::test(flavor = "current_thread")]
async fn the_email_claim_is_matched_case_insensitively() {
    let s = seeded().await;
    let p = authorize(
        &claims(Some("Aiko@Example.com")),
        Audience::Reviewer,
        Need::Reviewer,
        &s,
    )
    .await;
    assert_eq!(p.unwrap().email, "aiko@example.com");
}

#[tokio::test(flavor = "current_thread")]
async fn unknown_and_inactive_users_are_forbidden() {
    let s = seeded().await;
    for email in ["nobody@example.com", "ken@example.com"] {
        let p = authorize(&claims(Some(email)), Audience::Reviewer, Need::Reviewer, &s).await;
        assert_eq!(p, Err(Denied::Forbidden), "{email}");
    }
}

#[tokio::test(flavor = "current_thread")]
async fn a_service_token_is_forbidden() {
    let s = seeded().await;
    for need in [Need::Reviewer, Need::Admin] {
        assert_eq!(
            authorize(&claims(None), Audience::Admin, need, &s).await,
            Err(Denied::Forbidden)
        );
    }
}

#[tokio::test(flavor = "current_thread")]
async fn admin_routes_need_the_admin_audience_and_role() {
    let s = seeded().await;
    let owner = claims(Some(OWNER));
    assert_eq!(
        authorize(&owner, Audience::Admin, Need::Admin, &s)
            .await
            .unwrap()
            .role,
        Role::Admin
    );
    assert_eq!(
        authorize(&owner, Audience::Reviewer, Need::Admin, &s).await,
        Err(Denied::Forbidden)
    );
    let aiko = claims(Some("aiko@example.com"));
    assert_eq!(
        authorize(&aiko, Audience::Admin, Need::Admin, &s).await,
        Err(Denied::Forbidden)
    );
    // The owner can use reviewer routes from either application.
    assert!(authorize(&owner, Audience::Reviewer, Need::Reviewer, &s)
        .await
        .is_ok());
}

#[tokio::test(flavor = "current_thread")]
async fn renaming_writes_an_audit_row() {
    let s = seeded().await;
    s.set_display_name("aiko@example.com", "Aiko S.", "aiko@example.com", T0)
        .await
        .unwrap();
    assert_eq!(
        s.user("aiko@example.com")
            .await
            .unwrap()
            .unwrap()
            .display_name,
        "Aiko S."
    );
    let last = audit_rows(&s).pop().unwrap();
    assert_eq!(
        last,
        (
            "aiko@example.com".into(),
            "user.name".into(),
            "aiko@example.com".into(),
            "name=Aiko S.".into()
        )
    );
    assert_eq!(
        s.set_display_name("nobody@example.com", "X", OWNER, T0)
            .await,
        Err(StoreError::NotFound)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn migration_0006_credits_the_admin_as_owner() {
    let s = SqliteStore::with_migrations_before("0006");
    s.conn
        .borrow()
        .execute_batch(
            "INSERT INTO users (email, display_name, role, active, created_at) VALUES \
             ('owner@example.com', 'Martin', 'admin', 1, 't'), ('aiko@example.com', 'Aiko', 'reviewer', 1, 't');",
        )
        .unwrap();
    s.apply_migrations_from("0006");
    let owner = s.user("owner@example.com").await.unwrap().unwrap();
    let aiko = s.user("aiko@example.com").await.unwrap().unwrap();
    assert_eq!(owner.public_role.as_str(), "owner");
    assert_eq!(aiko.public_role.as_str(), "native");
    assert_eq!(aiko.public_name, None);
}

/// Makes `email` a teacher (active unless `active` is false) straight in the table.
fn add_teacher(s: &SqliteStore, email: &str, active: bool) {
    s.conn
        .borrow()
        .execute(
            "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, 'Keiko', 'teacher', ?2, 't')",
            rusqlite::params![email, active as i64],
        )
        .unwrap();
}

#[tokio::test(flavor = "current_thread")]
async fn migration_0007_keeps_every_user_and_allows_teacher() {
    let s = SqliteStore::with_migrations_before("0007");
    s.conn
        .borrow()
        .execute_batch(
            "INSERT INTO users (email, display_name, role, active, created_at, public_role) VALUES \
             ('owner@example.com', 'Martin', 'admin', 1, 't1', 'owner'); \
             INSERT INTO users (email, display_name, role, active, created_at, public_role, public_name) VALUES \
             ('aiko@example.com', 'Aiko', 'reviewer', 1, 't2', 'teacher', 'Aiko'); \
             INSERT INTO users (email, display_name, role, active, created_at) VALUES \
             ('ken@example.com', 'Ken', 'reviewer', 0, 't3');",
        )
        .unwrap();
    let before = s.users().await.unwrap();
    s.apply_migrations_from("0007");
    assert_eq!(s.users().await.unwrap(), before);
    let created: Vec<String> = s
        .conn
        .borrow()
        .prepare("SELECT created_at FROM users ORDER BY created_at")
        .unwrap()
        .query_map([], |r| r.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect();
    assert_eq!(created, ["t1", "t2", "t3"]);
    let conn = s.conn.borrow();
    conn.execute("UPDATE users SET role = 'teacher' WHERE email = 'aiko@example.com'", [])
        .unwrap();
    assert!(conn
        .execute("UPDATE users SET role = 'boss' WHERE email = 'ken@example.com'", [])
        .is_err());
    drop(conn);
    assert_eq!(s.user("aiko@example.com").await.unwrap().unwrap().role, Role::Teacher);
}

#[test]
fn only_teachers_and_the_admin_can_decide() {
    assert!(Role::Teacher.can_decide());
    assert!(Role::Admin.can_decide());
    assert!(!Role::Reviewer.can_decide());
    assert_eq!(Role::parse("teacher"), Some(Role::Teacher));
    assert_eq!(Role::Teacher.as_str(), "teacher");
}

#[tokio::test(flavor = "current_thread")]
async fn teacher_routes_need_a_teacher_or_the_admin_on_either_application() {
    let s = seeded().await;
    add_teacher(&s, "keiko@example.com", true);
    add_teacher(&s, "old@example.com", false);
    let keiko = claims(Some("keiko@example.com"));
    for audience in [Audience::Reviewer, Audience::Admin] {
        for need in [Need::Reviewer, Need::Teacher] {
            assert_eq!(
                authorize(&keiko, audience, need, &s).await.unwrap().role,
                Role::Teacher,
                "{audience:?} {need:?}"
            );
        }
        assert_eq!(
            authorize(&keiko, audience, Need::Admin, &s).await,
            Err(Denied::Forbidden)
        );
        let aiko = claims(Some("aiko@example.com"));
        assert_eq!(
            authorize(&aiko, audience, Need::Teacher, &s).await,
            Err(Denied::Forbidden)
        );
        let old = claims(Some("old@example.com"));
        for need in [Need::Reviewer, Need::Teacher, Need::Admin] {
            assert_eq!(authorize(&old, audience, need, &s).await, Err(Denied::Forbidden));
        }
    }
    let owner = claims(Some(OWNER));
    assert!(authorize(&owner, Audience::Reviewer, Need::Teacher, &s)
        .await
        .is_ok());
}
