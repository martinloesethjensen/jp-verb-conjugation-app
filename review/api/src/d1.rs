//! The `Store` over D1, with the SQL from `store.rs`. Each change and its audit row go in one batch, which
//! D1 runs as a transaction.

use crate::items::ItemRow;
use crate::store::*;
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

    async fn replace_snapshot(
        &self,
        file: &SnapshotFile,
        json: Option<&str>,
        rows: &[ItemRow],
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let rows_json =
            serde_json::to_string(rows).map_err(|e| StoreError::Backend(e.to_string()))?;
        let name: JsValue = file.name.as_str().into();
        let delete = self
            .db
            .prepare(DELETE_ITEMS)
            .bind(std::slice::from_ref(&name))
            .map_err(backend)?;
        let insert = self
            .db
            .prepare(INSERT_ITEMS)
            .bind(&[name.clone(), rows_json.into()])
            .map_err(backend)?;
        let optional = |v: Option<&str>| v.map(JsValue::from).unwrap_or(JsValue::NULL);
        let upsert = self
            .db
            .prepare(UPSERT_SNAPSHOT_FILE)
            .bind(&[
                name,
                file.version.as_str().into(),
                file.sha256.as_str().into(),
                optional(file.git_ref.as_deref()),
                JsValue::from(file.item_count),
                file.imported_at.as_str().into(),
                file.imported_by.as_str().into(),
                optional(json),
            ])
            .map_err(backend)?;
        let target = format!("{}.json", file.name);
        let detail = format!("version={}", file.version);
        let log = audit(&self.db, now, actor, "snapshot.import", &target, &detail)?;
        self.db
            .batch(vec![delete, insert, upsert, log])
            .await
            .map_err(backend)?;
        Ok(())
    }

    async fn snapshot_files(&self) -> Result<Vec<SnapshotFile>, StoreError> {
        let result = self
            .db
            .prepare(SELECT_SNAPSHOT_FILES)
            .all()
            .await
            .map_err(backend)?;
        result.results().map_err(backend)
    }

    async fn snapshot_file(&self, name: &str) -> Result<Option<SnapshotFile>, StoreError> {
        let statement = self
            .db
            .prepare(SELECT_SNAPSHOT_FILE)
            .bind(&[name.into()])
            .map_err(backend)?;
        statement.first::<SnapshotFile>(None).await.map_err(backend)
    }

    async fn snapshot_json(&self, name: &str) -> Result<Option<String>, StoreError> {
        let statement = self
            .db
            .prepare(SELECT_SNAPSHOT_JSON)
            .bind(&[name.into()])
            .map_err(backend)?;
        statement
            .first::<String>(Some("json"))
            .await
            .map_err(backend)
    }

    async fn entries(&self, dataset: &str) -> Result<Vec<ItemSummary>, StoreError> {
        let statement = self
            .db
            .prepare(SELECT_ENTRIES)
            .bind(&[dataset.into()])
            .map_err(backend)?;
        let result = statement.all().await.map_err(backend)?;
        result.results().map_err(backend)
    }

    async fn entry(
        &self,
        dataset: &str,
        item_id: &str,
    ) -> Result<Option<(String, String)>, StoreError> {
        #[derive(serde::Deserialize)]
        struct EntryRow {
            json: String,
            content_hash: String,
        }
        let statement = self
            .db
            .prepare(SELECT_ENTRY)
            .bind(&[dataset.into(), item_id.into()])
            .map_err(backend)?;
        let row = statement.first::<EntryRow>(None).await.map_err(backend)?;
        Ok(row.map(|r| (r.json, r.content_hash)))
    }
}
