//! A `Store` over an in-memory SQLite database, running the same migrations and SQL as the D1 store.

use review_api::store::{
    NewUser, Role, Store, StoreError, User, INSERT_AUDIT, INSERT_USER, SELECT_USER, SELECT_USERS,
    UPDATE_ACTIVE, UPDATE_DISPLAY_NAME,
};
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
}
