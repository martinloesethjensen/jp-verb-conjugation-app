mod support;

use review_api::course_store::*;
use review_api::data::DataFile;
use review_api::items::extract;
use review_api::review_store::Target;
use review_api::store::{SnapshotFile, Store};
use support::sqlite::SqliteStore;

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const T0: &str = "2026-11-17T12:00:00Z";
const T1: &str = "2026-11-17T13:00:00Z";
const AIKO: &str = "aiko@example.com";
const MARTIN: &str = "martin@example.com";

async fn load(store: &SqliteStore, file: DataFile) -> Vec<Target> {
    let bytes = std::fs::read(format!("{ROOT}/data/{}", file.file_name())).unwrap();
    let rows = extract(file, &bytes).unwrap();
    let snapshot = SnapshotFile {
        name: file.name().into(),
        version: "1".into(),
        sha256: "abc".into(),
        git_ref: None,
        item_count: rows.len() as u32,
        imported_at: T0.into(),
        imported_by: MARTIN.into(),
    };
    store
        .replace_snapshot(&snapshot, None, &rows, MARTIN, T0)
        .await
        .unwrap();
    rows.iter()
        .map(|r| Target {
            dataset: file.name().into(),
            kind: r.kind.as_str().into(),
            item_id: r.item_id.clone(),
        })
        .collect()
}

/// A store with verbs and words loaded; the first three verb entries and first word entry.
async fn setup() -> (SqliteStore, Vec<Target>, Target) {
    let s = SqliteStore::new();
    let verbs = load(&s, DataFile::Verbs).await;
    let words = load(&s, DataFile::Words).await;
    let v: Vec<Target> = verbs
        .iter()
        .filter(|t| t.kind == "entry")
        .take(3)
        .cloned()
        .collect();
    let w = words.iter().find(|t| t.kind == "entry").cloned().unwrap();
    (s, v, w)
}

fn lesson(id: Option<&str>, title: &str, items: Vec<Target>) -> LessonInput {
    LessonInput {
        id: id.map(String::from),
        title: title.into(),
        goal: "Goal".into(),
        items,
        ..Default::default()
    }
}

async fn new_course(s: &SqliteStore) -> String {
    let new = NewCourse {
        title: "Eating".into(),
        summary: "Food verbs".into(),
        ..Default::default()
    };
    s.create_course(&new, AIKO, T0).await.unwrap()
}

fn audits(s: &SqliteStore, action: &str) -> i64 {
    s.conn
        .borrow()
        .query_row(
            "SELECT COUNT(*) FROM audit_log WHERE action = ?1",
            [action],
            |r| r.get(0),
        )
        .unwrap()
}

#[tokio::test]
async fn create_and_read_back() {
    let (s, _, _) = setup().await;
    let id = new_course(&s).await;
    assert_eq!(id.len(), 6);
    let c = s.course(&id, AIKO).await.unwrap().unwrap();
    assert_eq!((c.title.as_str(), c.status.as_str()), ("Eating", "draft"));
    assert!(c.mine && c.lessons.is_empty() && c.approved.is_none());
    assert!(
        !s.course(&id, "ben@example.com")
            .await
            .unwrap()
            .unwrap()
            .mine
    );
    assert!(s.course("nope00", AIKO).await.unwrap().is_none());
    let list = s.courses(AIKO).await.unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(
        (list[0].lessons, list[0].items, list[0].approved),
        (0, 0, false)
    );
    assert_eq!(audits(&s, "course.create"), 1);
}

#[tokio::test]
async fn save_lessons_replaces_outline_in_one_batch() {
    let (s, v, w) = setup().await;
    let id = new_course(&s).await;
    let first = [lesson(None, "One", vec![v[0].clone(), v[1].clone()])];
    s.save_lessons(&id, &first, AIKO, T0).await.unwrap();
    let second = [
        lesson(None, "A", vec![w.clone()]),
        lesson(None, "B", vec![v[2].clone()]),
    ];
    let ids = s.save_lessons(&id, &second, AIKO, T1).await.unwrap();
    assert_eq!(ids.len(), 2);
    let c = s.course(&id, AIKO).await.unwrap().unwrap();
    assert_eq!(c.lessons.len(), 2);
    assert_eq!(c.lessons[0].items.len(), 1);
    assert_eq!(c.lessons[0].items[0].course_kind, "word");
    assert_eq!(c.lessons[1].items[0].course_kind, "verb");
    assert!(c.lessons[1].items[0].loaded && !c.lessons[1].items[0].title.is_empty());
    assert_eq!(c.updated_at, T1);
    assert_eq!(audits(&s, "course.outline"), 2);

    // A refused outline changes nothing, not even half of it.
    let bad = [
        lesson(None, "Fine", vec![v[0].clone()]),
        lesson(
            None,
            "Bad",
            vec![Target {
                item_id: "nowhere".into(),
                ..v[0].clone()
            }],
        ),
    ];
    let err = s.save_lessons(&id, &bad, AIKO, T1).await.unwrap_err();
    assert!(matches!(err, CourseError::Invalid(_)));
    assert_eq!(
        s.course(&id, AIKO).await.unwrap().unwrap().lessons,
        c.lessons
    );
    assert_eq!(audits(&s, "course.outline"), 2);
}

#[tokio::test]
async fn reordering_keeps_lesson_ids() {
    let (s, v, _) = setup().await;
    let id = new_course(&s).await;
    let ids = s
        .save_lessons(
            &id,
            &[
                lesson(None, "A", vec![v[0].clone()]),
                lesson(None, "B", vec![v[1].clone()]),
            ],
            AIKO,
            T0,
        )
        .await
        .unwrap();
    let swapped = [
        lesson(Some(&ids[1]), "B", vec![v[1].clone(), v[0].clone()]),
        lesson(Some(&ids[0]), "A", vec![]),
    ];
    let again = s.save_lessons(&id, &swapped, AIKO, T1).await.unwrap();
    assert_eq!(again, vec![ids[1].clone(), ids[0].clone()]);
    let c = s.course(&id, AIKO).await.unwrap().unwrap();
    assert_eq!(c.lessons[0].id, ids[1]);
    assert_eq!(c.lessons[0].items.len(), 2);
    // The same id twice is refused.
    let twice = [
        lesson(Some(&ids[0]), "A", vec![]),
        lesson(Some(&ids[0]), "A", vec![]),
    ];
    assert!(matches!(
        s.save_lessons(&id, &twice, AIKO, T1).await,
        Err(CourseError::Invalid(_))
    ));
}

#[tokio::test]
async fn missing_items_are_reported() {
    let (s, v, _) = setup().await;
    let id = new_course(&s).await;
    let ids = s
        .save_lessons(&id, &[lesson(None, "A", vec![v[0].clone()])], AIKO, T0)
        .await
        .unwrap();
    s.execute(&format!(
        "DELETE FROM items WHERE dataset = 'verbs' AND kind = 'entry' AND item_id = '{}'",
        v[0].item_id
    ));
    let c = s.course(&id, AIKO).await.unwrap().unwrap();
    let item = &c.lessons[0].items[0];
    assert!(!item.loaded);
    assert_eq!(item.title, v[0].item_id);
    // A kept item that left the data stays savable; a new one that isn't loaded is refused.
    let keep = [lesson(Some(&ids[0]), "A", vec![v[0].clone()])];
    s.save_lessons(&id, &keep, AIKO, T1).await.unwrap();
    let elsewhere = [lesson(None, "A", vec![v[0].clone()])];
    assert!(matches!(
        s.save_lessons(&id, &elsewhere, AIKO, T1).await,
        Err(CourseError::Invalid(_))
    ));
}

#[tokio::test]
async fn only_drafts_save() {
    let (s, v, _) = setup().await;
    let id = new_course(&s).await;
    s.save_lessons(&id, &[lesson(None, "A", vec![v[0].clone()])], AIKO, T0)
        .await
        .unwrap();
    s.set_status(&id, "draft", "in_review", true, AIKO, T0)
        .await
        .unwrap();
    let c = s.course(&id, AIKO).await.unwrap().unwrap();
    assert_eq!(c.status, "in_review");
    assert_eq!(c.submitted_at.as_deref(), Some(T0));
    assert_eq!(c.own_words_at.as_deref(), Some(T0));

    let meta = CourseMeta {
        title: "New".into(),
        ..Default::default()
    };
    assert_eq!(
        s.save_course_meta(&id, &meta, AIKO, T1).await,
        Err(CourseError::NotDraft)
    );
    assert_eq!(
        s.save_lessons(&id, &[], AIKO, T1).await,
        Err(CourseError::NotDraft)
    );
    assert_eq!(
        s.delete_draft(&id, AIKO, T1).await,
        Err(CourseError::NotDraft)
    );
    let after = s.course(&id, AIKO).await.unwrap().unwrap();
    assert_eq!((after.title.as_str(), after.lessons.len()), ("Eating", 1));

    // The SQL itself refuses too, whatever the pre-check saw.
    for sql in [DELETE_COURSE_ITEMS, DELETE_COURSE_LESSONS] {
        s.conn.borrow().execute(sql, [&id]).unwrap();
    }
    assert_eq!(
        s.course(&id, AIKO).await.unwrap().unwrap().lessons[0]
            .items
            .len(),
        1
    );

    // Moving on from the wrong status conflicts; back to draft works.
    assert_eq!(
        s.set_status(&id, "draft", "in_review", false, AIKO, T1)
            .await,
        Err(CourseError::Conflict)
    );
    s.set_status(&id, "in_review", "draft", false, AIKO, T1)
        .await
        .unwrap();
    s.save_course_meta(&id, &meta, AIKO, T1).await.unwrap();
    assert_eq!(s.course(&id, AIKO).await.unwrap().unwrap().title, "New");
    assert_eq!(audits(&s, "course.status"), 2);
    assert_eq!(audits(&s, "course.save"), 1);
}

#[tokio::test]
async fn delete_draft_removes_everything_unless_exported() {
    let (s, v, _) = setup().await;
    let id = new_course(&s).await;
    s.save_lessons(&id, &[lesson(None, "A", vec![v[0].clone()])], AIKO, T0)
        .await
        .unwrap();
    s.execute(&format!(
        "INSERT INTO course_comments (course_id, author, body, created_at) VALUES ('{id}', '{AIKO}', 'hi', '{T0}')"
    ));
    s.delete_draft(&id, AIKO, T1).await.unwrap();
    assert!(s.course(&id, AIKO).await.unwrap().is_none());
    let left: i64 = s
        .conn
        .borrow()
        .query_row(
            "SELECT (SELECT COUNT(*) FROM course_items) + (SELECT COUNT(*) FROM course_lessons) \
             + (SELECT COUNT(*) FROM course_comments)",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(left, 0);
    assert_eq!(audits(&s, "course.delete"), 1);
    assert_eq!(
        s.delete_draft(&id, AIKO, T1).await,
        Err(CourseError::NotFound)
    );

    let kept = new_course(&s).await;
    s.execute(&format!(
        "UPDATE courses SET exported_at = '{T0}' WHERE id = '{kept}'"
    ));
    assert_eq!(
        s.delete_draft(&kept, AIKO, T1).await,
        Err(CourseError::NotDraft)
    );
}

#[tokio::test]
async fn search_finds_loaded_items_by_kind() {
    let (s, v, w) = setup().await;
    let title: String = s
        .conn
        .borrow()
        .query_row(
            "SELECT title FROM items WHERE dataset = 'verbs' AND kind = 'entry' AND item_id = ?1",
            [&v[0].item_id],
            |r| r.get(0),
        )
        .unwrap();
    let hits = s
        .search_items(std::slice::from_ref(&title), &[], 40)
        .await
        .unwrap();
    assert!(hits.iter().any(|h| h.item_id == v[0].item_id && h.loaded));
    let words = s
        .search_items(std::slice::from_ref(&title), &["word".into()], 40)
        .await
        .unwrap();
    assert!(words.iter().all(|h| h.course_kind == "word"));
    assert!(!words.iter().any(|h| h.item_id == v[0].item_id));
    assert!(s.search_items(&[], &[], 40).await.unwrap().is_empty());
    assert!(s
        .search_items(&["zzzzqqq".into()], &[], 40)
        .await
        .unwrap()
        .is_empty());
    assert!(s.search_items(&[title], &[], 1).await.unwrap().len() <= 1);
    let _ = w;
}

#[test]
fn course_kind_round_trips() {
    for k in COURSE_KINDS {
        let pairs = kind_targets(k);
        assert!(!pairs.is_empty(), "{k}");
        for (dataset, kind) in pairs {
            assert_eq!(course_kind(dataset, kind), Some(k));
        }
    }
    assert_eq!(course_kind("verbs", "entry"), Some("verb"));
    assert_eq!(course_kind("counters", "example"), Some("example"));
    assert_eq!(course_kind("words", "example"), None);
    assert_eq!(course_kind("furigana", "entry"), None);
    assert!(kind_targets("nope").is_empty());
}

#[tokio::test]
async fn made_up_lesson_ids_are_refused() {
    let (s, v, _) = setup().await;
    let id = new_course(&s).await;
    let ids = s
        .save_lessons(&id, &[lesson(None, "A", vec![v[0].clone()])], AIKO, T0)
        .await
        .unwrap();
    assert!(
        ids[0].len() == 6
            && ids[0]
                .bytes()
                .all(|b| b"abcdefghijkmnpqrstuvwxyz23456789".contains(&b))
    );
    let before = s.course(&id, AIKO).await.unwrap().unwrap();
    for bad in ["1", "madeup", "zzzzzz"] {
        let input = [
            lesson(Some(&ids[0]), "A", vec![]),
            lesson(Some(bad), "B", vec![]),
        ];
        assert!(matches!(
            s.save_lessons(&id, &input, AIKO, T1).await,
            Err(CourseError::Invalid(_))
        ));
    }
    assert_eq!(s.course(&id, AIKO).await.unwrap().unwrap(), before);
    assert_eq!(audits(&s, "course.outline"), 1);
}

#[tokio::test]
async fn a_guarded_write_that_changes_nothing_is_an_error() {
    assert_eq!(
        require_written(0, CourseError::NotDraft),
        Err(CourseError::NotDraft)
    );
    assert_eq!(require_written(1, CourseError::NotDraft), Ok(()));
    // The SQL really does write nothing once the status has moved on, which is what the helper catches.
    let (s, _, _) = setup().await;
    let id = new_course(&s).await;
    s.set_status(&id, "draft", "in_review", false, AIKO, T0)
        .await
        .unwrap();
    let conn = s.conn.borrow();
    let meta = conn
        .execute(
            UPDATE_COURSE_META,
            rusqlite::params![id, "x", "y", None::<String>, T1],
        )
        .unwrap();
    let touch = conn
        .execute(TOUCH_COURSE, rusqlite::params![id, T1])
        .unwrap();
    let status = conn
        .execute(
            UPDATE_COURSE_STATUS,
            rusqlite::params![id, "draft", "approved", T1, 0],
        )
        .unwrap();
    assert_eq!((meta, touch, status), (0, 0, 0));
}
