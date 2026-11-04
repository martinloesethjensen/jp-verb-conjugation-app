//! Users and the audit log. The SQL is written once here and run by both the D1 store (the Worker) and the
//! SQLite store the tests use, so the two can't drift.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Admin,
    Reviewer,
}

impl Role {
    pub fn as_str(self) -> &'static str {
        match self {
            Role::Admin => "admin",
            Role::Reviewer => "reviewer",
        }
    }

    pub fn parse(text: &str) -> Option<Role> {
        match text {
            "admin" => Some(Role::Admin),
            "reviewer" => Some(Role::Reviewer),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct User {
    pub email: String,
    pub display_name: String,
    pub role: Role,
    pub active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewUser {
    pub email: String,
    pub display_name: String,
    pub role: Role,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StoreError {
    Conflict,
    NotFound,
    Backend(String),
}

pub const SELECT_USER: &str =
    "SELECT email, display_name, role, active FROM users WHERE email = ?1";
pub const SELECT_USERS: &str =
    "SELECT email, display_name, role, active FROM users ORDER BY display_name, email";
pub const INSERT_USER: &str =
    "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, ?2, ?3, 1, ?4)";
pub const UPDATE_ACTIVE: &str = "UPDATE users SET active = ?1 WHERE email = ?2";
pub const UPDATE_DISPLAY_NAME: &str = "UPDATE users SET display_name = ?1 WHERE email = ?2";
pub const INSERT_AUDIT: &str =
    "INSERT INTO audit_log (at, actor, action, target, detail) VALUES (?1, ?2, ?3, ?4, ?5)";

/// Users and their audit trail. `add_user` and `set_active` write their audit row in the same transaction
/// as the change (`user.add` with `role=<role>`, `user.active` with `active=0|1`, `user.name` with
/// `name=<new name>`).
#[allow(async_fn_in_trait)]
pub trait Store {
    async fn user(&self, email: &str) -> Result<Option<User>, StoreError>;
    /// Ordered by display name, then email.
    async fn users(&self) -> Result<Vec<User>, StoreError>;
    async fn add_user(&self, user: &NewUser, actor: &str, now: &str) -> Result<(), StoreError>;
    async fn set_active(
        &self,
        email: &str,
        active: bool,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    async fn set_display_name(
        &self,
        email: &str,
        display_name: &str,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError>;
}
