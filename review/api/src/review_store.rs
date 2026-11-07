//! What reviewers do: approvals, suggestions, comments, queues and skips. As in `store.rs`, the SQL is
//! written once here and run by both the D1 store and the SQLite store the tests use.
//!
//! Every row names its target as `(dataset, kind, item_id)` and copies in the entry id and title, so it
//! keeps rendering after the item leaves the data. Whether an approval is current, and whether a
//! suggestion is stale or its item gone, is computed on read against `items.content_hash`.
//!
//! Both backends read rows into the `*Row` structs below (D1 through serde, SQLite by column name), so
//! turning rows into the API's types happens once, here.

use crate::store::StoreError;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Target {
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
}

impl Target {
    /// How the audit log names a target.
    pub fn audit_name(&self) -> String {
        format!("{}/{}/{}", self.dataset, self.kind, self.item_id)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Approval {
    pub kind: String,
    pub item_id: String,
    pub reviewer_name: String,
    pub mine: bool,
    /// The approval's hash is the item's current hash.
    pub current: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Comment {
    pub author_name: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Suggestion {
    pub id: i64,
    pub action: String,
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub item_title: String,
    pub author_name: String,
    pub mine: bool,
    pub status: String,
    pub base_hash: String,
    pub proposed: Option<Value>,
    pub furigana: Option<Value>,
    pub dropped_blanks: u32,
    pub comment: String,
    pub admin_edit: Option<Value>,
    pub created_at: String,
    pub decided_at: Option<String>,
    /// The item changed since the suggestion was made.
    pub stale: bool,
    /// The item (an addition: its parent) is no longer in the loaded data.
    pub gone: bool,
    /// An addition's parent; `None` otherwise and for a new entry.
    pub parent_kind: Option<String>,
    pub parent_id: Option<String>,
    /// An addition whose new item is now among the loaded items (after export and reload).
    pub landed: bool,
    pub comments: Vec<Comment>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct QueueSummary {
    pub id: i64,
    pub title: String,
    pub description: String,
    pub total: u32,
    /// Done for the asking reviewer (see `ReviewStore::queue`).
    pub done: u32,
    pub with_suggestion: u32,
    pub archived: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct QueueItem {
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub title: String,
    pub note: String,
    pub position: i64,
    pub gone: bool,
    /// `"approved"`, `"suggested"` or `"skipped"`, for the asking reviewer.
    pub mine: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewSuggestion {
    pub action: String,
    pub target: Target,
    pub entry_id: String,
    pub item_title: String,
    pub base_hash: String,
    pub proposed_json: Option<String>,
    pub furigana_json: Option<String>,
    pub dropped_blanks: u32,
    pub comment: String,
    /// An addition's parent: `None` for a change, removal, note or new entry.
    pub parent_kind: Option<String>,
    pub parent_id: Option<String>,
    /// An addition's item without its ids, so a double tap finds the first one.
    pub fingerprint: Option<String>,
}

/// Which items a queue holds. Empty lists mean "any"; `ids` match `item_id` exactly within the dataset.
#[derive(Debug, Clone, PartialEq, Eq, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct QueueFilter {
    pub dataset: String,
    pub kinds: Vec<String>,
    pub jlpt: Vec<String>,
    pub never_approved: bool,
    pub ids: Vec<String>,
}

impl QueueFilter {
    /// The filter's bind values, in the order `FILTER_WHERE` numbers them from `?1`.
    pub fn binds(&self) -> (String, String, String, i64, String) {
        let list = |v: &Vec<String>| serde_json::to_string(v).unwrap_or_else(|_| "[]".into());
        (
            self.dataset.clone(),
            list(&self.kinds),
            list(&self.jlpt),
            self.never_approved as i64,
            list(&self.ids),
        )
    }
}

// --- Rows, shared by both backends ---------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct HashRow {
    pub content_hash: String,
    pub entry_id: String,
    pub title: String,
}

/// One target of an entry, as `GET /api/review` lists it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Part {
    pub kind: String,
    pub item_id: String,
    pub content_hash: String,
}

#[derive(Debug, Deserialize)]
pub struct ItemIdRow {
    pub item_id: String,
}

#[derive(Debug, Deserialize)]
pub struct IdRow {
    pub id: i64,
}

#[derive(Debug, Deserialize)]
pub struct ApprovalRow {
    pub kind: String,
    pub item_id: String,
    pub reviewer_name: String,
    pub mine: i64,
    pub current: i64,
    pub created_at: String,
}

impl From<ApprovalRow> for Approval {
    fn from(r: ApprovalRow) -> Self {
        Approval {
            kind: r.kind,
            item_id: r.item_id,
            reviewer_name: r.reviewer_name,
            mine: r.mine != 0,
            current: r.current != 0,
            created_at: r.created_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct SuggestionRow {
    pub id: i64,
    pub action: String,
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub item_title: String,
    pub author: String,
    pub author_name: String,
    pub mine: i64,
    pub status: String,
    pub base_hash: String,
    pub proposed_json: Option<String>,
    pub furigana_json: Option<String>,
    pub dropped_blanks: i64,
    pub comment: String,
    pub admin_edit_json: Option<String>,
    pub created_at: String,
    pub decided_at: Option<String>,
    pub stale: i64,
    pub gone: i64,
    pub parent_kind: Option<String>,
    pub parent_id: Option<String>,
    pub landed: i64,
}

#[derive(Debug, Deserialize)]
pub struct CommentRow {
    pub suggestion_id: i64,
    pub author_name: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct QueueRow {
    pub id: i64,
    pub title: String,
    pub description: String,
    pub total: i64,
    pub done: i64,
    pub with_suggestion: i64,
    pub archived: i64,
}

impl From<QueueRow> for QueueSummary {
    fn from(r: QueueRow) -> Self {
        QueueSummary {
            id: r.id,
            title: r.title,
            description: r.description,
            total: r.total as u32,
            done: r.done as u32,
            with_suggestion: r.with_suggestion as u32,
            archived: r.archived != 0,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct QueueItemRow {
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub title: String,
    pub note: String,
    pub position: i64,
    pub gone: i64,
    pub mine: Option<String>,
}

impl From<QueueItemRow> for QueueItem {
    fn from(r: QueueItemRow) -> Self {
        QueueItem {
            dataset: r.dataset,
            kind: r.kind,
            item_id: r.item_id,
            entry_id: r.entry_id,
            title: r.title,
            note: r.note,
            position: r.position,
            gone: r.gone != 0,
            mine: r.mine,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct CountRow {
    pub entry_id: String,
    pub approved: i64,
    pub open: i64,
}

#[derive(Debug, Deserialize)]
pub struct StatusRow {
    pub status: String,
    pub author: String,
}

fn parse_json(text: Option<String>) -> Option<Value> {
    text.and_then(|t| serde_json::from_str(&t).ok())
}

/// Suggestions with their comments attached, in the rows' order.
pub fn assemble(rows: Vec<SuggestionRow>, comments: Vec<CommentRow>) -> Vec<Suggestion> {
    rows.into_iter()
        .map(|r| Suggestion {
            comments: comments
                .iter()
                .filter(|c| c.suggestion_id == r.id)
                .map(|c| Comment {
                    author_name: c.author_name.clone(),
                    body: c.body.clone(),
                    created_at: c.created_at.clone(),
                })
                .collect(),
            id: r.id,
            action: r.action,
            dataset: r.dataset,
            kind: r.kind,
            item_id: r.item_id,
            entry_id: r.entry_id,
            item_title: r.item_title,
            author_name: r.author_name,
            mine: r.mine != 0,
            status: r.status,
            base_hash: r.base_hash,
            proposed: parse_json(r.proposed_json),
            furigana: parse_json(r.furigana_json),
            dropped_blanks: r.dropped_blanks as u32,
            comment: r.comment,
            admin_edit: parse_json(r.admin_edit_json),
            created_at: r.created_at,
            decided_at: r.decided_at,
            stale: r.stale != 0,
            gone: r.gone != 0,
            parent_kind: r.parent_kind,
            parent_id: r.parent_id,
            landed: r.landed != 0,
        })
        .collect()
}

// --- SQL ------------------------------------------------------------------------------------------

/// ?1 dataset, ?2 entry id: the entry and its parts in file order.
/// A stamp the owner made, waiting for export. `by` is the reviewer's public role when stamped; `name` is
/// their public name now (they can change it until export); `reviewer_name` is their site name.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Stamp {
    pub id: i64,
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub item_title: String,
    pub content_hash: String,
    pub by: String,
    pub name: Option<String>,
    pub reviewer_name: String,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewStamp {
    pub target: Target,
    pub entry_id: String,
    pub item_title: String,
    pub content_hash: String,
    pub by_role: String,
    pub reviewer: String,
}

/// Whether an entry can be stamped: parts without a current approval, open suggestions on it, and the most
/// senior reviewer among its current approvals (by public role, then the earliest approval).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct StampReadiness {
    pub missing: i64,
    pub open: i64,
    pub reviewer: Option<String>,
    pub reviewer_role: Option<String>,
    pub content_hash: Option<String>,
    pub title: Option<String>,
}

macro_rules! stamp_columns {
    () => {
        "SELECT s.id, s.dataset, s.kind, s.item_id, s.entry_id, s.item_title, s.content_hash, \
     s.by_role AS \"by\", u.public_name AS name, IFNULL(u.display_name, '') AS reviewer_name, s.created_at \
     FROM stamps s LEFT JOIN users u ON u.email = s.reviewer "
    };
}
/// ?1–?3 the target.
pub const SELECT_PENDING_STAMP: &str = concat!(
    stamp_columns!(),
    "WHERE s.dataset = ?1 AND s.kind = ?2 AND s.item_id = ?3 AND s.exported_at IS NULL"
);
/// The current approvals of an entry's parts, most senior reviewer first. ?1 dataset, ?2 entry id.
macro_rules! senior_approval {
    () => {
        "FROM approvals a \
     JOIN items i ON i.dataset = a.dataset AND i.kind = a.kind AND i.item_id = a.item_id AND i.content_hash = a.content_hash \
     JOIN users u ON u.email = a.reviewer WHERE a.dataset = ?1 AND i.entry_id = ?2 \
     ORDER BY CASE u.public_role WHEN 'owner' THEN 0 WHEN 'teacher' THEN 1 ELSE 2 END, a.created_at, a.reviewer LIMIT 1"
    };
}
/// ?1 dataset, ?2 entry id.
pub const SELECT_STAMP_READINESS: &str = concat!(
    "SELECT (SELECT COUNT(*) FROM items i WHERE i.dataset = ?1 AND i.entry_id = ?2 AND NOT EXISTS \
     (SELECT 1 FROM approvals a WHERE a.dataset = i.dataset AND a.kind = i.kind AND a.item_id = i.item_id \
     AND a.content_hash = i.content_hash)) AS missing, \
     (SELECT COUNT(*) FROM suggestions WHERE dataset = ?1 AND entry_id = ?2 AND status = 'open') AS open, \
     (SELECT a.reviewer ",
    senior_approval!(),
    ") AS reviewer, (SELECT u.public_role ",
    senior_approval!(),
    ") AS reviewer_role, \
     (SELECT content_hash FROM items WHERE dataset = ?1 AND kind = 'entry' AND item_id = ?2) AS content_hash, \
     (SELECT title FROM items WHERE dataset = ?1 AND kind = 'entry' AND item_id = ?2) AS title"
);
/// An accepted suggestion as export reads it: the item to write (the owner's edit, else the reviewer's),
/// and how its author is credited. Never the author's email.
#[derive(Debug, Clone, Deserialize)]
pub struct ExportRow {
    pub id: i64,
    pub action: String,
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub entry_id: String,
    pub parent_kind: Option<String>,
    pub parent_id: Option<String>,
    pub item_title: String,
    pub item_json: Option<String>,
    pub furigana_json: Option<String>,
    pub comment: String,
    pub credit_role: String,
    pub credit_name: Option<String>,
    pub decided_at: Option<String>,
    /// A change whose target's hash is no longer the one it was built on.
    pub stale: i64,
}

pub const SELECT_EXPORT_SUGGESTIONS: &str = "SELECT s.id, s.action, s.dataset, s.kind, s.item_id, s.entry_id, \
     s.parent_kind, s.parent_id, s.item_title, IFNULL(s.admin_edit_json, s.proposed_json) AS item_json, \
     s.furigana_json, s.comment, IFNULL(u.public_role, 'native') AS credit_role, u.public_name AS credit_name, \
     s.decided_at, (s.action = 'change' AND i.content_hash IS NOT NULL AND i.content_hash <> s.base_hash) AS stale \
     FROM suggestions s LEFT JOIN users u ON u.email = s.author \
     LEFT JOIN items i ON i.dataset = s.dataset AND i.kind = s.kind AND i.item_id = s.item_id \
     WHERE s.status = 'accepted' AND s.exported_at IS NULL ORDER BY s.id";
pub const SELECT_EXPORT_STAMPS: &str = concat!(
    stamp_columns!(),
    "WHERE s.exported_at IS NULL ORDER BY s.id"
);
/// ?1 a JSON array of ids, ?2 now. Only accepted, not yet exported suggestions change.
pub const MARK_SUGGESTIONS_EXPORTED: &str = "UPDATE suggestions SET exported_at = ?2 \
     WHERE id IN (SELECT value FROM json_each(?1)) AND status = 'accepted' AND exported_at IS NULL";
/// ?1 a JSON array of ids, ?2 now.
pub const MARK_STAMPS_EXPORTED: &str = "UPDATE stamps SET exported_at = ?2 \
     WHERE id IN (SELECT value FROM json_each(?1)) AND exported_at IS NULL";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReadyEntry {
    pub dataset: String,
    pub item_id: String,
    pub title: String,
}

/// Counters and grammar points ready for the owner's stamp: every part approved at its current hash,
/// nothing open, no pending stamp, and no stamp in the published data already.
pub const SELECT_READY_TO_STAMP: &str = "SELECT e.dataset, e.item_id, e.title FROM items e \
     WHERE e.kind = 'entry' AND e.dataset IN ('counters', 'grammar') AND json_extract(e.json, '$.review') IS NULL \
     AND NOT EXISTS (SELECT 1 FROM items i WHERE i.dataset = e.dataset AND i.entry_id = e.item_id AND NOT EXISTS \
       (SELECT 1 FROM approvals a WHERE a.dataset = i.dataset AND a.kind = i.kind AND a.item_id = i.item_id \
        AND a.content_hash = i.content_hash)) \
     AND NOT EXISTS (SELECT 1 FROM suggestions s WHERE s.dataset = e.dataset AND s.entry_id = e.item_id \
       AND s.status = 'open') \
     AND NOT EXISTS (SELECT 1 FROM stamps t WHERE t.dataset = e.dataset AND t.kind = 'entry' \
       AND t.item_id = e.item_id AND t.exported_at IS NULL) \
     ORDER BY e.dataset, e.position";
/// ?1–?3 target, ?4 entry id, ?5 title, ?6 hash, ?7 role, ?8 reviewer, ?9 by, ?10 now.
pub const INSERT_STAMP: &str =
    "INSERT INTO stamps (dataset, kind, item_id, entry_id, item_title, content_hash, \
     by_role, reviewer, created_by, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10) \
     ON CONFLICT (dataset, kind, item_id) WHERE exported_at IS NULL DO NOTHING";
/// ?1–?3 the target.
pub const DELETE_PENDING_STAMP: &str =
    "DELETE FROM stamps WHERE dataset = ?1 AND kind = ?2 AND item_id = ?3 AND exported_at IS NULL";

pub const SELECT_PARTS: &str = "SELECT kind, item_id, content_hash FROM items WHERE dataset = ?1 AND entry_id = ?2 ORDER BY position";

pub const SELECT_HASH: &str = "SELECT content_hash, entry_id, title FROM items WHERE dataset = ?1 AND kind = ?2 AND item_id = ?3";

/// ?1–?3 the target, ?4 reviewer, ?5 hash, ?6 now. Takes the entry id from `items`; a second approval
/// by the same reviewer replaces the first.
pub const UPSERT_APPROVAL: &str = "INSERT INTO approvals (dataset, kind, item_id, entry_id, reviewer, content_hash, created_at) \
     SELECT ?1, ?2, ?3, entry_id, ?4, ?5, ?6 FROM items WHERE dataset = ?1 AND kind = ?2 AND item_id = ?3 \
     ON CONFLICT (dataset, kind, item_id, reviewer) DO UPDATE SET content_hash = excluded.content_hash, created_at = excluded.created_at";
pub const DELETE_APPROVAL: &str =
    "DELETE FROM approvals WHERE dataset = ?1 AND kind = ?2 AND item_id = ?3 AND reviewer = ?4";

/// ?1 action, ?2–?4 target, ?5 author, ?6 proposed, ?7 furigana, ?8 comment.
pub const SELECT_IDENTICAL_OPEN: &str = "SELECT id FROM suggestions WHERE action = ?1 AND dataset = ?2 AND kind = ?3 \
     AND item_id = ?4 AND author = ?5 AND status = 'open' AND IFNULL(proposed_json, '') = IFNULL(?6, '') \
     AND IFNULL(furigana_json, '') = IFNULL(?7, '') AND comment = ?8 ORDER BY id LIMIT 1";
/// An identical open addition: same author, dataset, kind, parent and item (ids aside). ?1 dataset,
/// ?2 kind, ?3 parent id, ?4 author, ?5 fingerprint, ?6 furigana, ?7 comment.
pub const SELECT_IDENTICAL_ADD: &str = "SELECT id FROM suggestions WHERE action = 'add' AND dataset = ?1 AND kind = ?2 \
     AND IFNULL(parent_id, '') = IFNULL(?3, '') AND author = ?4 AND status = 'open' AND fingerprint = ?5 \
     AND IFNULL(furigana_json, '') = IFNULL(?6, '') AND comment = ?7 ORDER BY id LIMIT 1";
/// ?1 dataset, ?2 id: a loaded item, or an open or accepted addition, already uses it.
pub const SELECT_ID_IN_USE: &str = "SELECT 1 AS id FROM items WHERE dataset = ?1 AND item_id = ?2 \
     UNION ALL SELECT 1 AS id FROM suggestions WHERE dataset = ?1 AND item_id = ?2 AND action = 'add' \
     AND status IN ('open', 'accepted') LIMIT 1";
/// ?1 dataset: every loaded item's id.
pub const SELECT_LOADED_IDS: &str = "SELECT item_id FROM items WHERE dataset = ?1";
/// ?1 dataset: the ids of open and accepted additions.
pub const SELECT_SUGGESTED_IDS: &str =
    "SELECT item_id FROM suggestions WHERE dataset = ?1 AND action = 'add' \
     AND status IN ('open', 'accepted')";
/// ?1 dataset, ?2 kind, ?3 item id.
pub const SELECT_OPEN_ADD: &str =
    "SELECT id FROM suggestions WHERE action = 'add' AND dataset = ?1 AND kind = ?2 \
     AND item_id = ?3 AND status = 'open' ORDER BY id LIMIT 1";
pub const INSERT_SUGGESTION: &str =
    "INSERT INTO suggestions (action, dataset, kind, item_id, entry_id, item_title, base_hash, \
     proposed_json, furigana_json, dropped_blanks, comment, author, created_at, parent_kind, parent_id, fingerprint) \
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16) RETURNING id";
/// The audit row for the suggestion just inserted by ?2 in this batch: ?1 now, ?2 author, ?3 detail.
pub const INSERT_SUGGESTION_AUDIT: &str = "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, 'suggestion.add', 'suggestion/' || MAX(id), ?3 FROM suggestions WHERE author = ?2";

pub const SELECT_STATUS: &str = "SELECT status, author FROM suggestions WHERE id = ?1";
/// ?1 id, ?2 author, ?3 now.
pub const WITHDRAW: &str =
    "UPDATE suggestions SET status = 'withdrawn', decided_at = ?3, decided_by = ?2 \
     WHERE id = ?1 AND author = ?2 AND status = 'open'";
/// ?1 id, ?2 status, ?3 admin edit, ?4 by, ?5 now, ?6 the owner's furigana (replaces the reviewer's
/// when set), ?7 the hash the owner's edit was built on (replaces the reviewer's base, so export can tell
/// whether the data moved on since).
/// What an accept with the owner's edit stores: the edited item, the owner's readings (replacing the
/// reviewer's), and the hash of the data the edit was built on (replacing the reviewer's base).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct OwnerEdit<'a> {
    pub item_json: Option<&'a str>,
    pub furigana_json: Option<&'a str>,
    pub base_hash: Option<&'a str>,
}

pub const DECIDE: &str =
    "UPDATE suggestions SET status = ?2, admin_edit_json = ?3, decided_by = ?4, \
     decided_at = ?5, furigana_json = IFNULL(?6, furigana_json), base_hash = IFNULL(?7, base_hash) \
     WHERE id = ?1 AND status = 'open'";
/// A decision's audit row, written before `DECIDE` in the same batch and only while the suggestion is
/// still open, so a decision that loses a race to another tab logs nothing. ?1 now, ?2 by, ?3 action,
/// ?4 detail, ?5 id.
pub const INSERT_DECIDE_AUDIT: &str = "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, ?3, 'suggestion/' || id, ?4 FROM suggestions WHERE id = ?5 AND status = 'open'";
/// As `INSERT_DECIDE_AUDIT`, for `WITHDRAW`: ?1 now, ?2 author, ?3 id.
pub const INSERT_WITHDRAW_AUDIT: &str =
    "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, 'suggestion.withdraw', 'suggestion/' || id, '' FROM suggestions \
     WHERE id = ?3 AND status = 'open' AND author = ?2";
/// ?1 suggestion, ?2 author, ?3 body, ?4 now.
pub const INSERT_COMMENT: &str = "INSERT INTO comments (suggestion_id, author, body, created_at) \
     SELECT ?1, ?2, ?3, ?4 WHERE EXISTS (SELECT 1 FROM suggestions WHERE id = ?1)";

macro_rules! suggestions_where {
    ($where:literal, $order:literal) => {
        concat!(
            "SELECT s.id, s.action, s.dataset, s.kind, s.item_id, s.entry_id, s.item_title, s.author, ",
            "IFNULL(u.display_name, '') AS author_name, (s.author = ?1) AS mine, s.status, s.base_hash, s.proposed_json, ",
            "s.furigana_json, s.dropped_blanks, s.comment, s.admin_edit_json, s.created_at, s.decided_at, ",
            // An addition is never stale; it is gone when its parent left, and landed once its item is loaded.
            "CASE WHEN s.action = 'add' THEN 0 ELSE (i.content_hash IS NOT NULL AND i.content_hash <> s.base_hash) END AS stale, ",
            "CASE WHEN s.action = 'add' THEN (s.parent_id IS NOT NULL AND p.item_id IS NULL) ELSE (i.content_hash IS NULL) END AS gone, ",
            "s.parent_kind, s.parent_id, (s.action = 'add' AND i.content_hash IS NOT NULL) AS landed ",
            "FROM suggestions s LEFT JOIN users u ON u.email = s.author ",
            "LEFT JOIN items i ON i.dataset = s.dataset AND i.kind = s.kind AND i.item_id = s.item_id ",
            "LEFT JOIN items p ON p.dataset = s.dataset AND p.kind = s.parent_kind AND p.item_id = s.parent_id ",
            $where,
            " ",
            $order
        )
    };
}

macro_rules! comments_where {
    ($where:literal) => {
        concat!(
            "SELECT c.suggestion_id, IFNULL(u.display_name, '') AS author_name, c.body, c.created_at ",
            "FROM comments c LEFT JOIN users u ON u.email = c.author WHERE c.suggestion_id IN (SELECT s.id FROM suggestions s ",
            $where,
            ") ORDER BY c.id"
        )
    };
}

/// ?1 viewer, ?2 id.
pub const SELECT_SUGGESTION: &str = suggestions_where!("WHERE s.id = ?2", "");
pub const SELECT_SUGGESTION_COMMENTS: &str = comments_where!("WHERE s.id = ?2 AND ?1 IS NOT NULL");
/// ?1 viewer, ?2 dataset, ?3 entry id. Every status, newest first.
pub const SELECT_ENTRY_SUGGESTIONS: &str = suggestions_where!(
    "WHERE s.dataset = ?2 AND s.entry_id = ?3",
    "ORDER BY s.id DESC"
);
pub const SELECT_ENTRY_COMMENTS: &str =
    comments_where!("WHERE s.dataset = ?2 AND s.entry_id = ?3 AND ?1 IS NOT NULL");
/// ?1 viewer, ?2 dataset. Suggested new entries, not withdrawn, newest first.
pub const SELECT_ADDITIONS: &str = suggestions_where!(
    "WHERE s.dataset = ?2 AND s.action = 'add' AND s.kind = 'entry' AND s.status <> 'withdrawn'",
    "ORDER BY s.id DESC"
);
pub const SELECT_ADDITIONS_COMMENTS: &str = comments_where!(
    "WHERE s.dataset = ?2 AND s.action = 'add' AND s.kind = 'entry' AND ?1 IS NOT NULL"
);
/// ?1 viewer, ?2 status. Oldest first.
pub const SELECT_INBOX: &str = suggestions_where!("WHERE s.status = ?2", "ORDER BY s.id");
pub const SELECT_INBOX_COMMENTS: &str = comments_where!("WHERE s.status = ?2 AND ?1 IS NOT NULL");

/// ?1 viewer, ?2 dataset, ?3 entry id.
pub const SELECT_ENTRY_APPROVALS: &str = "SELECT a.kind, a.item_id, IFNULL(u.display_name, '') AS reviewer_name, \
     (a.reviewer = ?1) AS mine, (i.content_hash IS NOT NULL AND i.content_hash = a.content_hash) AS current, a.created_at \
     FROM approvals a LEFT JOIN users u ON u.email = a.reviewer \
     LEFT JOIN items i ON i.dataset = a.dataset AND i.kind = a.kind AND i.item_id = a.item_id \
     WHERE a.dataset = ?2 AND a.entry_id = ?3 ORDER BY a.created_at, a.reviewer";

/// ?1 dataset. Per entry: targets with a current approval, and open suggestions.
pub const SELECT_REVIEW_COUNTS: &str = "SELECT e.item_id AS entry_id, \
     (SELECT COUNT(*) FROM items t WHERE t.dataset = e.dataset AND t.entry_id = e.item_id AND EXISTS \
       (SELECT 1 FROM approvals a WHERE a.dataset = t.dataset AND a.kind = t.kind AND a.item_id = t.item_id \
        AND a.content_hash = t.content_hash)) AS approved, \
     (SELECT COUNT(*) FROM suggestions s WHERE s.dataset = e.dataset AND s.entry_id = e.item_id AND s.status = 'open') AS open \
     FROM items e WHERE e.dataset = ?1 AND e.kind = 'entry' ORDER BY e.position";

// Queue progress. `qi` is a queue_items row and ?1 the viewer.
macro_rules! gone {
    () => {
        "NOT EXISTS (SELECT 1 FROM items i WHERE i.dataset = qi.dataset AND i.kind = qi.kind AND i.item_id = qi.item_id)"
    };
}
macro_rules! approved_by_viewer {
    () => {
        "EXISTS (SELECT 1 FROM approvals a JOIN items i ON i.dataset = a.dataset AND i.kind = a.kind AND i.item_id = a.item_id \
         WHERE a.dataset = qi.dataset AND a.kind = qi.kind AND a.item_id = qi.item_id AND a.reviewer = ?1 \
         AND a.content_hash = i.content_hash)"
    };
}
macro_rules! suggested_by_viewer {
    () => {
        "EXISTS (SELECT 1 FROM suggestions s WHERE s.dataset = qi.dataset AND s.kind = qi.kind AND s.item_id = qi.item_id \
         AND s.author = ?1 AND s.status IN ('open', 'accepted'))"
    };
}
macro_rules! skipped_by_viewer {
    () => {
        "EXISTS (SELECT 1 FROM skips k WHERE k.queue_id = qi.queue_id AND k.dataset = qi.dataset AND k.kind = qi.kind \
         AND k.item_id = qi.item_id AND k.reviewer = ?1)"
    };
}
macro_rules! queue_summary {
    ($where:literal) => {
        concat!(
            "SELECT q.id, q.title, q.description, q.archived, COUNT(qi.item_id) AS total, ",
            "IFNULL(SUM(CASE WHEN qi.item_id IS NOT NULL AND (",
            gone!(),
            " OR ",
            approved_by_viewer!(),
            " OR ",
            suggested_by_viewer!(),
            " OR ",
            skipped_by_viewer!(),
            ") THEN 1 ELSE 0 END), 0) AS done, ",
            "IFNULL(SUM(CASE WHEN EXISTS (SELECT 1 FROM suggestions s WHERE s.dataset = qi.dataset AND s.kind = qi.kind ",
            "AND s.item_id = qi.item_id AND s.status = 'open') THEN 1 ELSE 0 END), 0) AS with_suggestion ",
            "FROM queues q LEFT JOIN queue_items qi ON qi.queue_id = q.id ",
            $where,
            " GROUP BY q.id ORDER BY q.id DESC"
        )
    };
}

/// ?1 viewer, ?2 1 to include archived queues. Newest first.
pub const SELECT_QUEUES: &str = queue_summary!("WHERE (?2 = 1 OR q.archived = 0)");
/// ?1 viewer, ?2 queue id.
pub const SELECT_QUEUE: &str = queue_summary!("WHERE q.id = ?2");
/// ?1 viewer, ?2 queue id. In position order.
pub const SELECT_QUEUE_ITEMS: &str = concat!(
    "SELECT qi.dataset, qi.kind, qi.item_id, qi.entry_id, qi.item_title AS title, qi.note, qi.position, (",
    gone!(),
    ") AS gone, CASE WHEN ",
    approved_by_viewer!(),
    " THEN 'approved' WHEN ",
    suggested_by_viewer!(),
    " THEN 'suggested' WHEN ",
    skipped_by_viewer!(),
    " THEN 'skipped' END AS mine FROM queue_items qi WHERE qi.queue_id = ?2 ORDER BY qi.position"
);

/// The items a `QueueFilter` picks, as `i`, in file order. ?1 dataset, ?2 kinds, ?3 levels, ?4 never
/// approved, ?5 ids (JSON arrays). A part's level is its own, else its entry's.
macro_rules! filter_from {
    () => {
        "FROM items i JOIN items e ON e.dataset = i.dataset AND e.kind = 'entry' AND e.item_id = i.entry_id \
         WHERE i.dataset = ?1 \
         AND (json_array_length(?2) = 0 OR i.kind IN (SELECT value FROM json_each(?2))) \
         AND (json_array_length(?3) = 0 OR IFNULL(i.jlpt, e.jlpt) IN (SELECT value FROM json_each(?3))) \
         AND (?4 = 0 OR NOT EXISTS (SELECT 1 FROM approvals a WHERE a.dataset = i.dataset AND a.kind = i.kind AND a.item_id = i.item_id)) \
         AND (json_array_length(?5) = 0 OR i.item_id IN (SELECT value FROM json_each(?5)))"
    };
}

pub const SELECT_FILTERED: &str = concat!(
    "SELECT i.dataset, i.kind, i.item_id, i.entry_id, i.title, '' AS note, i.position, 0 AS gone, NULL AS mine ",
    filter_from!(),
    " ORDER BY i.position"
);
/// ?1 title, ?2 description, ?3 by, ?4 now.
pub const INSERT_QUEUE: &str = "INSERT INTO queues (title, description, created_by, created_at) \
     VALUES (?1, ?2, ?3, ?4) RETURNING id";
/// Fills the queue just inserted by ?6 (the creator) in this batch.
pub const INSERT_QUEUE_ITEMS: &str = concat!(
    "INSERT INTO queue_items (queue_id, dataset, kind, item_id, entry_id, item_title, position) ",
    "SELECT (SELECT MAX(id) FROM queues WHERE created_by = ?6), i.dataset, i.kind, i.item_id, i.entry_id, i.title, i.position ",
    filter_from!()
);
/// ?1 now, ?2 by, ?3 detail.
pub const INSERT_QUEUE_AUDIT: &str = "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, 'queue.add', 'queue/' || MAX(id), ?3 FROM queues WHERE created_by = ?2";

pub const SELECT_QUEUE_EXISTS: &str = "SELECT id FROM queues WHERE id = ?1";
/// ?1 id, ?2 title, ?3 description, ?4 archived.
pub const UPDATE_QUEUE: &str =
    "UPDATE queues SET title = ?2, description = ?3, archived = ?4 WHERE id = ?1";
/// ?1 queue, ?2–?4 target.
pub const SELECT_QUEUE_ITEM_EXISTS: &str = "SELECT queue_id AS id FROM queue_items WHERE queue_id = ?1 AND dataset = ?2 AND kind = ?3 AND item_id = ?4";
/// ?1 queue, ?2–?4 target, ?5 note.
pub const UPDATE_QUEUE_NOTE: &str = "UPDATE queue_items SET note = ?5 WHERE queue_id = ?1 AND dataset = ?2 AND kind = ?3 AND item_id = ?4";
pub const DELETE_QUEUE_ITEM: &str =
    "DELETE FROM queue_items WHERE queue_id = ?1 AND dataset = ?2 AND kind = ?3 AND item_id = ?4";
/// ?1 queue, ?2–?4 target, ?5 reviewer, ?6 now.
pub const INSERT_SKIP: &str =
    "INSERT OR IGNORE INTO skips (queue_id, dataset, kind, item_id, reviewer, created_at) \
     VALUES (?1, ?2, ?3, ?4, ?5, ?6)";

/// Review data. `viewer` is the asking user's email, used only for `mine` and queue progress; names come
/// from `users.display_name`. Every write inserts its audit row in the same batch (actions
/// `approval.add|remove`, `suggestion.add|withdraw|accept|decline`, `comment.add`,
/// `queue.add|update|note|remove_item|skip`).
#[allow(async_fn_in_trait)]
pub trait ReviewStore {
    /// `(content_hash, entry_id, title)` of a loaded target.
    async fn current_hash(
        &self,
        t: &Target,
    ) -> Result<Option<(String, String, String)>, StoreError>;
    /// Records (or replaces) the reviewer's approval of the target at `hash`.
    async fn approve(
        &self,
        t: &Target,
        hash: &str,
        reviewer: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    async fn unapprove(&self, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError>;
    /// The entry and its parts, in file order; empty when the entry isn't loaded.
    async fn parts(&self, dataset: &str, entry_id: &str) -> Result<Vec<Part>, StoreError>;
    /// Stores a suggestion and returns `(id, true)`, or `(id, false)` for an identical open one by the
    /// same author.
    async fn add_suggestion(
        &self,
        s: &NewSuggestion,
        author: &str,
        now: &str,
    ) -> Result<(i64, bool), StoreError>;
    async fn suggestion(&self, id: i64, viewer: &str) -> Result<Option<Suggestion>, StoreError>;
    /// Whether a loaded item, or an open or accepted addition, in the dataset uses `id`.
    async fn id_in_use(&self, dataset: &str, id: &str) -> Result<bool, StoreError>;
    /// The ids the dataset's loaded items use, and the ids its open and accepted additions use.
    async fn ids_taken(
        &self,
        dataset: &str,
    ) -> Result<(BTreeSet<String>, BTreeSet<String>), StoreError>;
    /// The open addition of `(dataset, kind, item_id)`, if any.
    async fn open_add_for(
        &self,
        dataset: &str,
        kind: &str,
        item_id: &str,
    ) -> Result<Option<i64>, StoreError>;
    /// Suggested new entries in a dataset, not withdrawn, newest first.
    async fn additions(&self, dataset: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError>;
    /// `NotFound` unless the suggestion is open; `Conflict` if it isn't the author's.
    async fn withdraw(&self, id: i64, author: &str, now: &str) -> Result<(), StoreError>;
    /// `NotFound` for an unknown id; `Conflict` unless it is open. `furigana_json`, when given, replaces
    /// the readings the reviewer proposed.
    async fn decide(
        &self,
        id: i64,
        accept: bool,
        edit: OwnerEdit<'_>,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    /// `NotFound` for an unknown suggestion.
    async fn add_comment(
        &self,
        suggestion_id: i64,
        body: &str,
        author: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    /// The entry's approvals, and its suggestions in every status, newest first.
    async fn entry_review(
        &self,
        dataset: &str,
        entry_id: &str,
        viewer: &str,
    ) -> Result<(Vec<Approval>, Vec<Suggestion>), StoreError>;
    async fn stamp_readiness(
        &self,
        dataset: &str,
        entry_id: &str,
    ) -> Result<StampReadiness, StoreError>;
    async fn pending_stamp(&self, t: &Target) -> Result<Option<Stamp>, StoreError>;
    async fn ready_to_stamp(&self) -> Result<Vec<ReadyEntry>, StoreError>;
    /// Accepted suggestions and stamps not yet exported, oldest first.
    async fn export_batch(&self) -> Result<(Vec<ExportRow>, Vec<Stamp>), StoreError>;
    /// Marks those still waiting as exported (audit row `export.mark`); returns how many of each changed.
    async fn mark_exported(
        &self,
        suggestions: &[i64],
        stamps: &[i64],
        actor: &str,
        now: &str,
    ) -> Result<(usize, usize), StoreError>;
    /// Stores a pending stamp with its audit row (`stamp.add`); a pending one for the target is kept.
    async fn add_stamp(&self, s: &NewStamp, actor: &str, now: &str) -> Result<(), StoreError>;
    /// Deletes the pending stamp (audit row `stamp.withdraw`); false when there was none.
    async fn withdraw_stamp(&self, t: &Target, actor: &str, now: &str) -> Result<bool, StoreError>;
    /// Suggestions in a status, oldest first.
    async fn inbox(&self, status: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError>;
    /// `(entry_id, approved targets, open suggestions)` per entry of a dataset.
    async fn review_counts(&self, dataset: &str) -> Result<Vec<(String, u32, u32)>, StoreError>;
    /// Newest first. An item is done for the viewer when they have a current approval of it, an open or
    /// accepted suggestion on it, or skipped it in this queue, or when it left the data.
    async fn queues(
        &self,
        viewer: &str,
        include_archived: bool,
    ) -> Result<Vec<QueueSummary>, StoreError>;
    async fn queue(
        &self,
        id: i64,
        viewer: &str,
    ) -> Result<Option<(QueueSummary, Vec<QueueItem>)>, StoreError>;
    /// The items a filter picks, in file order.
    async fn preview_queue(&self, f: &QueueFilter) -> Result<Vec<QueueItem>, StoreError>;
    async fn add_queue(
        &self,
        title: &str,
        description: &str,
        f: &QueueFilter,
        by: &str,
        now: &str,
    ) -> Result<i64, StoreError>;
    async fn update_queue(
        &self,
        id: i64,
        title: &str,
        description: &str,
        archived: bool,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    /// `NotFound` when the target isn't in the queue.
    async fn set_queue_note(
        &self,
        id: i64,
        t: &Target,
        note: &str,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    async fn remove_queue_item(
        &self,
        id: i64,
        t: &Target,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError>;
    /// `NotFound` when the target isn't in the queue.
    async fn skip(&self, id: i64, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError>;
}
