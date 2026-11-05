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

impl SqliteStore {
    pub fn new() -> Self {
        let conn = Connection::open_in_memory().unwrap();
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("migrations");
        let mut files: Vec<_> = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .collect();
        files.sort();
        for file in files {
            conn.execute_batch(&std::fs::read_to_string(file).unwrap())
                .unwrap();
        }
        SqliteStore {
            conn: RefCell::new(conn),
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
