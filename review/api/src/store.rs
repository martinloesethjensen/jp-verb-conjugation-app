//! Users and the audit log. The SQL is written once here and run by both the D1 store (the Worker) and the
//! SQLite store the tests use, so the two can't drift.

use crate::items::{ItemRow, Slice};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    Admin,
    /// Accepts and declines other people's suggestions.
    Teacher,
    Reviewer,
}

impl Role {
    pub fn as_str(self) -> &'static str {
        match self {
            Role::Admin => "admin",
            Role::Teacher => "teacher",
            Role::Reviewer => "reviewer",
        }
    }

    pub fn parse(text: &str) -> Option<Role> {
        match text {
            "admin" => Some(Role::Admin),
            "teacher" => Some(Role::Teacher),
            "reviewer" => Some(Role::Reviewer),
            _ => None,
        }
    }

    /// May accept and decline suggestions (never their own): teachers and the owner.
    pub fn can_decide(self) -> bool {
        matches!(self, Role::Teacher | Role::Admin)
    }
}

/// How someone is credited in the public repo: a stamp's `by` and the PR summary's wording.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PublicRole {
    Owner,
    Teacher,
    Native,
}

impl PublicRole {
    pub fn as_str(self) -> &'static str {
        match self {
            PublicRole::Owner => "owner",
            PublicRole::Teacher => "teacher",
            PublicRole::Native => "native",
        }
    }

    pub fn parse(text: &str) -> Option<PublicRole> {
        match text {
            "owner" => Some(PublicRole::Owner),
            "teacher" => Some(PublicRole::Teacher),
            "native" => Some(PublicRole::Native),
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
    pub public_role: PublicRole,
    /// `None`: credited by role only.
    pub public_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewUser {
    pub email: String,
    pub display_name: String,
    pub role: Role,
}

/// A loaded data file. `name` is the dataset name (`"verbs"`); `item_count` counts its entries.
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

/// A load in progress: what `begin` verified, and the slices the following requests handle.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SnapshotLoad {
    pub load_id: String,
    pub name: String,
    pub version: String,
    pub sha256: String,
    pub git_ref: Option<String>,
    pub slices: Vec<Slice>,
    pub started_by: String,
    pub started_at: String,
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
    "SELECT email, display_name, role, active, public_role, public_name FROM users WHERE email = ?1";
pub const SELECT_USERS: &str =
    "SELECT email, display_name, role, active, public_role, public_name FROM users ORDER BY display_name, email";
pub const INSERT_USER: &str =
    "INSERT INTO users (email, display_name, role, active, created_at) VALUES (?1, ?2, ?3, 1, ?4)";
pub const UPDATE_ACTIVE: &str = "UPDATE users SET active = ?1 WHERE email = ?2";
pub const UPDATE_DISPLAY_NAME: &str = "UPDATE users SET display_name = ?1 WHERE email = ?2";
pub const UPDATE_PUBLIC_NAME: &str = "UPDATE users SET public_name = ?1 WHERE email = ?2";
pub const UPDATE_PUBLIC_ROLE: &str = "UPDATE users SET public_role = ?1 WHERE email = ?2";
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

/// Starting a load of a file discards that file's unfinished loads (and their staged rows).
pub const DELETE_STAGING_FOR_NAME: &str =
    "DELETE FROM items_staging WHERE load_id IN (SELECT load_id FROM snapshot_loads WHERE name = ?1)";
pub const DELETE_SLICES_FOR_NAME: &str =
    "DELETE FROM snapshot_load_slices WHERE load_id IN (SELECT load_id FROM snapshot_loads WHERE name = ?1)";
pub const DELETE_LOADS_FOR_NAME: &str = "DELETE FROM snapshot_loads WHERE name = ?1";
pub const INSERT_LOAD: &str = "INSERT INTO snapshot_loads \
     (load_id, name, version, sha256, git_ref, slices, started_by, started_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)";
pub const SELECT_LOAD: &str =
    "SELECT load_id, name, version, sha256, git_ref, slices, started_by, started_at FROM snapshot_loads WHERE load_id = ?1";
pub const DELETE_STAGED_SLICE: &str = "DELETE FROM items_staging WHERE load_id = ?1 AND slice = ?2";
/// One slice's rows in one statement: ?4 is a JSON array of `ItemRow`s.
pub const INSERT_STAGED: &str = "INSERT INTO items_staging (load_id, slice, dataset, kind, item_id, parent_id, entry_id, position, title, subtitle, jlpt, content_hash, json) \
     SELECT ?1, ?2, ?3, json_extract(value, '$.kind'), json_extract(value, '$.item_id'), json_extract(value, '$.parent_id'), \
     json_extract(value, '$.entry_id'), json_extract(value, '$.position'), json_extract(value, '$.title'), \
     json_extract(value, '$.subtitle'), json_extract(value, '$.jlpt'), json_extract(value, '$.content_hash'), \
     json_extract(value, '$.json') FROM json_each(?4) WHERE EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?1)";
pub const INSERT_SLICE_DONE: &str = "INSERT OR IGNORE INTO snapshot_load_slices (load_id, slice) \
     SELECT ?1, ?2 WHERE EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?1)";
pub const COUNT_SLICES_DONE: &str =
    "SELECT COUNT(*) AS done FROM snapshot_load_slices WHERE load_id = ?1";
// finish's batch: every statement runs only while the load still exists, and the load row is deleted
// last, so a finish overtaken by a newer begin (or run twice) changes nothing.
pub const DELETE_ITEMS_FOR_LOAD: &str =
    "DELETE FROM items WHERE dataset = ?1 AND EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?2)";
pub const INSERT_ITEMS_FROM_STAGING: &str = "INSERT INTO items (dataset, kind, item_id, parent_id, entry_id, position, title, subtitle, jlpt, content_hash, json) \
     SELECT dataset, kind, item_id, parent_id, entry_id, position, title, subtitle, jlpt, content_hash, json FROM items_staging \
     WHERE load_id = ?1 AND EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?1)";
pub const UPSERT_SNAPSHOT_FILE_FOR_LOAD: &str = "INSERT OR REPLACE INTO snapshot_files \
     (name, version, sha256, git_ref, item_count, imported_at, imported_by, json) \
     SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8 WHERE EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?9)";
pub const INSERT_AUDIT_FOR_LOAD: &str =
    "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, ?3, ?4, ?5 WHERE EXISTS (SELECT 1 FROM snapshot_loads WHERE load_id = ?6)";
pub const DELETE_STAGING: &str = "DELETE FROM items_staging WHERE load_id = ?1";
pub const DELETE_SLICES: &str = "DELETE FROM snapshot_load_slices WHERE load_id = ?1";
pub const DELETE_LOAD: &str = "DELETE FROM snapshot_loads WHERE load_id = ?1";

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
    /// `None` makes the user anonymous. Audit row `user.public_name`.
    async fn set_public_name(
        &self,
        email: &str,
        public_name: Option<&str>,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    /// Audit row `user.public_role`.
    async fn set_public_role(
        &self,
        email: &str,
        public_role: PublicRole,
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
    /// Records a new load of a file, discarding that file's unfinished loads.
    async fn begin_load(&self, load: &SnapshotLoad) -> Result<(), StoreError>;
    async fn load(&self, load_id: &str) -> Result<Option<SnapshotLoad>, StoreError>;
    /// Writes one slice's rows to staging, replacing any earlier copy of that slice.
    async fn stage_slice(
        &self,
        load: &SnapshotLoad,
        slice: u32,
        rows: &[ItemRow],
    ) -> Result<(), StoreError>;
    async fn slices_done(&self, load_id: &str) -> Result<u32, StoreError>;
    /// In one batch: the staged rows replace the dataset's items, `snapshot_files` and the audit log
    /// are updated, and the load and its staging are removed. `NotFound` (and no change at all) when
    /// the load no longer exists, e.g. a newer begin discarded it or it was already finished.
    async fn finish_load(
        &self,
        load: &SnapshotLoad,
        file: &SnapshotFile,
        json: Option<&str>,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError>;

    /// A dataset's entries in file order.
    async fn entries(&self, dataset: &str) -> Result<Vec<ItemSummary>, StoreError>;
    /// An entry's JSON and content hash.
    async fn entry(
        &self,
        dataset: &str,
        item_id: &str,
    ) -> Result<Option<(String, String)>, StoreError>;
}
