mod support;

use review_api::data::DataFile;
use review_api::items::{extract, ItemRow};
use review_api::store::{SnapshotFile, Store};
use serde_json::Value;
use support::sqlite::SqliteStore;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const T0: &str = "2026-11-04T12:00:00Z";
const OWNER: &str = "owner@example.com";

fn real(file: DataFile) -> Vec<u8> {
    std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap()
}

fn version_of(file: DataFile) -> String {
    let manifest: Value =
        serde_json::from_slice(&std::fs::read(format!("{ROOT}/data/manifest.json")).unwrap())
            .unwrap();
    match file {
        DataFile::Verbs => manifest["version"].as_str().unwrap().into(),
        other => manifest[other.name()]["version"].as_str().unwrap().into(),
    }
}

fn snapshot(file: DataFile, rows: &[ItemRow]) -> SnapshotFile {
    SnapshotFile {
        name: file.name().into(),
        version: version_of(file),
        sha256: "abc".into(),
        git_ref: None,
        item_count: rows.len() as u32,
        imported_at: T0.into(),
        imported_by: OWNER.into(),
    }
}

async fn load(store: &SqliteStore, file: DataFile, bytes: &[u8]) -> Vec<ItemRow> {
    let rows = extract(file, bytes).unwrap();
    let json = (!file.is_browsable()).then(|| String::from_utf8(bytes.to_vec()).unwrap());
    store
        .replace_snapshot(&snapshot(file, &rows), json.as_deref(), &rows, OWNER, T0)
        .await
        .unwrap();
    rows
}

#[tokio::test(flavor = "current_thread")]
async fn a_snapshot_round_trips() {
    let s = SqliteStore::new();
    load(&s, DataFile::Words, &real(DataFile::Words)).await;
    let file = s.snapshot_file("words").await.unwrap().unwrap();
    assert_eq!(file.version, version_of(DataFile::Words));
    assert_eq!(file.item_count, 32);
    let entries = s.entries("words").await.unwrap();
    assert_eq!(entries.len(), 32);
    assert_eq!(entries[0].item_id, "i-adjective:いい");
    let (json, hash) = s.entry("words", "i-adjective:いい").await.unwrap().unwrap();
    let published: Value = serde_json::from_slice(&real(DataFile::Words)).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&json).unwrap(),
        published["words"][0]
    );
    assert_eq!(hash.len(), 64);
    assert_eq!(s.entry("words", "noun:nothing").await.unwrap(), None);
    assert_eq!(s.snapshot_files().await.unwrap().len(), 1);
}

#[tokio::test(flavor = "current_thread")]
async fn replacing_drops_items_that_disappeared() {
    let s = SqliteStore::new();
    load(&s, DataFile::Words, &real(DataFile::Words)).await;
    let mut doc: Value = serde_json::from_slice(&real(DataFile::Words)).unwrap();
    doc["words"].as_array_mut().unwrap().remove(0);
    load(&s, DataFile::Words, doc.to_string().as_bytes()).await;
    assert_eq!(s.entries("words").await.unwrap().len(), 31);
    assert_eq!(s.entry("words", "i-adjective:いい").await.unwrap(), None);
}

#[tokio::test(flavor = "current_thread")]
async fn parts_count_every_sub_item_of_an_entry() {
    let s = SqliteStore::new();
    let rows = load(&s, DataFile::Verbs, &real(DataFile::Verbs)).await;
    let taberu = s
        .entries("verbs")
        .await
        .unwrap()
        .into_iter()
        .find(|e| e.item_id == "たべる")
        .unwrap();
    let expected = rows
        .iter()
        .filter(|r| r.entry_id == "たべる" && r.item_id != "たべる")
        .count();
    assert_eq!(taberu.parts as usize, expected);
    assert_eq!(expected, 23); // 20 examples + 3 collocations today
    assert_eq!(taberu.title, "たべる (食べる)");
    assert_eq!(taberu.jlpt.as_deref(), Some("N5"));
}

#[tokio::test(flavor = "current_thread")]
async fn a_failed_write_keeps_the_old_snapshot() {
    let s = SqliteStore::new();
    load(&s, DataFile::Words, &real(DataFile::Words)).await;
    let mut rows = extract(DataFile::Words, &real(DataFile::Words)).unwrap();
    rows[1].item_id = rows[0].item_id.clone(); // two rows with the same (kind, item_id)
    let mut bad = snapshot(DataFile::Words, &rows);
    bad.version = "99.0.0".into();
    assert!(s
        .replace_snapshot(&bad, None, &rows, OWNER, T0)
        .await
        .is_err());
    assert_eq!(s.entries("words").await.unwrap().len(), 32);
    assert_eq!(
        s.snapshot_file("words").await.unwrap().unwrap().version,
        version_of(DataFile::Words)
    );
}

#[tokio::test(flavor = "current_thread")]
async fn reference_files_keep_their_json() {
    let s = SqliteStore::new();
    load(&s, DataFile::Furigana, &real(DataFile::Furigana)).await;
    assert_eq!(
        s.snapshot_json("furigana")
            .await
            .unwrap()
            .unwrap()
            .as_bytes(),
        real(DataFile::Furigana)
    );
    assert_eq!(s.snapshot_json("forms").await.unwrap(), None);
    assert!(s.entries("furigana").await.unwrap().is_empty());
}

#[tokio::test(flavor = "current_thread")]
async fn imports_are_audited() {
    let s = SqliteStore::new();
    load(&s, DataFile::Words, &real(DataFile::Words)).await;
    let conn = s.conn.borrow();
    let row: (String, String, String, String) = conn
        .query_row(
            "SELECT actor, action, target, detail FROM audit_log ORDER BY id DESC LIMIT 1",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )
        .unwrap();
    assert_eq!(
        row,
        (
            OWNER.into(),
            "snapshot.import".into(),
            "words.json".into(),
            format!("version={}", version_of(DataFile::Words))
        )
    );
}
