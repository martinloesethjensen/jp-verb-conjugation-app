//! Users and the audit log. The SQL is written once here and run by both the D1 store (the Worker) and the
//! SQLite store the tests use, so the two can't drift.

use crate::items::ItemRow;
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

/// A loaded data file. `name` is the dataset name (`"verbs"`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SnapshotFile {
    pub name: String,
    pub version: String,
    pub sha256: String,
    pub git_ref: Option<String>,
    pub item_count: u32,
    pub imported_at: String,
    pub imported_by: String,
}

/// An entry in a browse list. `parts` counts its sub-items (examples, usages, pitfalls, things).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemSummary {
    pub item_id: String,
    pub title: String,
    pub subtitle: String,
    pub jlpt: Option<String>,
    pub parts: u32,
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
pub const DELETE_ITEMS: &str = "DELETE FROM items WHERE dataset = ?1";
/// All of a dataset's rows in one statement: ?2 is a JSON array of `ItemRow`s.
pub const INSERT_ITEMS: &str = "INSERT INTO items (dataset, kind, item_id, parent_id, entry_id, position, title, subtitle, jlpt, content_hash, json) \
     SELECT ?1, json_extract(value, '$.kind'), json_extract(value, '$.item_id'), json_extract(value, '$.parent_id'), \
     json_extract(value, '$.entry_id'), json_extract(value, '$.position'), json_extract(value, '$.title'), \
     json_extract(value, '$.subtitle'), json_extract(value, '$.jlpt'), json_extract(value, '$.content_hash'), \
     json_extract(value, '$.json') FROM json_each(?2)";
pub const UPSERT_SNAPSHOT_FILE: &str = "INSERT OR REPLACE INTO snapshot_files \
     (name, version, sha256, git_ref, item_count, imported_at, imported_by, json) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)";
pub const SELECT_SNAPSHOT_FILES: &str = "SELECT name, version, sha256, git_ref, item_count, imported_at, imported_by FROM snapshot_files";
pub const SELECT_SNAPSHOT_FILE: &str = "SELECT name, version, sha256, git_ref, item_count, imported_at, imported_by FROM snapshot_files WHERE name = ?1";
pub const SELECT_SNAPSHOT_JSON: &str =
    "SELECT json FROM snapshot_files WHERE name = ?1 AND json IS NOT NULL";
pub const SELECT_ENTRIES: &str = "SELECT e.item_id, e.title, e.subtitle, e.jlpt, \
     (SELECT COUNT(*) FROM items s WHERE s.dataset = e.dataset AND s.entry_id = e.item_id AND s.kind <> 'entry') AS parts \
     FROM items e WHERE e.dataset = ?1 AND e.kind = 'entry' ORDER BY e.position";
pub const SELECT_ENTRY: &str =
    "SELECT json, content_hash FROM items WHERE dataset = ?1 AND kind = 'entry' AND item_id = ?2";

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

    /// Replaces a dataset's snapshot in one batch: its items, its `snapshot_files` row (with `json`
    /// for reference files) and a `snapshot.import` audit row. On error nothing changes.
    async fn replace_snapshot(
        &self,
        file: &SnapshotFile,
        json: Option<&str>,
        rows: &[ItemRow],
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    async fn snapshot_files(&self) -> Result<Vec<SnapshotFile>, StoreError>;
    async fn snapshot_file(&self, name: &str) -> Result<Option<SnapshotFile>, StoreError>;
    async fn snapshot_json(&self, name: &str) -> Result<Option<String>, StoreError>;
    /// A dataset's entries in file order.
    async fn entries(&self, dataset: &str) -> Result<Vec<ItemSummary>, StoreError>;
    /// An entry's JSON and content hash.
    async fn entry(
        &self,
        dataset: &str,
        item_id: &str,
    ) -> Result<Option<(String, String)>, StoreError>;
}
