//! The `Store` over D1, with the SQL from `store.rs`. Each change and its audit row go in one batch, which
//! D1 runs as a transaction.

use crate::store::{
    NewUser, Role, Store, StoreError, User, INSERT_AUDIT, INSERT_USER, SELECT_USER, SELECT_USERS,
    UPDATE_ACTIVE, UPDATE_DISPLAY_NAME,
};
use serde::Deserialize;
use worker::wasm_bindgen::JsValue;
use worker::D1Database;

pub struct D1Store {
    pub db: D1Database,
}

#[derive(Deserialize)]
struct Row {
    email: String,
    display_name: String,
    role: String,
    active: i64,
}

impl Row {
    fn into_user(self) -> Result<User, StoreError> {
        let role = Role::parse(&self.role)
            .ok_or_else(|| StoreError::Backend(format!("unknown role {:?}", self.role)))?;
        Ok(User {
            email: self.email,
            display_name: self.display_name,
            role,
            active: self.active == 1,
        })
    }
}

fn backend(error: worker::Error) -> StoreError {
    let text = error.to_string();
    if text.contains("UNIQUE constraint failed") || text.contains("PRIMARY KEY") {
        StoreError::Conflict
    } else {
        StoreError::Backend(text)
    }
}

fn audit(
    db: &D1Database,
    now: &str,
    actor: &str,
    action: &str,
    target: &str,
    detail: &str,
) -> Result<worker::D1PreparedStatement, StoreError> {
    db.prepare(INSERT_AUDIT)
        .bind(&[
            now.into(),
            actor.into(),
            action.into(),
            target.into(),
            detail.into(),
        ])
        .map_err(backend)
}

impl Store for D1Store {
    async fn user(&self, email: &str) -> Result<Option<User>, StoreError> {
        let statement = self
            .db
            .prepare(SELECT_USER)
            .bind(&[email.into()])
            .map_err(backend)?;
        match statement.first::<Row>(None).await.map_err(backend)? {
            Some(row) => row.into_user().map(Some),
            None => Ok(None),
        }
    }

    async fn users(&self) -> Result<Vec<User>, StoreError> {
        let result = self.db.prepare(SELECT_USERS).all().await.map_err(backend)?;
        let rows: Vec<Row> = result.results().map_err(backend)?;
        rows.into_iter().map(Row::into_user).collect()
    }

    async fn add_user(&self, user: &NewUser, actor: &str, now: &str) -> Result<(), StoreError> {
        let insert = self
            .db
            .prepare(INSERT_USER)
            .bind(&[
                user.email.as_str().into(),
                user.display_name.as_str().into(),
                user.role.as_str().into(),
                now.into(),
            ])
            .map_err(backend)?;
        let detail = format!("role={}", user.role.as_str());
        let log = audit(&self.db, now, actor, "user.add", &user.email, &detail)?;
        self.db.batch(vec![insert, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn set_active(
        &self,
        email: &str,
        active: bool,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        // A batch can't skip its audit row when the UPDATE matches nothing, so look the user up first.
        if self.user(email).await?.is_none() {
            return Err(StoreError::NotFound);
        }
        let flag = if active { 1 } else { 0 };
        let update = self
            .db
            .prepare(UPDATE_ACTIVE)
            .bind(&[JsValue::from(flag), email.into()])
            .map_err(backend)?;
        let log = audit(
            &self.db,
            now,
            actor,
            "user.active",
            email,
            &format!("active={flag}"),
        )?;
        self.db.batch(vec![update, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn set_display_name(
        &self,
        email: &str,
        display_name: &str,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        // As in set_active: look the user up first, since the batch always writes its audit row.
        if self.user(email).await?.is_none() {
            return Err(StoreError::NotFound);
        }
        let update = self
            .db
            .prepare(UPDATE_DISPLAY_NAME)
            .bind(&[display_name.into(), email.into()])
            .map_err(backend)?;
        let detail = format!("name={display_name}");
        let log = audit(&self.db, now, actor, "user.name", email, &detail)?;
        self.db.batch(vec![update, log]).await.map_err(backend)?;
        Ok(())
    }
}
