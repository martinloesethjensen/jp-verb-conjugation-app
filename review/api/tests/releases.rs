mod support;

use support::sqlite::SqliteStore;

const OWNER: &str = "owner@example.com";

fn exported(s: &SqliteStore, action: &str, dataset: &str, exported_at: Option<&str>) -> i64 {
    let conn = s.conn.borrow();
    conn.execute(
        "INSERT INTO suggestions (action, dataset, kind, item_id, entry_id, item_title, base_hash, author, \
         status, created_at, exported_at) \
         VALUES (?1, ?2, 'entry', 'x', 'x', 'x', 'h', 'aiko@example.com', 'accepted', '2026-11-01T00:00:00Z', ?3)",
        rusqlite::params![action, dataset, exported_at],
    )
    .unwrap();
    conn.last_insert_rowid()
}

fn released_in(s: &SqliteStore, id: i64) -> Option<String> {
    s.conn
        .borrow()
        .query_row(
            "SELECT r.label FROM suggestions s LEFT JOIN data_releases r ON r.id = s.released_in WHERE s.id = ?1",
            [id],
            |r| r.get(0),
        )
        .unwrap()
}

fn releases(s: &SqliteStore) -> Vec<(Option<String>, String)> {
    let conn = s.conn.borrow();
    let mut st = conn
        .prepare("SELECT manifest_sha256, label FROM data_releases ORDER BY id")
        .unwrap();
    st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
        .unwrap()
        .map(|r| r.unwrap())
        .collect()
}

fn loaded(s: &SqliteStore, name: &str, imported_at: &str) {
    s.conn
        .borrow()
        .execute(
            "INSERT INTO snapshot_files (name, version, sha256, git_ref, item_count, imported_at, imported_by, json) \
             VALUES (?1, '1.0.0', 'x', NULL, 1, ?2, ?3, NULL)",
            rusqlite::params![name, imported_at, OWNER],
        )
        .unwrap();
}

#[test]
fn the_backfill_files_earlier_exports_under_earlier_releases() {
    let s = SqliteStore::with_migrations_before("0012");
    loaded(&s, "verbs", "2026-11-10T12:00:00Z");
    let before = exported(&s, "change", "verbs", Some("2026-11-09T12:00:00Z"));
    let after = exported(&s, "change", "verbs", Some("2026-11-11T12:00:00Z"));
    let note = exported(&s, "note", "verbs", Some("2026-11-09T12:00:00Z"));
    let unexported = exported(&s, "change", "verbs", None);
    let never_loaded = exported(&s, "change", "counters", Some("2026-11-09T12:00:00Z"));
    s.apply_migrations_from("0012");
    assert_eq!(released_in(&s, before).as_deref(), Some("Earlier releases"));
    for id in [after, note, unexported, never_loaded] {
        assert_eq!(released_in(&s, id), None, "suggestion {id}");
    }
    assert_eq!(releases(&s), [(None, "Earlier releases".to_string())]);
}

#[test]
fn the_backfill_adds_no_row_when_nothing_qualifies() {
    let s = SqliteStore::with_migrations_before("0012");
    loaded(&s, "verbs", "2026-11-10T12:00:00Z");
    exported(&s, "change", "verbs", Some("2026-11-11T12:00:00Z"));
    s.apply_migrations_from("0012");
    assert!(releases(&s).is_empty());
}
