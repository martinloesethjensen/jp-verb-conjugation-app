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
    public_role: String,
    public_name: Option<String>,
}

impl Row {
    fn into_user(self) -> Result<User, StoreError> {
        let role = Role::parse(&self.role)
            .ok_or_else(|| StoreError::Backend(format!("unknown role {:?}", self.role)))?;
        let public_role = PublicRole::parse(&self.public_role).ok_or_else(|| {
            StoreError::Backend(format!("unknown public role {:?}", self.public_role))
        })?;
        Ok(User {
            email: self.email,
            display_name: self.display_name,
            role,
            active: self.active == 1,
            public_role,
            public_name: self.public_name,
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

impl D1Store {
    /// One column of a user (`sql` binds ?1 value, ?2 email) and its audit row, in one batch. The user is
    /// looked up first, since a batch can't skip its audit row when the UPDATE matches nothing.
    async fn update_user(
        &self,
        sql: &str,
        value: JsValue,
        email: &str,
        (actor, now): (&str, &str),
        action: &str,
        detail: &str,
    ) -> Result<(), StoreError> {
        if self.user(email).await?.is_none() {
            return Err(StoreError::NotFound);
        }
        let update = self
            .db
            .prepare(sql)
            .bind(&[value, email.into()])
            .map_err(backend)?;
        let log = audit(&self.db, now, actor, action, email, detail)?;
        self.db.batch(vec![update, log]).await.map_err(backend)?;
        Ok(())
    }
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
        let detail = format!("name={display_name}");
        self.update_user(
            UPDATE_DISPLAY_NAME,
            display_name.into(),
            email,
            (actor, now),
            "user.name",
            &detail,
        )
        .await
    }

    async fn set_public_name(
        &self,
        email: &str,
        public_name: Option<&str>,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let value = public_name.map(JsValue::from).unwrap_or(JsValue::NULL);
        let detail = format!("public_name={}", public_name.unwrap_or(""));
        self.update_user(
            UPDATE_PUBLIC_NAME,
            value,
            email,
            (actor, now),
            "user.public_name",
            &detail,
        )
        .await
    }

    async fn set_public_role(
        &self,
        email: &str,
        public_role: PublicRole,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let detail = format!("public_role={}", public_role.as_str());
        let value = public_role.as_str().into();
        self.update_user(
            UPDATE_PUBLIC_ROLE,
            value,
            email,
            (actor, now),
            "user.public_role",
            &detail,
        )
        .await
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

    async fn begin_load(&self, load: &SnapshotLoad) -> Result<(), StoreError> {
        let slices =
            serde_json::to_string(&load.slices).map_err(|e| StoreError::Backend(e.to_string()))?;
        let name: JsValue = load.name.as_str().into();
        let mut statements = Vec::new();
        for sql in [
            DELETE_STAGING_FOR_NAME,
            DELETE_SLICES_FOR_NAME,
            DELETE_LOADS_FOR_NAME,
        ] {
            statements.push(
                self.db
                    .prepare(sql)
                    .bind(std::slice::from_ref(&name))
                    .map_err(backend)?,
            );
        }
        let optional = |v: Option<&str>| v.map(JsValue::from).unwrap_or(JsValue::NULL);
        statements.push(
            self.db
                .prepare(INSERT_LOAD)
                .bind(&[
                    load.load_id.as_str().into(),
                    name,
                    load.version.as_str().into(),
                    load.sha256.as_str().into(),
                    optional(load.git_ref.as_deref()),
                    slices.into(),
                    load.started_by.as_str().into(),
                    load.started_at.as_str().into(),
                ])
                .map_err(backend)?,
        );
        self.db.batch(statements).await.map_err(backend)?;
        Ok(())
    }

    async fn load(&self, load_id: &str) -> Result<Option<SnapshotLoad>, StoreError> {
        #[derive(serde::Deserialize)]
        struct LoadRow {
            load_id: String,
            name: String,
            version: String,
            sha256: String,
            git_ref: Option<String>,
            slices: String,
            started_by: String,
            started_at: String,
        }
        let statement = self
            .db
            .prepare(SELECT_LOAD)
            .bind(&[load_id.into()])
            .map_err(backend)?;
        let Some(row) = statement.first::<LoadRow>(None).await.map_err(backend)? else {
            return Ok(None);
        };
        let slices =
            serde_json::from_str(&row.slices).map_err(|e| StoreError::Backend(e.to_string()))?;
        Ok(Some(SnapshotLoad {
            load_id: row.load_id,
            name: row.name,
            version: row.version,
            sha256: row.sha256,
            git_ref: row.git_ref,
            slices,
            started_by: row.started_by,
            started_at: row.started_at,
        }))
    }

    async fn stage_slice(
        &self,
        load: &SnapshotLoad,
        slice: u32,
        rows: &[ItemRow],
    ) -> Result<(), StoreError> {
        let rows_json =
            serde_json::to_string(rows).map_err(|e| StoreError::Backend(e.to_string()))?;
        let (id, n): (JsValue, JsValue) = (load.load_id.as_str().into(), JsValue::from(slice));
        let delete = self
            .db
            .prepare(DELETE_STAGED_SLICE)
            .bind(&[id.clone(), n.clone()])
            .map_err(backend)?;
        let insert = self
            .db
            .prepare(INSERT_STAGED)
            .bind(&[
                id.clone(),
                n.clone(),
                load.name.as_str().into(),
                rows_json.into(),
            ])
            .map_err(backend)?;
        let done = self
            .db
            .prepare(INSERT_SLICE_DONE)
            .bind(&[id, n])
            .map_err(backend)?;
        self.db
            .batch(vec![delete, insert, done])
            .await
            .map_err(backend)?;
        Ok(())
    }

    async fn slices_done(&self, load_id: &str) -> Result<u32, StoreError> {
        let statement = self
            .db
            .prepare(COUNT_SLICES_DONE)
            .bind(&[load_id.into()])
            .map_err(backend)?;
        Ok(statement
            .first::<u32>(Some("done"))
            .await
            .map_err(backend)?
            .unwrap_or(0))
    }

    async fn finish_load(
        &self,
        load: &SnapshotLoad,
        file: &SnapshotFile,
        json: Option<&str>,
        actor: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let id: JsValue = load.load_id.as_str().into();
        let name: JsValue = file.name.as_str().into();
        let optional = |v: Option<&str>| v.map(JsValue::from).unwrap_or(JsValue::NULL);
        let mut statements = vec![
            self.db
                .prepare(DELETE_ITEMS_FOR_LOAD)
                .bind(&[name.clone(), id.clone()])
                .map_err(backend)?,
            self.db
                .prepare(INSERT_ITEMS_FROM_STAGING)
                .bind(std::slice::from_ref(&id))
                .map_err(backend)?,
            self.db
                .prepare(UPSERT_SNAPSHOT_FILE_FOR_LOAD)
                .bind(&[
                    name,
                    file.version.as_str().into(),
                    file.sha256.as_str().into(),
                    optional(file.git_ref.as_deref()),
                    JsValue::from(file.item_count),
                    file.imported_at.as_str().into(),
                    file.imported_by.as_str().into(),
                    optional(json),
                    id.clone(),
                ])
                .map_err(backend)?,
            self.db
                .prepare(INSERT_AUDIT_FOR_LOAD)
                .bind(&[
                    now.into(),
                    actor.into(),
                    "snapshot.import".into(),
                    format!("{}.json", file.name).into(),
                    format!("version={}", file.version).into(),
                    id.clone(),
                ])
                .map_err(backend)?,
        ];
        // The load row goes last: while it exists every statement above applies, and afterwards none.
        for sql in [DELETE_STAGING, DELETE_SLICES, DELETE_LOAD] {
            statements.push(
                self.db
                    .prepare(sql)
                    .bind(std::slice::from_ref(&id))
                    .map_err(backend)?,
            );
        }
        let results = self.db.batch(statements).await.map_err(backend)?;
        let deleted = results
            .last()
            .and_then(|r| r.meta().ok().flatten())
            .and_then(|m| m.changes)
            .unwrap_or(0);
        if deleted == 0 {
            return Err(StoreError::NotFound); // the load was gone: every statement was a no-op
        }
        Ok(())
    }
}

// --- ReviewStore ----------------------------------------------------------------------------------

use crate::review_store::*;
use serde::de::DeserializeOwned;
use worker::{D1PreparedStatement, D1Result};

fn text(v: &str) -> JsValue {
    JsValue::from(v)
}

fn maybe(v: Option<&str>) -> JsValue {
    v.map(JsValue::from).unwrap_or(JsValue::NULL)
}

/// D1 numbers are JavaScript numbers; an i64 would become a BigInt, which D1 refuses.
fn number(v: i64) -> JsValue {
    JsValue::from(v as f64)
}

fn changes(result: Option<&D1Result>) -> usize {
    result
        .and_then(|r| r.meta().ok().flatten())
        .and_then(|m| m.changes)
        .unwrap_or(0)
}

impl D1Store {
    fn statement(&self, sql: &str, binds: &[JsValue]) -> Result<D1PreparedStatement, StoreError> {
        self.db.prepare(sql).bind(binds).map_err(backend)
    }

    async fn rows<T: DeserializeOwned>(
        &self,
        sql: &str,
        binds: &[JsValue],
    ) -> Result<Vec<T>, StoreError> {
        let result = self.statement(sql, binds)?.all().await.map_err(backend)?;
        result.results().map_err(backend)
    }

    fn log(
        &self,
        now: &str,
        actor: &str,
        action: &str,
        target: &str,
        detail: &str,
    ) -> Result<D1PreparedStatement, StoreError> {
        audit(&self.db, now, actor, action, target, detail)
    }

    fn target_binds(t: &Target) -> [JsValue; 3] {
        [text(&t.dataset), text(&t.kind), text(&t.item_id)]
    }

    async fn queue_item_exists(&self, id: i64, t: &Target) -> Result<bool, StoreError> {
        let [d, k, i] = Self::target_binds(t);
        let rows: Vec<IdRow> = self
            .rows(SELECT_QUEUE_ITEM_EXISTS, &[number(id), d, k, i])
            .await?;
        Ok(!rows.is_empty())
    }

    async fn status(&self, id: i64) -> Result<Option<StatusRow>, StoreError> {
        let rows: Vec<StatusRow> = self.rows(SELECT_STATUS, &[number(id)]).await?;
        Ok(rows.into_iter().next())
    }
}

impl ReviewStore for D1Store {
    async fn current_hash(
        &self,
        t: &Target,
    ) -> Result<Option<(String, String, String)>, StoreError> {
        let rows: Vec<HashRow> = self.rows(SELECT_HASH, &Self::target_binds(t)).await?;
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
        let [d, k, i] = Self::target_binds(t);
        let upsert = self.statement(
            UPSERT_APPROVAL,
            &[d, k, i, text(reviewer), text(hash), text(now)],
        )?;
        let log = self.log(
            now,
            reviewer,
            "approval.add",
            &t.audit_name(),
            &format!("hash={hash}"),
        )?;
        self.db.batch(vec![upsert, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn unapprove(&self, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError> {
        let [d, k, i] = Self::target_binds(t);
        let delete = self.statement(DELETE_APPROVAL, &[d, k, i, text(reviewer)])?;
        let log = self.log(now, reviewer, "approval.remove", &t.audit_name(), "")?;
        self.db.batch(vec![delete, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn parts(&self, dataset: &str, entry_id: &str) -> Result<Vec<Part>, StoreError> {
        self.rows(SELECT_PARTS, &[text(dataset), text(entry_id)])
            .await
    }

    async fn id_in_use(&self, dataset: &str, id: &str) -> Result<bool, StoreError> {
        let rows: Vec<IdRow> = self
            .rows(SELECT_ID_IN_USE, &[text(dataset), text(id)])
            .await?;
        Ok(!rows.is_empty())
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
        let loaded: Vec<ItemIdRow> = self.rows(SELECT_LOADED_IDS, &[text(dataset)]).await?;
        let suggested: Vec<ItemIdRow> = self.rows(SELECT_SUGGESTED_IDS, &[text(dataset)]).await?;
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
        let rows: Vec<IdRow> = self
            .rows(SELECT_OPEN_ADD, &[text(dataset), text(kind), text(item_id)])
            .await?;
        Ok(rows.first().map(|r| r.id))
    }

    async fn additions(&self, dataset: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError> {
        let binds = [text(viewer), text(dataset)];
        let rows = self.rows(SELECT_ADDITIONS, &binds).await?;
        let comments = self.rows(SELECT_ADDITIONS_COMMENTS, &binds).await?;
        Ok(assemble(rows, comments))
    }

    async fn add_suggestion(
        &self,
        s: &NewSuggestion,
        author: &str,
        now: &str,
    ) -> Result<(i64, bool), StoreError> {
        let t = &s.target;
        let existing: Vec<IdRow> = if s.action == "add" {
            self.rows(
                SELECT_IDENTICAL_ADD,
                &[
                    text(&t.dataset),
                    text(&t.kind),
                    maybe(s.parent_id.as_deref()),
                    text(author),
                    maybe(s.fingerprint.as_deref()),
                    maybe(s.furigana_json.as_deref()),
                    text(&s.comment),
                ],
            )
            .await?
        } else {
            self.rows(
                SELECT_IDENTICAL_OPEN,
                &[
                    text(&s.action),
                    text(&t.dataset),
                    text(&t.kind),
                    text(&t.item_id),
                    text(author),
                    maybe(s.proposed_json.as_deref()),
                    maybe(s.furigana_json.as_deref()),
                    text(&s.comment),
                ],
            )
            .await?
        };
        if let Some(row) = existing.into_iter().next() {
            return Ok((row.id, false));
        }
        let insert = self.statement(
            INSERT_SUGGESTION,
            &[
                text(&s.action),
                text(&t.dataset),
                text(&t.kind),
                text(&t.item_id),
                text(&s.entry_id),
                text(&s.item_title),
                text(&s.base_hash),
                maybe(s.proposed_json.as_deref()),
                maybe(s.furigana_json.as_deref()),
                number(s.dropped_blanks as i64),
                text(&s.comment),
                text(author),
                text(now),
                maybe(s.parent_kind.as_deref()),
                maybe(s.parent_id.as_deref()),
                maybe(s.fingerprint.as_deref()),
            ],
        )?;
        let detail = format!("action={} target={}", s.action, t.audit_name());
        let log = self.statement(
            INSERT_SUGGESTION_AUDIT,
            &[text(now), text(author), text(&detail)],
        )?;
        let results = self.db.batch(vec![insert, log]).await.map_err(backend)?;
        let ids: Vec<IdRow> = results
            .first()
            .ok_or_else(|| StoreError::Backend("no insert result".into()))?
            .results()
            .map_err(backend)?;
        ids.first()
            .map(|r| (r.id, true))
            .ok_or_else(|| StoreError::Backend("no id returned".into()))
    }

    async fn suggestion(&self, id: i64, viewer: &str) -> Result<Option<Suggestion>, StoreError> {
        let binds = [text(viewer), number(id)];
        let rows = self.rows(SELECT_SUGGESTION, &binds).await?;
        let comments = self.rows(SELECT_SUGGESTION_COMMENTS, &binds).await?;
        Ok(assemble(rows, comments).into_iter().next())
    }

    async fn withdraw(&self, id: i64, author: &str, now: &str) -> Result<(), StoreError> {
        match self.status(id).await? {
            Some(row) if row.status == "open" && row.author == author => {}
            Some(row) if row.status == "open" => return Err(StoreError::Conflict),
            _ => return Err(StoreError::NotFound),
        }
        // The audit row goes first, written only while the suggestion is open: both apply or neither.
        let log = self.statement(
            INSERT_WITHDRAW_AUDIT,
            &[text(now), text(author), number(id)],
        )?;
        let update = self.statement(WITHDRAW, &[number(id), text(author), text(now)])?;
        let results = self.db.batch(vec![log, update]).await.map_err(backend)?;
        if changes(results.get(1)) == 0 {
            return Err(StoreError::NotFound);
        }
        Ok(())
    }

    async fn decide(
        &self,
        id: i64,
        accept: bool,
        edit: OwnerEdit<'_>,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        let OwnerEdit {
            item_json: admin_edit_json,
            furigana_json,
            base_hash,
        } = edit;
        match self.status(id).await? {
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
        // As in withdraw: the audit row first, written only while the suggestion is still open.
        let log = self.statement(
            INSERT_DECIDE_AUDIT,
            &[text(now), text(by), text(action), text(detail), number(id)],
        )?;
        let update = self.statement(
            DECIDE,
            &[
                number(id),
                text(status),
                maybe(admin_edit_json),
                text(by),
                text(now),
                maybe(furigana_json),
                maybe(base_hash),
            ],
        )?;
        let results = self.db.batch(vec![log, update]).await.map_err(backend)?;
        if changes(results.get(1)) == 0 {
            return Err(StoreError::Conflict);
        }
        Ok(())
    }

    async fn add_comment(
        &self,
        suggestion_id: i64,
        body: &str,
        author: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if self.status(suggestion_id).await?.is_none() {
            return Err(StoreError::NotFound);
        }
        let insert = self.statement(
            INSERT_COMMENT,
            &[number(suggestion_id), text(author), text(body), text(now)],
        )?;
        let log = self.log(
            now,
            author,
            "comment.add",
            &format!("suggestion/{suggestion_id}"),
            "",
        )?;
        self.db.batch(vec![insert, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn entry_review(
        &self,
        dataset: &str,
        entry_id: &str,
        viewer: &str,
    ) -> Result<(Vec<Approval>, Vec<Suggestion>), StoreError> {
        let binds = [text(viewer), text(dataset), text(entry_id)];
        let approvals: Vec<ApprovalRow> = self.rows(SELECT_ENTRY_APPROVALS, &binds).await?;
        let rows = self.rows(SELECT_ENTRY_SUGGESTIONS, &binds).await?;
        let comments = self.rows(SELECT_ENTRY_COMMENTS, &binds).await?;
        Ok((
            approvals.into_iter().map(Approval::from).collect(),
            assemble(rows, comments),
        ))
    }

    async fn stamp_readiness(
        &self,
        dataset: &str,
        entry_id: &str,
    ) -> Result<StampReadiness, StoreError> {
        let rows = self
            .rows(SELECT_STAMP_READINESS, &[text(dataset), text(entry_id)])
            .await?;
        rows.into_iter()
            .next()
            .ok_or_else(|| StoreError::Backend("no readiness row".into()))
    }

    async fn pending_stamp(&self, t: &Target) -> Result<Option<Stamp>, StoreError> {
        let rows = self
            .rows(SELECT_PENDING_STAMP, &Self::target_binds(t))
            .await?;
        Ok(rows.into_iter().next())
    }

    async fn ready_to_stamp(&self) -> Result<Vec<ReadyEntry>, StoreError> {
        self.rows(SELECT_READY_TO_STAMP, &[]).await
    }

    async fn export_batch(&self) -> Result<(Vec<ExportRow>, Vec<Stamp>), StoreError> {
        let suggestions = self.rows(SELECT_EXPORT_SUGGESTIONS, &[]).await?;
        let stamps = self.rows(SELECT_EXPORT_STAMPS, &[]).await?;
        Ok((suggestions, stamps))
    }

    async fn mark_exported(
        &self,
        suggestions: &[i64],
        stamps: &[i64],
        actor: &str,
        now: &str,
    ) -> Result<(usize, usize), StoreError> {
        let ids = |v: &[i64]| serde_json::to_string(v).unwrap_or_else(|_| "[]".into());
        let a = self.statement(
            MARK_SUGGESTIONS_EXPORTED,
            &[text(&ids(suggestions)), text(now)],
        )?;
        let b = self.statement(MARK_STAMPS_EXPORTED, &[text(&ids(stamps)), text(now)])?;
        let detail = format!("suggestions={} stamps={}", ids(suggestions), ids(stamps));
        let log = self.log(now, actor, "export.mark", "export", &detail)?;
        let results = self.db.batch(vec![a, b, log]).await.map_err(backend)?;
        Ok((changes(results.first()), changes(results.get(1))))
    }

    async fn add_stamp(&self, s: &NewStamp, actor: &str, now: &str) -> Result<(), StoreError> {
        let [d, k, i] = Self::target_binds(&s.target);
        let insert = self.statement(
            INSERT_STAMP,
            &[
                d,
                k,
                i,
                text(&s.entry_id),
                text(&s.item_title),
                text(&s.content_hash),
                text(&s.by_role),
                text(&s.reviewer),
                text(actor),
                text(now),
            ],
        )?;
        let detail = format!("by={} hash={}", s.by_role, s.content_hash);
        let log = self.log(now, actor, "stamp.add", &s.target.audit_name(), &detail)?;
        self.db.batch(vec![insert, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn withdraw_stamp(&self, t: &Target, actor: &str, now: &str) -> Result<bool, StoreError> {
        if self.pending_stamp(t).await?.is_none() {
            return Ok(false);
        }
        let delete = self.statement(DELETE_PENDING_STAMP, &Self::target_binds(t))?;
        let log = self.log(now, actor, "stamp.withdraw", &t.audit_name(), "")?;
        self.db.batch(vec![delete, log]).await.map_err(backend)?;
        Ok(true)
    }

    async fn inbox(&self, status: &str, viewer: &str) -> Result<Vec<Suggestion>, StoreError> {
        let binds = [text(viewer), text(status)];
        let rows = self.rows(SELECT_INBOX, &binds).await?;
        let comments = self.rows(SELECT_INBOX_COMMENTS, &binds).await?;
        Ok(assemble(rows, comments))
    }

    async fn review_counts(&self, dataset: &str) -> Result<Vec<(String, u32, u32)>, StoreError> {
        let rows: Vec<CountRow> = self.rows(SELECT_REVIEW_COUNTS, &[text(dataset)]).await?;
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
        let rows: Vec<QueueRow> = self
            .rows(
                SELECT_QUEUES,
                &[text(viewer), number(include_archived as i64)],
            )
            .await?;
        Ok(rows.into_iter().map(QueueSummary::from).collect())
    }

    async fn queue(
        &self,
        id: i64,
        viewer: &str,
    ) -> Result<Option<(QueueSummary, Vec<QueueItem>)>, StoreError> {
        let binds = [text(viewer), number(id)];
        let summary: Vec<QueueRow> = self.rows(SELECT_QUEUE, &binds).await?;
        let Some(summary) = summary.into_iter().next() else {
            return Ok(None);
        };
        let items: Vec<QueueItemRow> = self.rows(SELECT_QUEUE_ITEMS, &binds).await?;
        Ok(Some((
            summary.into(),
            items.into_iter().map(QueueItem::from).collect(),
        )))
    }

    async fn preview_queue(&self, f: &QueueFilter) -> Result<Vec<QueueItem>, StoreError> {
        let (a, b, c, d, e) = f.binds();
        let rows: Vec<QueueItemRow> = self
            .rows(
                SELECT_FILTERED,
                &[text(&a), text(&b), text(&c), number(d), text(&e)],
            )
            .await?;
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
        let insert = self.statement(
            INSERT_QUEUE,
            &[text(title), text(description), text(by), text(now)],
        )?;
        let fill = self.statement(
            INSERT_QUEUE_ITEMS,
            &[text(&a), text(&b), text(&c), number(d), text(&e), text(by)],
        )?;
        let log = self.statement(
            INSERT_QUEUE_AUDIT,
            &[text(now), text(by), text(&format!("title={title}"))],
        )?;
        let results = self
            .db
            .batch(vec![insert, fill, log])
            .await
            .map_err(backend)?;
        let ids: Vec<IdRow> = results
            .first()
            .ok_or_else(|| StoreError::Backend("no insert result".into()))?
            .results()
            .map_err(backend)?;
        ids.first()
            .map(|r| r.id)
            .ok_or_else(|| StoreError::Backend("no id returned".into()))
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
        let exists: Vec<IdRow> = self.rows(SELECT_QUEUE_EXISTS, &[number(id)]).await?;
        if exists.is_empty() {
            return Err(StoreError::NotFound);
        }
        let update = self.statement(
            UPDATE_QUEUE,
            &[
                number(id),
                text(title),
                text(description),
                number(archived as i64),
            ],
        )?;
        let detail = format!("title={title} archived={}", archived as i64);
        let log = self.log(now, by, "queue.update", &format!("queue/{id}"), &detail)?;
        self.db.batch(vec![update, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn set_queue_note(
        &self,
        id: i64,
        t: &Target,
        note: &str,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if !self.queue_item_exists(id, t).await? {
            return Err(StoreError::NotFound);
        }
        let [d, k, i] = Self::target_binds(t);
        let update = self.statement(UPDATE_QUEUE_NOTE, &[number(id), d, k, i, text(note)])?;
        let log = self.log(
            now,
            by,
            "queue.note",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        self.db.batch(vec![update, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn remove_queue_item(
        &self,
        id: i64,
        t: &Target,
        by: &str,
        now: &str,
    ) -> Result<(), StoreError> {
        if !self.queue_item_exists(id, t).await? {
            return Err(StoreError::NotFound);
        }
        let [d, k, i] = Self::target_binds(t);
        let delete = self.statement(DELETE_QUEUE_ITEM, &[number(id), d, k, i])?;
        let log = self.log(
            now,
            by,
            "queue.remove_item",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        self.db.batch(vec![delete, log]).await.map_err(backend)?;
        Ok(())
    }

    async fn skip(&self, id: i64, t: &Target, reviewer: &str, now: &str) -> Result<(), StoreError> {
        if !self.queue_item_exists(id, t).await? {
            return Err(StoreError::NotFound);
        }
        let [d, k, i] = Self::target_binds(t);
        let insert = self.statement(
            INSERT_SKIP,
            &[number(id), d, k, i, text(reviewer), text(now)],
        )?;
        let log = self.log(
            now,
            reviewer,
            "queue.skip",
            &format!("queue/{id}"),
            &t.audit_name(),
        )?;
        self.db.batch(vec![insert, log]).await.map_err(backend)?;
        Ok(())
    }
}
