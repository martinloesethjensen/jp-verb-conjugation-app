//! A `Store` over an in-memory SQLite database, running the same migrations and SQL as the D1 store.

use review_api::items::ItemRow;
use review_api::store::*;
use rusqlite::{params, Connection, ErrorCode};
use std::cell::RefCell;
use std::path::Path;

pub struct SqliteStore {
    pub conn: RefCell<Connection>,
}

impl Default for SqliteStore {
    fn default() -> Self {
        Self::new()
    }
}

/// One migration in one transaction, as D1 applies it (so `PRAGMA defer_foreign_keys` holds).
fn run_migration(conn: &Connection, file: &Path) {
    let sql = std::fs::read_to_string(file).unwrap();
    conn.execute_batch(&format!("BEGIN;\n{sql}\nCOMMIT;"))
        .unwrap_or_else(|e| panic!("{}: {e}", file.display()));
}

impl SqliteStore {
    pub fn new() -> Self {
        // "~" sorts after every migration file name, so this applies them all.
        Self::with_migrations_before("~")
    }

    /// The migration files whose names sort before (or, `from`, at and after) `name`.
    fn migrations(keep: impl Fn(&str) -> bool) -> Vec<std::path::PathBuf> {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("migrations");
        let mut files: Vec<_> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| keep(&p.file_name().unwrap().to_string_lossy()))
            .collect();
        files.sort();
        files
    }

    /// A store with only the migrations whose file names sort before `name` (e.g. `"0005"`).
    pub fn with_migrations_before(name: &str) -> Self {
        let conn = Connection::open_in_memory().unwrap();
        for file in Self::migrations(|f| f < name) {
            run_migration(&conn, &file);
        }
        SqliteStore {
            conn: RefCell::new(conn),
        }
    }

    /// Applies the migrations whose file names sort at or after `name`.
    pub fn apply_migrations_from(&self, name: &str) {
        let conn = self.conn.borrow();
        for file in Self::migrations(|f| f >= name) {
            run_migration(&conn, &file);
        }
    }
}

fn role(text: String) -> Role {
    match text.as_str() {
        "admin" => Role::Admin,
        _ => Role::Reviewer,
    }
}

fn row_to_user(row: &rusqlite::Row) -> rusqlite::Result<User> {
    Ok(User {
        email: row.get(0)?,
        display_name: row.get(1)?,
        role: role(row.get(2)?),
        active: row.get::<_, i64>(3)? == 1,
    })
}

fn row_to_snapshot(row: &rusqlite::Row) -> rusqlite::Result<SnapshotFile> {
    Ok(SnapshotFile {
        name: row.get(0)?,
        version: row.get(1)?,
        sha256: row.get(2)?,
        git_ref: row.get(3)?,
        item_count: row.get(4)?,
        imported_at: row.get(5)?,
        imported_by: row.get(6)?,
    })
}

fn backend(error: rusqlite::Error) -> StoreError {
    match error.sqlite_error_code() {
        Some(ErrorCode::ConstraintViolation) => StoreError::Conflict,
        _ => StoreError::Backend(error.to_string()),
    }
}

impl Store for SqliteStore {
    async fn user(&self, email: &str) -> Result<Option<User>, StoreError> {
        let conn = self.conn.borrow();
        let mut statement = conn.prepare(SELECT_USER).map_err(backend)?;
        let mut rows = statement
            .query_map(params![email], row_to_user)
            .map_err(backend)?;
        rows.next().transpose().map_err(backend)
    }

    async fn users(&self) -> Result<Vec<User>, StoreError> {
        let conn = self.conn.borrow();
        let mut statement = conn.prepare(SELECT_USERS).map_err(backend)?;
        let rows = statement.query_map([], row_to_user).map_err(backend)?;
        rows.collect::<Result<_, _>>().map_err(backend)
    }

    async fn add_user(&self, user: &NewUser, actor: &str, now: &str) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            INSERT_USER,
            params![user.email, user.display_name, user.role.as_str(), now],
        )
        .map_err(backend)?;
        tx.execute(
            INSERT_AUDIT,
            params![
                now,
                actor,
                "user.add",
                user.email,
                format!("role={}", user.role.as_str())
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn set_active(
        &self,
        email: &str,
        active: bool,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        let changed = tx
            .execute(UPDATE_ACTIVE, params![active as i64, email])
            .map_err(backend)?;
        if changed == 0 {
            return Err(StoreError::NotFound);
        }
        tx.execute(
            INSERT_AUDIT,
            params![
                now,
                actor,
                "user.active",
                email,
                format!("active={}", active as i64)
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn set_display_name(
        &self,
        email: &str,
        display_name: &str,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        let changed = tx
            .execute(UPDATE_DISPLAY_NAME, params![display_name, email])
            .map_err(backend)?;
        if changed == 0 {
            return Err(StoreError::NotFound);
        }
        tx.execute(
            INSERT_AUDIT,
            params![
                now,
                actor,
                "user.name",
                email,
                format!("name={display_name}")
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn replace_snapshot(
        &self,
        file: &SnapshotFile,
        json: Option<&str>,
        rows: &[ItemRow],
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let rows_json = serde_json::to_string(rows).unwrap();
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(DELETE_ITEMS, params![file.name])
            .map_err(backend)?;
        tx.execute(INSERT_ITEMS, params![file.name, rows_json])
            .map_err(backend)?;
        tx.execute(
            UPSERT_SNAPSHOT_FILE,
            params![
                file.name,
                file.version,
                file.sha256,
                file.git_ref,
                file.item_count,
                file.imported_at,
                file.imported_by,
                json
            ],
        )
        .map_err(backend)?;
        let target = format!("{}.json", file.name);
        tx.execute(
            INSERT_AUDIT,
            params![
                now,
                actor,
                "snapshot.import",
                target,
                format!("version={}", file.version)
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn snapshot_files(&self) -> Result<Vec<SnapshotFile>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_SNAPSHOT_FILES).map_err(backend)?;
        let rows = st.query_map([], row_to_snapshot).map_err(backend)?;
        rows.collect::<Result<_, _>>().map_err(backend)
    }

    async fn snapshot_file(&self, name: &str) -> Result<Option<SnapshotFile>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_SNAPSHOT_FILE).map_err(backend)?;
        let mut rows = st
            .query_map(params![name], row_to_snapshot)
            .map_err(backend)?;
        rows.next().transpose().map_err(backend)
    }

    async fn snapshot_json(&self, name: &str) -> Result<Option<String>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_SNAPSHOT_JSON).map_err(backend)?;
        let mut rows = st.query_map(params![name], |r| r.get(0)).map_err(backend)?;
        rows.next().transpose().map_err(backend)
    }

    async fn entries(&self, dataset: &str) -> Result<Vec<ItemSummary>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_ENTRIES).map_err(backend)?;
        let rows = st
            .query_map(params![dataset], |r| {
                Ok(ItemSummary {
                    item_id: r.get(0)?,
                    title: r.get(1)?,
                    subtitle: r.get(2)?,
                    jlpt: r.get(3)?,
                    parts: r.get(4)?,
                })
            })
            .map_err(backend)?;
        rows.collect::<Result<_, _>>().map_err(backend)
    }

    async fn entry(
        &self,
        dataset: &str,
        item_id: &str,
    ) -> Result<Option<(String, String)>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_ENTRY).map_err(backend)?;
        let mut rows = st
            .query_map(params![dataset, item_id], |r| Ok((r.get(0)?, r.get(1)?)))
            .map_err(backend)?;
        rows.next().transpose().map_err(backend)
    }

    async fn begin_load(&self, load: &SnapshotLoad) -> Result<(), StoreError> {
        let slices = serde_json::to_string(&load.slices).unwrap();
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        for sql in [
            DELETE_STAGING_FOR_NAME,
            DELETE_SLICES_FOR_NAME,
            DELETE_LOADS_FOR_NAME,
        ] {
            tx.execute(sql, params![load.name]).map_err(backend)?;
        }
        tx.execute(
            INSERT_LOAD,
            params![
                load.load_id,
                load.name,
                load.version,
                load.sha256,
                load.git_ref,
                slices,
                load.started_by,
                load.started_at
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn load(&self, load_id: &str) -> Result<Option<SnapshotLoad>, StoreError> {
        let conn = self.conn.borrow();
        let mut st = conn.prepare(SELECT_LOAD).map_err(backend)?;
        let mut rows = st
            .query_map(params![load_id], |r| {
                let slices: String = r.get(5)?;
                Ok(SnapshotLoad {
                    load_id: r.get(0)?,
                    name: r.get(1)?,
                    version: r.get(2)?,
                    sha256: r.get(3)?,
                    git_ref: r.get(4)?,
                    slices: serde_json::from_str(&slices).unwrap(),
                    started_by: r.get(6)?,
                    started_at: r.get(7)?,
                })
            })
            .map_err(backend)?;
        rows.next().transpose().map_err(backend)
    }

    async fn stage_slice(
        &self,
        load: &SnapshotLoad,
        slice: u32,
        rows: &[ItemRow],
    ) -> Result<(), StoreError> {
        let rows_json = serde_json::to_string(rows).unwrap();
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(DELETE_STAGED_SLICE, params![load.load_id, slice])
            .map_err(backend)?;
        tx.execute(
            INSERT_STAGED,
            params![load.load_id, slice, load.name, rows_json],
        )
        .map_err(backend)?;
        tx.execute(INSERT_SLICE_DONE, params![load.load_id, slice])
            .map_err(backend)?;
        tx.commit().map_err(backend)
    }

    async fn slices_done(&self, load_id: &str) -> Result<u32, StoreError> {
        let conn = self.conn.borrow();
        conn.query_row(COUNT_SLICES_DONE, params![load_id], |r| r.get(0))
            .map_err(backend)
    }

    async fn finish_load(
        &self,
        load: &SnapshotLoad,
        file: &SnapshotFile,
        json: Option<&str>,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(DELETE_ITEMS_FOR_LOAD, params![file.name, load.load_id])
            .map_err(backend)?;
        tx.execute(INSERT_ITEMS_FROM_STAGING, params![load.load_id])
            .map_err(backend)?;
        tx.execute(
            UPSERT_SNAPSHOT_FILE_FOR_LOAD,
            params![
                file.name,
                file.version,
                file.sha256,
                file.git_ref,
                file.item_count,
                file.imported_at,
                file.imported_by,
                json,
                load.load_id
            ],
        )
        .map_err(backend)?;
        let target = format!("{}.json", file.name);
        let detail = format!("version={}", file.version);
        tx.execute(
            INSERT_AUDIT_FOR_LOAD,
            params![now, actor, "snapshot.import", target, detail, load.load_id],
        )
        .map_err(backend)?;
        tx.execute(DELETE_STAGING, params![load.load_id])
            .map_err(backend)?;
        tx.execute(DELETE_SLICES, params![load.load_id])
            .map_err(backend)?;
        if tx
            .execute(DELETE_LOAD, params![load.load_id])
            .map_err(backend)?
            == 0
        {
            return Err(StoreError::NotFound); // every statement above was a no-op
        }
        tx.commit().map_err(backend)
    }
}

// --- ReviewStore ----------------------------------------------------------------------------------

use review_api::review_store::*;
use rusqlite::types::ValueRef;
use rusqlite::Transaction;
use serde::de::DeserializeOwned;

/// Rows as `T`, read by column name, the way D1 hands them to serde.
fn query<T: DeserializeOwned>(
    conn: &Connection,
    sql: &str,
    params: impl rusqlite::Params,
) -> Result<Vec<T>, StoreError> {
    let mut st = conn.prepare(sql).map_err(backend)?;
    let names: Vec<String> = st.column_names().map(|n| n.to_string()).collect();
    let rows = st
        .query_map(params, |row| {
            let mut map = serde_json::Map::new();
            for (i, name) in names.iter().enumerate() {
                let value = match row.get_ref(i)? {
                    ValueRef::Null => serde_json::Value::Null,
                    ValueRef::Integer(n) => n.into(),
                    ValueRef::Real(f) => f.into(),
                    ValueRef::Text(t) => String::from_utf8_lossy(t).into_owned().into(),
                    ValueRef::Blob(_) => serde_json::Value::Null,
                };
                map.insert(name.clone(), value);
            }
            Ok(serde_json::Value::Object(map))
        })
        .map_err(backend)?;
    rows.map(|r| {
        let value = r.map_err(backend)?;
        serde_json::from_value(value).map_err(|e| StoreError::Backend(e.to_string()))
    })
    .collect()
}

fn audit_tx(
    tx: &Transaction,
    now: &str,
    actor: &str,
    action: &str,
    target: &str,
    detail: &str,
) -> Result<(), StoreError> {
    tx.execute(INSERT_AUDIT, params![now, actor, action, target, detail])
        .map_err(backend)?;
    Ok(())
}

impl SqliteStore {
    fn exists(&self, sql: &str, params: impl rusqlite::Params) -> Result<bool, StoreError> {
        let conn = self.conn.borrow();
        Ok(!query::<IdRow>(&conn, sql, params)?.is_empty())
    }
}

impl ReviewStore for SqliteStore {
    async fn current_hash(
        &self,
        t: &Target,
    ) -> Result<Option<(String, String, String)>, StoreError> {
        let conn = self.conn.borrow();
        let rows: Vec<HashRow> = query(&conn, SELECT_HASH, params![t.dataset, t.kind, t.item_id])?;
        Ok(rows
            .into_iter()
            .next()
            .map(|r| (r.content_hash, r.entry_id, r.title)))
    }

    async fn approve(
        &self,
        t: &Target,
        hash: &str,
        reviewer: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            UPSERT_APPROVAL,
            params![t.dataset, t.kind, t.item_id, reviewer, hash, now],
        )
        .map_err(backend)?;
        audit_tx(
            &tx,
            now,
            reviewer,
            "approval.add",
            &t.audit_name(),
            &format!("hash={hash}"),
        )?;
        tx.commit().map_err(backend)
    }

    async fn unapprove(&self, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            DELETE_APPROVAL,
            params![t.dataset, t.kind, t.item_id, reviewer],
        )
        .map_err(backend)?;
        audit_tx(&tx, now, reviewer, "approval.remove", &t.audit_name(), "")?;
        tx.commit().map_err(backend)
    }

    async fn parts(&self, dataset: &str, entry_id: &str) -> Result<Vec<Part>, StoreError> {
        let conn = self.conn.borrow();
        query(&conn, SELECT_PARTS, params![dataset, entry_id])
    }

    async fn id_in_use(&self, dataset: &str, id: &str) -> Result<bool, StoreError> {
        let conn = self.conn.borrow();
        Ok(!query::<IdRow>(&conn, SELECT_ID_IN_USE, params![dataset, id])?.is_empty())
    }

    async fn ids_taken(
        &self,
        dataset: &str,
    ) -> Result<
        (
            std::collections::BTreeSet<String>,
            std::collections::BTreeSet<String>,
        ),
        StoreError,
    > {
        let conn = self.conn.borrow();
        let loaded: Vec<ItemIdRow> = query(&conn, SELECT_LOADED_IDS, params![dataset])?;
        let suggested: Vec<ItemIdRow> = query(&conn, SELECT_SUGGESTED_IDS, params![dataset])?;
        Ok((
            loaded.into_iter().map(|r| r.item_id).collect(),
            suggested.into_iter().map(|r| r.item_id).collect(),
        ))
    }

    async fn open_add_for(
        &self,
        dataset: &str,
        kind: &str,
        item_id: &str,
    ) -> Result<Option<i64>, StoreError> {
        let conn = self.conn.borrow();
        let rows: Vec<IdRow> = query(&conn, SELECT_OPEN_ADD, params![dataset, kind, item_id])?;
        Ok(rows.first().map(|r| r.id))
    }

    async fn additions(&self, dataset: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError> {
        let conn = self.conn.borrow();
        let rows = query(&conn, SELECT_ADDITIONS, params![viewer, dataset])?;
        let comments = query(&conn, SELECT_ADDITIONS_COMMENTS, params![viewer, dataset])?;
        Ok(assemble(rows, comments))
    }

    async fn add_suggestion(
        &self,
        s: &NewSuggestion,
        author: &str,
        now: &str,
    ) -> Result<(i64, bool), StoreError> {
        let t = &s.target;
        let mut conn = self.conn.borrow_mut();
        let existing: Vec<IdRow> = if s.action == "add" {
            query(
                &conn,
                SELECT_IDENTICAL_ADD,
                params![
                    t.dataset,
                    t.kind,
                    s.parent_id,
                    author,
                    s.fingerprint,
                    s.furigana_json,
                    s.comment
                ],
            )?
        } else {
            query(
                &conn,
                SELECT_IDENTICAL_OPEN,
                params![
                    s.action,
                    t.dataset,
                    t.kind,
                    t.item_id,
                    author,
                    s.proposed_json,
                    s.furigana_json,
                    s.comment
                ],
            )?
        };
        if let Some(row) = existing.into_iter().next() {
            return Ok((row.id, false));
        }
        let tx = conn.transaction().map_err(backend)?;
        let id: i64 = tx
            .query_row(
                INSERT_SUGGESTION,
                params![
                    s.action,
                    t.dataset,
                    t.kind,
                    t.item_id,
                    s.entry_id,
                    s.item_title,
                    s.base_hash,
                    s.proposed_json,
                    s.furigana_json,
                    s.dropped_blanks,
                    s.comment,
                    author,
                    now,
                    s.parent_kind,
                    s.parent_id,
                    s.fingerprint
                ],
                |r| r.get(0),
            )
            .map_err(backend)?;
        tx.execute(
            INSERT_SUGGESTION_AUDIT,
            params![
                now,
                author,
                format!("action={} target={}", s.action, t.audit_name())
            ],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)?;
        Ok((id, true))
    }

    async fn suggestion(&self, id: i64, viewer: &str) -> Result<Option<Suggestion>, StoreError> {
        let conn = self.conn.borrow();
        let rows = query(&conn, SELECT_SUGGESTION, params![viewer, id])?;
        let comments = query(&conn, SELECT_SUGGESTION_COMMENTS, params![viewer, id])?;
        Ok(assemble(rows, comments).into_iter().next())
    }

    async fn withdraw(&self, id: i64, author: &str, now: &str) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let status: Vec<StatusRow> = query(&conn, SELECT_STATUS, params![id])?;
        match status.first() {
            Some(row) if row.status == "open" && row.author == author => {}
            Some(row) if row.status == "open" => return Err(StoreError::Conflict),
            _ => return Err(StoreError::NotFound),
        }
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(INSERT_WITHDRAW_AUDIT, params![now, author, id])
            .map_err(backend)?;
        if tx
            .execute(WITHDRAW, params![id, author, now])
            .map_err(backend)?
            == 0
        {
            return Err(StoreError::NotFound); // dropping tx rolls the audit row back
        }
        tx.commit().map_err(backend)
    }

    async fn decide(
        &self,
        id: i64,
        accept: bool,
        admin_edit_json: Option<&str>,
        furigana_json: Option<&str>,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let status: Vec<StatusRow> = query(&conn, SELECT_STATUS, params![id])?;
        match status.first() {
            None => return Err(StoreError::NotFound),
            Some(row) if row.status != "open" => return Err(StoreError::Conflict),
            Some(_) => {}
        }
        let (status, action) = if accept {
            ("accepted", "suggestion.accept")
        } else {
            ("declined", "suggestion.decline")
        };
        let detail = if admin_edit_json.is_some() {
            "edited"
        } else {
            ""
        };
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(INSERT_DECIDE_AUDIT, params![now, by, action, detail, id])
            .map_err(backend)?;
        if tx
            .execute(
                DECIDE,
                params![id, status, admin_edit_json, by, now, furigana_json],
            )
            .map_err(backend)?
            == 0
        {
            return Err(StoreError::Conflict); // dropping tx rolls the audit row back
        }
        tx.commit().map_err(backend)
    }

    async fn add_comment(
        &self,
        suggestion_id: i64,
        body: &str,
        author: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        if tx
            .execute(INSERT_COMMENT, params![suggestion_id, author, body, now])
            .map_err(backend)?
            == 0
        {
            return Err(StoreError::NotFound);
        }
        audit_tx(
            &tx,
            now,
            author,
            "comment.add",
            &format!("suggestion/{suggestion_id}"),
            "",
        )?;
        tx.commit().map_err(backend)
    }

    async fn entry_review(
        &self,
        dataset: &str,
        entry_id: &str,
        viewer: &str,
    ) -> Result<(Vec<Approval>, Vec<Suggestion>), StoreError> {
        let conn = self.conn.borrow();
        let approvals: Vec<ApprovalRow> = query(
            &conn,
            SELECT_ENTRY_APPROVALS,
            params![viewer, dataset, entry_id],
        )?;
        let rows = query(
            &conn,
            SELECT_ENTRY_SUGGESTIONS,
            params![viewer, dataset, entry_id],
        )?;
        let comments = query(
            &conn,
            SELECT_ENTRY_COMMENTS,
            params![viewer, dataset, entry_id],
        )?;
        Ok((
            approvals.into_iter().map(Approval::from).collect(),
            assemble(rows, comments),
        ))
    }

    async fn inbox(&self, status: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError> {
        let conn = self.conn.borrow();
        let rows = query(&conn, SELECT_INBOX, params![viewer, status])?;
        let comments = query(&conn, SELECT_INBOX_COMMENTS, params![viewer, status])?;
        Ok(assemble(rows, comments))
    }

    async fn review_counts(&self, dataset: &str) -> Result<Vec<(String, u32, u32)>, StoreError> {
        let conn = self.conn.borrow();
        let rows: Vec<CountRow> = query(&conn, SELECT_REVIEW_COUNTS, params![dataset])?;
        Ok(rows
            .into_iter()
            .map(|r| (r.entry_id, r.approved as u32, r.open as u32))
            .collect())
    }

    async fn queues(
        &self,
        viewer: &str,
        include_archived: bool,
    ) -> Result<Vec<QueueSummary>, StoreError> {
        let conn = self.conn.borrow();
        let rows: Vec<QueueRow> = query(
            &conn,
            SELECT_QUEUES,
            params![viewer, include_archived as i64],
        )?;
        Ok(rows.into_iter().map(QueueSummary::from).collect())
    }

    async fn queue(
        &self,
        id: i64,
        viewer: &str,
    ) -> Result<Option<(QueueSummary, Vec<QueueItem>)>, StoreError> {
        let conn = self.conn.borrow();
        let summary: Vec<QueueRow> = query(&conn, SELECT_QUEUE, params![viewer, id])?;
        let Some(summary) = summary.into_iter().next() else {
            return Ok(None);
        };
        let items: Vec<QueueItemRow> = query(&conn, SELECT_QUEUE_ITEMS, params![viewer, id])?;
        Ok(Some((
            summary.into(),
            items.into_iter().map(QueueItem::from).collect(),
        )))
    }

    async fn preview_queue(&self, f: &QueueFilter) -> Result<Vec<QueueItem>, StoreError> {
        let (a, b, c, d, e) = f.binds();
        let conn = self.conn.borrow();
        let rows: Vec<QueueItemRow> = query(&conn, SELECT_FILTERED, params![a, b, c, d, e])?;
        Ok(rows.into_iter().map(QueueItem::from).collect())
    }

    async fn add_queue(
        &self,
        title: &str,
        description: &str,
        f: &QueueFilter,
        by: &str,
        now: &str,
    ) -> Result<i64, StoreError> {
        let (a, b, c, d, e) = f.binds();
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        let id: i64 = tx
            .query_row(INSERT_QUEUE, params![title, description, by, now], |r| {
                r.get(0)
            })
            .map_err(backend)?;
        let count = tx
            .execute(INSERT_QUEUE_ITEMS, params![a, b, c, d, e, by])
            .map_err(backend)?;
        tx.execute(
            INSERT_QUEUE_AUDIT,
            params![now, by, format!("title={title} items={count}")],
        )
        .map_err(backend)?;
        tx.commit().map_err(backend)?;
        Ok(id)
    }

    async fn update_queue(
        &self,
        id: i64,
        title: &str,
        description: &str,
        archived: bool,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if !self.exists(SELECT_QUEUE_EXISTS, params![id])? {
            return Err(StoreError::NotFound);
        }
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            UPDATE_QUEUE,
            params![id, title, description, archived as i64],
        )
        .map_err(backend)?;
        let detail = format!("title={title} archived={}", archived as i64);
        audit_tx(
            &tx,
            now,
            by,
            "queue.update",
            &format!("queue/{id}"),
            &detail,
        )?;
        tx.commit().map_err(backend)
    }

    async fn set_queue_note(
        &self,
        id: i64,
        t: &Target,
        note: &str,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if !self.exists(
            SELECT_QUEUE_ITEM_EXISTS,
            params![id, t.dataset, t.kind, t.item_id],
        )? {
            return Err(StoreError::NotFound);
        }
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            UPDATE_QUEUE_NOTE,
            params![id, t.dataset, t.kind, t.item_id, note],
        )
        .map_err(backend)?;
        audit_tx(
            &tx,
            now,
            by,
            "queue.note",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        tx.commit().map_err(backend)
    }

    async fn remove_queue_item(
        &self,
        id: i64,
        t: &Target,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if !self.exists(
            SELECT_QUEUE_ITEM_EXISTS,
            params![id, t.dataset, t.kind, t.item_id],
        )? {
            return Err(StoreError::NotFound);
        }
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(DELETE_QUEUE_ITEM, params![id, t.dataset, t.kind, t.item_id])
            .map_err(backend)?;
        audit_tx(
            &tx,
            now,
            by,
            "queue.remove_item",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        tx.commit().map_err(backend)
    }

    async fn skip(&self, id: i64, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError> {
        if !self.exists(
            SELECT_QUEUE_ITEM_EXISTS,
            params![id, t.dataset, t.kind, t.item_id],
        )? {
            return Err(StoreError::NotFound);
        }
        let mut conn = self.conn.borrow_mut();
        let tx = conn.transaction().map_err(backend)?;
        tx.execute(
            INSERT_SKIP,
            params![id, t.dataset, t.kind, t.item_id, reviewer, now],
        )
        .map_err(backend)?;
        audit_tx(
            &tx,
            now,
            reviewer,
            "queue.skip",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        tx.commit().map_err(backend)
    }
}
