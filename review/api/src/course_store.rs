//! Courses: their lessons and items. As in `review_store.rs`, the SQL is written once here and run by both
//! the D1 store and the SQLite store the tests use, and both read rows into the `*Row` structs below.
//!
//! The store doesn't decide who may see a course (the routes do, by role); `viewer` only sets `mine`.
//! It does decide what may be written: only a draft's meta, lessons and items change, enforced in SQL
//! (`status = 'draft'`) so a racing status change can't be overwritten. An item may be saved only when it
//! is loaded (in `items`) or already in that lesson of the stored course, so a kept item that has left the
//! data reads back with `loaded = false`. Every write adds its `audit_log` row in the same batch.

use crate::review_store::Target;
use crate::store::StoreError;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

/// Why a course write was refused.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CourseError {
    NotFound,
    /// The course isn't a draft (or, for a delete, was exported).
    NotDraft,
    /// A write that lost to another one (a duplicate id, or the status moved on).
    Conflict,
    /// The input is wrong: an item that isn't loaded, an unknown kind, a bad or repeated lesson id.
    Invalid(String),
    /// An item (named for the message) that isn't in the loaded data.
    NotLoaded(String),
    Backend(String),
}

impl From<StoreError> for CourseError {
    fn from(e: StoreError) -> Self {
        match e {
            StoreError::Conflict => CourseError::Conflict,
            StoreError::NotFound => CourseError::NotFound,
            StoreError::Backend(m) => CourseError::Backend(m),
        }
    }
}

// --- Kinds ----------------------------------------------------------------------------------------

/// The course kinds, in the order the picker lists them.
pub const COURSE_KINDS: [&str; 5] = ["verb", "word", "grammar", "counter", "example"];

/// The course kind of an `items` row, or `None` for an item a course can't hold.
pub fn course_kind(dataset: &str, kind: &str) -> Option<&'static str> {
    match (dataset, kind) {
        ("verbs", "entry") => Some("verb"),
        ("words", "entry") => Some("word"),
        ("grammar", "entry") => Some("grammar"),
        ("counters", "entry") => Some("counter"),
        ("verbs" | "grammar" | "counters", "example") => Some("example"),
        _ => None,
    }
}

/// The `(dataset, kind)` pairs of a course kind: the inverse of `course_kind`.
pub fn kind_targets(course_kind: &str) -> &'static [(&'static str, &'static str)] {
    match course_kind {
        "verb" => &[("verbs", "entry")],
        "word" => &[("words", "entry")],
        "grammar" => &[("grammar", "entry")],
        "counter" => &[("counters", "entry")],
        "example" => &[
            ("verbs", "example"),
            ("grammar", "example"),
            ("counters", "example"),
        ],
        _ => &[],
    }
}

// --- API types ------------------------------------------------------------------------------------

/// A grammar proposal made from the course, as the item shows it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ProposalState {
    pub id: i64,
    /// The suggestion's status: `open`, `accepted`, `declined` or `withdrawn`.
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CourseItem {
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub course_kind: String,
    pub title: String,
    pub subtitle: String,
    pub jlpt: Option<String>,
    /// The item is among the loaded items; false once it leaves the data (or for an unaccepted proposal).
    pub loaded: bool,
    pub proposal: Option<ProposalState>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Lesson {
    pub id: String,
    pub title: String,
    pub goal: String,
    pub note: String,
    pub textbook_lesson: Option<i64>,
    pub items: Vec<CourseItem>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Course {
    pub id: String,
    pub title: String,
    pub summary: String,
    /// The author's email: for the routes' checks only, never serialized.
    #[serde(skip)]
    pub author: String,
    /// Display name; empty when the user is gone. Never an email.
    pub author_name: String,
    pub mine: bool,
    pub status: String,
    pub follows_book: Option<String>,
    pub copied_from: Option<Value>,
    pub own_words_at: Option<String>,
    /// The snapshot that ships; kept while an approved course is edited as a draft.
    pub approved: Option<Value>,
    #[serde(skip)]
    pub approved_by: Option<String>,
    pub approved_by_name: Option<String>,
    pub approved_at: Option<String>,
    pub submitted_at: Option<String>,
    pub exported_at: Option<String>,
    pub withdrawn_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub lessons: Vec<Lesson>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CourseSummary {
    pub id: String,
    pub title: String,
    pub summary: String,
    #[serde(skip)]
    pub author: String,
    pub author_name: String,
    pub mine: bool,
    pub status: String,
    pub follows_book: Option<String>,
    pub lessons: u32,
    pub items: u32,
    pub approved: bool,
    pub updated_at: String,
}

/// A new draft course. `copied_from` is the frozen credit text of a copy.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct NewCourse {
    pub title: String,
    pub summary: String,
    pub follows_book: Option<String>,
    pub copied_from: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CourseMeta {
    pub title: String,
    pub summary: String,
    pub follows_book: Option<String>,
}

/// One lesson of a saved outline. A kept lesson sends its `id`; a new one sends `None` and gets one.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct LessonInput {
    pub id: Option<String>,
    pub title: String,
    pub goal: String,
    pub note: String,
    pub textbook_lesson: Option<i64>,
    pub items: Vec<Target>,
}

// --- Rows, shared by both backends ----------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct CourseRow {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub author: String,
    pub author_name: String,
    pub mine: i64,
    pub status: String,
    pub follows_book: Option<String>,
    pub copied_from_json: Option<String>,
    pub own_words_at: Option<String>,
    pub approved_json: Option<String>,
    pub approved_by: Option<String>,
    pub approved_by_name: Option<String>,
    pub approved_at: Option<String>,
    pub submitted_at: Option<String>,
    pub exported_at: Option<String>,
    pub withdrawn_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Deserialize)]
pub struct SummaryRow {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub author: String,
    pub author_name: String,
    pub mine: i64,
    pub status: String,
    pub follows_book: Option<String>,
    pub lessons: i64,
    pub items: i64,
    pub approved: i64,
    pub updated_at: String,
}

impl From<SummaryRow> for CourseSummary {
    fn from(r: SummaryRow) -> Self {
        CourseSummary {
            id: r.id,
            title: r.title,
            summary: r.summary,
            author: r.author,
            author_name: r.author_name,
            mine: r.mine != 0,
            status: r.status,
            follows_book: r.follows_book,
            lessons: r.lessons as u32,
            items: r.items as u32,
            approved: r.approved != 0,
            updated_at: r.updated_at,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct LessonRow {
    pub id: String,
    pub title: String,
    pub goal: String,
    pub note: String,
    pub textbook_lesson: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct CourseItemRow {
    pub lesson_id: String,
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub proposal_id: Option<i64>,
    pub title: String,
    pub subtitle: String,
    pub jlpt: Option<String>,
    pub loaded: i64,
    pub proposal_status: Option<String>,
}

impl From<CourseItemRow> for CourseItem {
    fn from(r: CourseItemRow) -> Self {
        CourseItem {
            course_kind: course_kind(&r.dataset, &r.kind).unwrap_or("other").into(),
            dataset: r.dataset,
            kind: r.kind,
            item_id: r.item_id,
            title: r.title,
            subtitle: r.subtitle,
            jlpt: r.jlpt,
            loaded: r.loaded != 0,
            proposal: match (r.proposal_id, r.proposal_status) {
                (Some(id), Some(status)) => Some(ProposalState { id, status }),
                _ => None,
            },
        }
    }
}

/// A search hit: a loaded item.
#[derive(Debug, Deserialize)]
pub struct SearchRow {
    pub dataset: String,
    pub kind: String,
    pub item_id: String,
    pub title: String,
    pub subtitle: String,
    pub jlpt: Option<String>,
}

impl From<SearchRow> for CourseItem {
    fn from(r: SearchRow) -> Self {
        CourseItem {
            course_kind: course_kind(&r.dataset, &r.kind).unwrap_or("other").into(),
            dataset: r.dataset,
            kind: r.kind,
            item_id: r.item_id,
            title: r.title,
            subtitle: r.subtitle,
            jlpt: r.jlpt,
            loaded: true,
            proposal: None,
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct KeyRow {
    pub key: String,
}

fn parse_json(text: Option<String>) -> Option<Value> {
    text.and_then(|t| serde_json::from_str(&t).ok())
}

/// A course with its lessons and items attached, in the rows' order.
pub fn assemble_course(
    row: CourseRow,
    lessons: Vec<LessonRow>,
    items: Vec<CourseItemRow>,
) -> Course {
    let mut by_lesson: BTreeMap<String, Vec<CourseItem>> = BTreeMap::new();
    for item in items {
        by_lesson
            .entry(item.lesson_id.clone())
            .or_default()
            .push(item.into());
    }
    Course {
        lessons: lessons
            .into_iter()
            .map(|l| Lesson {
                items: by_lesson.remove(&l.id).unwrap_or_default(),
                id: l.id,
                title: l.title,
                goal: l.goal,
                note: l.note,
                textbook_lesson: l.textbook_lesson,
            })
            .collect(),
        id: row.id,
        title: row.title,
        summary: row.summary,
        author: row.author,
        author_name: row.author_name,
        mine: row.mine != 0,
        status: row.status,
        follows_book: row.follows_book,
        copied_from: parse_json(row.copied_from_json),
        own_words_at: row.own_words_at,
        approved: parse_json(row.approved_json),
        approved_by: row.approved_by,
        approved_by_name: row.approved_by_name,
        approved_at: row.approved_at,
        submitted_at: row.submitted_at,
        exported_at: row.exported_at,
        withdrawn_at: row.withdrawn_at,
        created_at: row.created_at,
        updated_at: row.updated_at,
    }
}

// --- Saving an outline: the planning both backends share ------------------------------------------

/// A lesson of the outline as it will be written.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedLesson {
    pub id: String,
    pub position: i64,
    pub title: String,
    pub goal: String,
    pub note: String,
    pub textbook_lesson: Option<i64>,
    pub items: Vec<PlannedItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedItem {
    pub position: i64,
    pub target: Target,
    /// Kept from the stored row, so a reordered proposal item stays tied to its proposal.
    pub proposal_id: Option<i64>,
}

/// The `key` a `KeyRow` carries for an item (the unit separator can't occur in an id).
pub fn item_key(t: &Target) -> String {
    format!("{}\u{1f}{}\u{1f}{}", t.dataset, t.kind, t.item_id)
}

fn stored_key(lesson: &str, t: &Target) -> String {
    format!("{lesson}\u{1f}{}", item_key(t))
}

/// The keys the backend must check against `items`: every item that isn't already in that lesson of the
/// stored course.
pub fn keys_to_check(inputs: &[LessonInput], stored: &[CourseItemRow]) -> Vec<String> {
    let kept = kept_set(stored);
    let mut keys = BTreeSet::new();
    for l in inputs {
        for t in &l.items {
            if !kept.contains(&stored_key(l.id.as_deref().unwrap_or(""), t)) {
                keys.insert(item_key(t));
            }
        }
    }
    keys.into_iter().collect()
}

fn kept_set(stored: &[CourseItemRow]) -> BTreeSet<String> {
    stored
        .iter()
        .map(|r| {
            let t = Target {
                dataset: r.dataset.clone(),
                kind: r.kind.clone(),
                item_id: r.item_id.clone(),
            };
            stored_key(&r.lesson_id, &t)
        })
        .collect()
}

/// Checks an outline and gives it ids and positions. `lesson_ids` are the course's stored lesson ids (a
/// lesson that keeps its id must be one of them), `stored` its current items and `loaded` the keys (from
/// `keys_to_check`) found in `items`. Lessons without an id get one from `new_id`; an item repeated within
/// a lesson is kept once.
pub fn plan_outline(
    inputs: &[LessonInput],
    lesson_ids: &BTreeSet<String>,
    stored: &[CourseItemRow],
    loaded: &BTreeSet<String>,
    new_id: &mut dyn FnMut() -> String,
) -> Result<Vec<PlannedLesson>, CourseError> {
    let kept = kept_set(stored);
    let proposals: BTreeMap<String, i64> = stored
        .iter()
        .filter_map(|r| {
            let t = Target {
                dataset: r.dataset.clone(),
                kind: r.kind.clone(),
                item_id: r.item_id.clone(),
            };
            r.proposal_id.map(|p| (stored_key(&r.lesson_id, &t), p))
        })
        .collect();

    let mut ids: BTreeSet<String> = BTreeSet::new();
    for l in inputs {
        if let Some(id) = &l.id {
            if !lesson_ids.contains(id) {
                return Err(CourseError::Invalid(format!("unknown lesson id {id:?}")));
            }
            if !ids.insert(id.clone()) {
                return Err(CourseError::Invalid(format!("lesson id {id:?} twice")));
            }
        }
    }

    let mut lessons = Vec::new();
    for (position, l) in inputs.iter().enumerate() {
        let id = match &l.id {
            Some(id) => id.clone(),
            None => loop {
                let id = new_id();
                if !lesson_ids.contains(&id) && ids.insert(id.clone()) {
                    break id;
                }
            },
        };
        let mut seen = BTreeSet::new();
        let mut items = Vec::new();
        for t in &l.items {
            if course_kind(&t.dataset, &t.kind).is_none() {
                return Err(CourseError::Invalid(format!(
                    "{} can't be in a course",
                    t.audit_name()
                )));
            }
            let key = item_key(t);
            let stored_here = stored_key(&id, t);
            let in_course = l.id.is_some() && kept.contains(&stored_here);
            if !in_course && !loaded.contains(&key) {
                return Err(CourseError::NotLoaded(t.audit_name()));
            }
            if seen.insert(key) {
                items.push(PlannedItem {
                    position: items.len() as i64,
                    target: t.clone(),
                    proposal_id: if l.id.is_some() {
                        proposals.get(&stored_here).copied()
                    } else {
                        None
                    },
                });
            }
        }
        lessons.push(PlannedLesson {
            id,
            position: position as i64,
            title: l.title.clone(),
            goal: l.goal.clone(),
            note: l.note.clone(),
            textbook_lesson: l.textbook_lesson,
            items,
        });
    }
    Ok(lessons)
}

/// A fresh 6-character id (from `STABLE_ID_ALPHABET`) for a course or lesson; a course's caller retries
/// on `Conflict`.
pub fn new_course_id() -> String {
    crate::addition::random_stable_id()
}

/// A guarded write that changed nothing lost a race (the status moved on after the pre-check).
pub fn require_written(changes: usize, otherwise: CourseError) -> Result<(), CourseError> {
    if changes == 0 {
        Err(otherwise)
    } else {
        Ok(())
    }
}

/// How many times creating a course retries after an id collision.
pub const ID_TRIES: usize = 8;

// --- SQL ------------------------------------------------------------------------------------------

/// Appends the "course ?1 is a draft" condition to a statement's `WHERE`/`AND` head.
macro_rules! when_draft {
    ($head:literal) => {
        concat!(
            $head,
            " (SELECT status FROM courses WHERE id = ?1) = 'draft'"
        )
    };
}

/// ?1 viewer, ?2 course id.
pub const SELECT_COURSE: &str = concat!(
    "SELECT ",
    "c.id, c.title, c.summary, c.author, IFNULL(u.display_name, '') AS author_name, \
     (c.author = ?1) AS mine, c.status, c.follows_book, c.copied_from_json, c.own_words_at, c.approved_json, \
     c.approved_by, (SELECT a.display_name FROM users a WHERE a.email = c.approved_by) AS approved_by_name, \
     c.approved_at, c.submitted_at, c.exported_at, c.withdrawn_at, c.created_at, c.updated_at \
     FROM courses c LEFT JOIN users u ON u.email = c.author WHERE c.id = ?2"
);

/// ?1 course id: the course's lessons in order.
pub const SELECT_LESSONS: &str =
    "SELECT id, title, goal, note, textbook_lesson FROM course_lessons \
     WHERE course_id = ?1 ORDER BY position";

/// ?1 course id: its items in lesson and item order, with the loaded item (if any) and proposal status.
pub const SELECT_COURSE_ITEMS: &str = "SELECT ci.lesson_id, ci.dataset, ci.kind, ci.item_id, ci.proposal_id, \
     COALESCE(i.title, s.item_title, ci.item_id) AS title, IFNULL(i.subtitle, '') AS subtitle, i.jlpt AS jlpt, \
     (i.item_id IS NOT NULL) AS loaded, s.status AS proposal_status \
     FROM course_items ci JOIN course_lessons l ON l.course_id = ci.course_id AND l.id = ci.lesson_id \
     LEFT JOIN items i ON i.dataset = ci.dataset AND i.kind = ci.kind AND i.item_id = ci.item_id \
     LEFT JOIN suggestions s ON s.id = ci.proposal_id \
     WHERE ci.course_id = ?1 ORDER BY l.position, ci.position";

/// ?1 viewer: every course, newest change first.
pub const SELECT_COURSES: &str =
    "SELECT c.id, c.title, c.summary, c.author, IFNULL(u.display_name, '') AS author_name, \
     (c.author = ?1) AS mine, c.status, c.follows_book, \
     (SELECT COUNT(*) FROM course_lessons l WHERE l.course_id = c.id) AS lessons, \
     (SELECT COUNT(*) FROM course_items i WHERE i.course_id = c.id) AS items, \
     (c.approved_json IS NOT NULL) AS approved, c.updated_at \
     FROM courses c LEFT JOIN users u ON u.email = c.author ORDER BY c.updated_at DESC, c.id";

/// ?1 JSON array of keys (`item_key`): those that are loaded items.
pub const SELECT_LOADED_KEYS: &str = "SELECT dataset || char(31) || kind || char(31) || item_id AS key FROM items \
     WHERE (dataset || char(31) || kind || char(31) || item_id) IN (SELECT value FROM json_each(?1))";

/// ?1 JSON array of search texts, ?2 JSON array of `dataset/kind` pairs, ?3 limit: loaded items whose
/// title or subtitle contains any text, ignoring ASCII case.
pub const SEARCH_ITEMS: &str = "SELECT i.dataset, i.kind, i.item_id, i.title, i.subtitle, i.jlpt \
     FROM items i WHERE (i.dataset || '/' || i.kind) IN (SELECT value FROM json_each(?2)) \
     AND EXISTS (SELECT 1 FROM json_each(?1) q WHERE q.value <> '' AND \
       (instr(lower(i.title), lower(q.value)) > 0 OR instr(lower(i.subtitle), lower(q.value)) > 0)) \
     ORDER BY i.title, i.item_id LIMIT ?3";

/// `dataset/kind` pairs for the `kinds` a search names (all kinds when empty), as `SEARCH_ITEMS` ?2.
pub fn search_pairs(kinds: &[String]) -> String {
    let all: Vec<String> = COURSE_KINDS.iter().map(|k| k.to_string()).collect();
    let kinds = if kinds.is_empty() { &all } else { kinds };
    let pairs: Vec<String> = kinds
        .iter()
        .flat_map(|k| kind_targets(k))
        .map(|(d, k)| format!("{d}/{k}"))
        .collect();
    serde_json::to_string(&pairs).unwrap_or_else(|_| "[]".into())
}

/// ?1 JSON of a list of strings, for `SEARCH_ITEMS` ?1 and `SELECT_LOADED_KEYS` ?1.
pub fn json_list(values: &[String]) -> String {
    serde_json::to_string(values).unwrap_or_else(|_| "[]".into())
}

/// ?1 id, ?2 title, ?3 summary, ?4 author, ?5 follows_book, ?6 copied_from_json, ?7 now.
pub const INSERT_COURSE: &str = "INSERT INTO courses (id, title, summary, author, follows_book, copied_from_json, created_at, updated_at) \
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)";

/// ?1 id, ?2 title, ?3 summary, ?4 follows_book, ?5 now.
pub const UPDATE_COURSE_META: &str =
    "UPDATE courses SET title = ?2, summary = ?3, follows_book = ?4, updated_at = ?5 \
     WHERE id = ?1 AND status = 'draft'";

/// ?1 id, ?2 now: a saved outline touches the course.
pub const TOUCH_COURSE: &str =
    "UPDATE courses SET updated_at = ?2 WHERE id = ?1 AND status = 'draft'";

pub const DELETE_COURSE_ITEMS: &str =
    when_draft!("DELETE FROM course_items WHERE course_id = ?1 AND");
pub const DELETE_COURSE_LESSONS: &str =
    when_draft!("DELETE FROM course_lessons WHERE course_id = ?1 AND");

/// ?1 course, ?2 lesson id, ?3 position, ?4 title, ?5 goal, ?6 note, ?7 textbook lesson.
pub const INSERT_LESSON: &str = when_draft!(
    "INSERT INTO course_lessons (course_id, id, position, title, goal, note, textbook_lesson) \
     SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7 WHERE"
);

/// ?1 course, ?2 lesson id, ?3 position, ?4 dataset, ?5 kind, ?6 item id, ?7 proposal id.
pub const INSERT_COURSE_ITEM: &str = when_draft!(
    "INSERT INTO course_items (course_id, lesson_id, position, dataset, kind, item_id, proposal_id) \
     SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7 WHERE"
);

/// ?1 id, ?2 from, ?3 to, ?4 now, ?5 1 to record "nothing is copied from a textbook" (`own_words_at`).
pub const UPDATE_COURSE_STATUS: &str = "UPDATE courses SET status = ?3, updated_at = ?4, \
     own_words_at = CASE WHEN ?5 = 1 THEN ?4 ELSE own_words_at END, \
     submitted_at = CASE WHEN ?3 = 'in_review' THEN ?4 ELSE submitted_at END, \
     withdrawn_at = CASE WHEN ?3 = 'withdrawn' THEN ?4 ELSE withdrawn_at END \
     WHERE id = ?1 AND status = ?2";

/// A never-exported draft goes with its lessons, items and comments. Children first; each is guarded by
/// the course still being a never-exported draft, and the course row goes last.
pub const DELETE_DRAFT_ITEMS: &str = "DELETE FROM course_items WHERE course_id = ?1 AND \
     EXISTS (SELECT 1 FROM courses WHERE id = ?1 AND status = 'draft' AND exported_at IS NULL)";
pub const DELETE_DRAFT_LESSONS: &str = "DELETE FROM course_lessons WHERE course_id = ?1 AND \
     EXISTS (SELECT 1 FROM courses WHERE id = ?1 AND status = 'draft' AND exported_at IS NULL)";
pub const DELETE_DRAFT_COMMENTS: &str = "DELETE FROM course_comments WHERE course_id = ?1 AND \
     EXISTS (SELECT 1 FROM courses WHERE id = ?1 AND status = 'draft' AND exported_at IS NULL)";
pub const DELETE_DRAFT: &str =
    "DELETE FROM courses WHERE id = ?1 AND status = 'draft' AND exported_at IS NULL";

/// ?1 now, ?2 actor, ?3 action, ?4 target, ?5 detail, ?6 course id: the audit row of a write that left the
/// course's `updated_at` at `now`; nothing is logged if the write didn't happen.
pub const INSERT_COURSE_AUDIT: &str = "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, ?3, ?4, ?5 WHERE EXISTS (SELECT 1 FROM courses WHERE id = ?6 AND updated_at = ?1)";

/// The same for a delete: logged only once the course is gone.
pub const INSERT_COURSE_DELETE_AUDIT: &str =
    "INSERT INTO audit_log (at, actor, action, target, detail) \
     SELECT ?1, ?2, ?3, ?4, ?5 WHERE NOT EXISTS (SELECT 1 FROM courses WHERE id = ?6)";

/// How the audit log names a course.
pub fn audit_target(id: &str) -> String {
    format!("course/{id}")
}

// --- The trait ------------------------------------------------------------------------------------

#[allow(async_fn_in_trait)]
pub trait CourseStore {
    /// A new draft owned by `by`; returns its id. Audit `course.create`.
    async fn create_course(
        &self,
        new: &NewCourse,
        by: &str,
        now: &str,
    ) -> Result<String, CourseError>;

    /// The course whatever its status (who may see it is the routes' call); `viewer` sets `mine`.
    async fn course(&self, id: &str, viewer: &str) -> Result<Option<Course>, CourseError>;

    async fn courses(&self, viewer: &str) -> Result<Vec<CourseSummary>, CourseError>;

    /// A draft's title, summary and book. Audit `course.save`.
    async fn save_course_meta(
        &self,
        id: &str,
        meta: &CourseMeta,
        by: &str,
        now: &str,
    ) -> Result<(), CourseError>;

    /// A draft's title, summary and book together with its whole outline, in ONE batch: all or nothing.
    /// Audit `course.save` and `course.outline`.
    async fn save_outline(
        &self,
        course_id: &str,
        meta: &CourseMeta,
        lessons: &[LessonInput],
        by: &str,
        now: &str,
    ) -> Result<Vec<String>, CourseError>;

    /// Replaces a draft's whole outline in one batch (lesson ids, order, fields, items); returns the
    /// lesson ids in order. Audit `course.outline`.
    async fn save_lessons(
        &self,
        course_id: &str,
        lessons: &[LessonInput],
        by: &str,
        now: &str,
    ) -> Result<Vec<String>, CourseError>;

    /// Deletes a never-exported draft with its lessons, items and comments. Audit `course.delete`.
    async fn delete_draft(&self, id: &str, by: &str, now: &str) -> Result<(), CourseError>;

    /// Moves a course from one status to another (`Conflict` when it isn't in `from`). `own_words` records
    /// the author's "nothing is copied from a textbook" tick. Audit `course.status`.
    async fn set_status(
        &self,
        id: &str,
        from: &str,
        to: &str,
        own_words: bool,
        by: &str,
        now: &str,
    ) -> Result<(), CourseError>;

    /// Loaded items of the course kinds `kinds` (all when empty) whose title or subtitle contains any of
    /// `queries`, at most `limit`.
    async fn search_items(
        &self,
        queries: &[String],
        kinds: &[String],
        limit: u32,
    ) -> Result<Vec<CourseItem>, CourseError>;
}
