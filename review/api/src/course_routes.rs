//! The course routes. `app::handle` has already checked who is asking and the `Origin`; these check
//! who may see or change a course (drafts belong to their author and the owner), the body and the limits.
//! The store enforces what a course may hold (only drafts change, only loaded items go in).

use crate::app::{error, parse, ApiResponse};
use crate::auth::Principal;
use crate::course_store::{
    course_kind, kind_targets, Course, CourseError, CourseMeta, CourseStore, LessonInput,
    NewCourse, COURSE_KINDS,
};
use crate::review_routes::{ok, text_field, tri, unavailable};
use crate::review_store::{ReviewStore, Target};
use crate::romaji;
use crate::store::{Role, Store};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::BTreeSet;

pub const MAX_LESSONS: usize = 60;
pub const MAX_ITEMS: usize = 80;
pub const SEARCH_LIMIT: u32 = 40;
const MAX_QUERY: usize = 100;

const NO_COURSE: &str = "no such course";
const NOT_DRAFT: &str = "only a draft can be changed";
const NOT_GRAMMAR: &str = "grammar isn't loaded yet, so there are no textbooks to follow";

fn course_error(e: CourseError) -> ApiResponse {
    match e {
        CourseError::NotFound => error(404, NO_COURSE),
        CourseError::NotDraft => error(409, NOT_DRAFT),
        CourseError::Conflict => error(409, "this course changed while you were saving; try again"),
        CourseError::Invalid(message) => error(400, &message),
        CourseError::NotLoaded(name) => error(400, &format!("{name} is not in the loaded data")),
        CourseError::Backend(_) => error(500, "the database is unavailable"),
    }
}

/// Drafts are for their author and the owner; every other status is for everyone.
fn can_see(status: &str, author: &str, by: &Principal) -> bool {
    status != "draft" || author == by.email || by.role == Role::Admin
}

async fn visible_course<S: CourseStore>(
    store: &S,
    id: &str,
    by: &Principal,
) -> Result<Course, ApiResponse> {
    match store.course(id, &by.email).await {
        Ok(Some(course)) if can_see(&course.status, &course.author, by) => Ok(course),
        Ok(_) => Err(error(404, NO_COURSE)),
        Err(e) => Err(course_error(e)),
    }
}

fn course_json(status: u16, course: &Course) -> ApiResponse {
    ok(status, json!(course))
}

/// The text of `name` in the query, or 400.
fn required(value: Option<String>, what: &str) -> Result<String, ApiResponse> {
    value
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| error(400, &format!("{what} is missing")))
}

fn title_field(raw: &str) -> Result<String, ApiResponse> {
    let title = text_field(raw, "title")?;
    if title.is_empty() {
        return Err(error(400, "a course needs a title"));
    }
    Ok(title)
}

// --- GET /api/courses, GET /api/course ----------------------------------------------------------

pub async fn list<S: CourseStore>(by: &Principal, store: &S) -> ApiResponse {
    match store.courses(&by.email).await {
        Ok(all) => {
            let courses: Vec<_> = all
                .into_iter()
                .filter(|c| can_see(&c.status, &c.author, by))
                .collect();
            ok(200, json!({ "courses": courses }))
        }
        Err(e) => course_error(e),
    }
}

pub async fn get_one<S: CourseStore>(id: Option<String>, by: &Principal, store: &S) -> ApiResponse {
    let id = tri!(required(id, "id"));
    let course = tri!(visible_course(store, &id, by).await);
    course_json(200, &course)
}

// --- GET /api/books ------------------------------------------------------------------------------

/// The loaded grammar's textbooks: `{id, title, edition, first_lesson, lessons}`, `first_lesson` defaulting to 1.
async fn books<S: Store>(store: &S) -> Result<Vec<Value>, ApiResponse> {
    let stored = store.snapshot_json("grammar").await.map_err(unavailable)?;
    let doc: Value = stored
        .and_then(|text| serde_json::from_str(&text).ok())
        .ok_or_else(|| error(409, NOT_GRAMMAR))?;
    let books = doc["books"].as_array().cloned().unwrap_or_default();
    Ok(books
        .into_iter()
        .map(|mut book| {
            if book["first_lesson"].is_null() {
                book["first_lesson"] = json!(1);
            }
            book
        })
        .collect())
}

pub async fn list_books<S: Store>(store: &S) -> ApiResponse {
    let books = tri!(books(store).await);
    ok(200, json!({ "books": books }))
}

// --- POST /api/course/create ---------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CreateBody {
    start: String,
    #[serde(default)]
    title: String,
    #[serde(default)]
    book: Option<String>,
    #[serde(default)]
    from: Option<String>,
}

pub async fn create<S: Store + ReviewStore + CourseStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: CreateBody = tri!(parse(body));
    let course = match body.start.as_str() {
        "scratch" => {
            let title = tri!(title_field(&body.title));
            let new = NewCourse {
                title,
                ..NewCourse::default()
            };
            tri!(store
                .create_course(&new, &by.email, now)
                .await
                .map_err(course_error))
        }
        "textbook" => tri!(start_textbook(&body, by, store, now).await),
        "copy" => tri!(start_copy(&body, by, store, now).await),
        _ => return error(400, "start must be scratch, textbook or copy"),
    };
    let course = tri!(visible_course(store, &course, by).await);
    course_json(201, &course)
}

/// A course following a textbook: one empty lesson per book lesson, "Lesson n", numbered.
async fn start_textbook<S: Store + CourseStore>(
    body: &CreateBody,
    by: &Principal,
    store: &S,
    now: &str,
) -> Result<String, ApiResponse> {
    let wanted = required(body.book.clone(), "the book")?;
    let book = books(store)
        .await?
        .into_iter()
        .find(|b| b["id"] == wanted.as_str())
        .ok_or_else(|| error(400, "that textbook isn't in the loaded grammar"))?;
    let first = book["first_lesson"].as_i64().unwrap_or(1);
    let last = book["lessons"].as_i64().unwrap_or(0);
    if last - first + 1 > MAX_LESSONS as i64 {
        return Err(error(400, "that textbook has too many lessons"));
    }
    let title = if body.title.trim().is_empty() {
        book["title"]
            .as_str()
            .unwrap_or("Textbook course")
            .to_string()
    } else {
        title_field(&body.title)?
    };
    let new = NewCourse {
        title,
        follows_book: Some(wanted),
        ..NewCourse::default()
    };
    let id = store
        .create_course(&new, &by.email, now)
        .await
        .map_err(course_error)?;
    let lessons: Vec<LessonInput> = (first..=last)
        .map(|n| LessonInput {
            title: format!("Lesson {n}"),
            textbook_lesson: Some(n),
            ..LessonInput::default()
        })
        .collect();
    if !lessons.is_empty() {
        if let Err(e) = store.save_lessons(&id, &lessons, &by.email, now).await {
            // Don't leave a half-made draft behind.
            let _ = store.delete_draft(&id, &by.email, now).await;
            return Err(course_error(e));
        }
    }
    Ok(id)
}

/// A copy of an approved course's approved version, with new ids, credited as text.
async fn start_copy<S: Store + ReviewStore + CourseStore>(
    body: &CreateBody,
    by: &Principal,
    store: &S,
    now: &str,
) -> Result<String, ApiResponse> {
    let from = required(body.from.clone(), "the course to copy")?;
    // A course with an approved version can be copied by anyone, whatever state its current edits are in;
    // only that approved version is read.
    let source = match store.course(&from, &by.email).await {
        Ok(Some(c)) if c.approved.is_some() || can_see(&c.status, &c.author, by) => c,
        Ok(_) => return Err(error(404, NO_COURSE)),
        Err(e) => return Err(course_error(e)),
    };
    let Some(approved) = source.approved.as_ref() else {
        return Err(error(400, "only an approved course can be copied"));
    };
    let source_title = approved["title"]
        .as_str()
        .unwrap_or(&source.title)
        .to_string();
    let credit = store.user(&source.author).await.map_err(unavailable)?;
    let mut author =
        json!({ "role": credit.as_ref().map_or("reviewer", |u| u.public_role.as_str()) });
    if let Some(name) = credit.as_ref().and_then(|u| u.public_name.as_deref()) {
        author["name"] = json!(name);
    }
    let title = if body.title.trim().is_empty() {
        source_title.clone()
    } else {
        title_field(&body.title)?
    };
    let new = NewCourse {
        title,
        summary: approved["summary"].as_str().unwrap_or("").to_string(),
        follows_book: approved["follows"].as_str().map(String::from),
        copied_from: Some(json!({ "title": source_title, "author": author })),
    };
    let id = store
        .create_course(&new, &by.email, now)
        .await
        .map_err(course_error)?;
    let mut lessons = Vec::new();
    for lesson in approved["lessons"].as_array().into_iter().flatten() {
        let mut items = Vec::new();
        for item in lesson["items"].as_array().into_iter().flatten() {
            for target in snapshot_targets(item) {
                // An item that has since left the loaded data can't be saved; the copy drops it.
                if let Ok(Some(_)) = store.current_hash(&target).await {
                    items.push(target);
                }
            }
        }
        lessons.push(LessonInput {
            id: None,
            title: text_of(lesson, "title"),
            goal: text_of(lesson, "goal"),
            note: text_of(lesson, "note"),
            textbook_lesson: lesson["textbook_lesson"].as_i64(),
            items,
        });
    }
    if !lessons.is_empty() {
        if let Err(e) = store.save_lessons(&id, &lessons, &by.email, now).await {
            // Don't leave a half-made draft behind.
            let _ = store.delete_draft(&id, &by.email, now).await;
            return Err(course_error(e));
        }
    }
    Ok(id)
}

fn text_of(value: &Value, key: &str) -> String {
    value[key].as_str().unwrap_or("").to_string()
}

/// The `items` rows a snapshot item `{kind, id, in?}` stands for.
fn snapshot_targets(item: &Value) -> Vec<Target> {
    let (Some(kind), Some(id)) = (item["kind"].as_str(), item["id"].as_str()) else {
        return Vec::new();
    };
    kind_targets(kind)
        .iter()
        .filter(|(dataset, _)| kind != "example" || item["in"].as_str() == Some(dataset))
        .map(|(dataset, item_kind)| Target {
            dataset: dataset.to_string(),
            kind: item_kind.to_string(),
            item_id: id.to_string(),
        })
        .collect()
}

// --- POST /api/course/save -----------------------------------------------------------------------

/// An item as the page sends it. Extra fields are ignored so a course read can be saved back as it is.
#[derive(Deserialize)]
struct ItemBody {
    dataset: String,
    kind: String,
    item_id: String,
}

#[derive(Deserialize)]
struct LessonBody {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    title: String,
    #[serde(default)]
    goal: String,
    #[serde(default)]
    note: String,
    #[serde(default)]
    textbook_lesson: Option<i64>,
    #[serde(default)]
    items: Vec<ItemBody>,
}

#[derive(Deserialize)]
struct SaveBody {
    id: String,
    title: String,
    #[serde(default)]
    summary: String,
    lessons: Vec<LessonBody>,
}

fn lesson_input(lesson: LessonBody) -> Result<LessonInput, ApiResponse> {
    if lesson.items.len() > MAX_ITEMS {
        return Err(error(400, "a lesson holds at most 80 items"));
    }
    if lesson.textbook_lesson.is_some_and(|n| n < 1) {
        return Err(error(400, "a textbook lesson number starts at 1"));
    }
    let mut seen = BTreeSet::new();
    let mut items = Vec::new();
    for item in lesson.items {
        if course_kind(&item.dataset, &item.kind).is_none() {
            return Err(error(400, "that kind of item can't be in a course"));
        }
        let target = Target {
            dataset: item.dataset,
            kind: item.kind,
            item_id: item.item_id,
        };
        let key = (
            target.dataset.clone(),
            target.kind.clone(),
            target.item_id.clone(),
        );
        if !seen.insert(key) {
            return Err(error(400, "an item can be in a lesson only once"));
        }
        items.push(target);
    }
    Ok(LessonInput {
        id: lesson.id.filter(|id| !id.is_empty()),
        title: text_field(&lesson.title, "lesson title")?,
        goal: text_field(&lesson.goal, "goal")?,
        note: text_field(&lesson.note, "note")?,
        textbook_lesson: lesson.textbook_lesson,
        items,
    })
}

pub async fn save<S: CourseStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: SaveBody = tri!(parse(body));
    let course = tri!(visible_course(store, &body.id, by).await);
    if course.author != by.email {
        return error(403, "only the author can change a course");
    }
    if course.status != "draft" {
        return error(409, NOT_DRAFT);
    }
    if body.lessons.len() > MAX_LESSONS {
        return error(400, "a course holds at most 60 lessons");
    }
    let meta = CourseMeta {
        title: tri!(title_field(&body.title)),
        summary: tri!(text_field(&body.summary, "summary")),
        follows_book: course.follows_book.clone(),
    };
    let mut lessons = Vec::new();
    for lesson in body.lessons {
        lessons.push(tri!(lesson_input(lesson)));
    }
    tri!(store
        .save_outline(&body.id, &meta, &lessons, &by.email, now)
        .await
        .map_err(course_error));
    let saved = tri!(visible_course(store, &body.id, by).await);
    course_json(200, &saved)
}

// --- POST /api/course/delete ---------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct DeleteBody {
    id: String,
}

pub async fn delete<S: CourseStore>(
    body: &[u8],
    by: &Principal,
    store: &S,
    now: &str,
) -> ApiResponse {
    let body: DeleteBody = tri!(parse(body));
    let course = tri!(visible_course(store, &body.id, by).await);
    if course.author != by.email && by.role != Role::Admin {
        return error(403, "only the author or the owner can delete a course");
    }
    if course.exported_at.is_some() {
        return error(
            409,
            "this course was already published and can't be deleted",
        );
    }
    match store.delete_draft(&body.id, &by.email, now).await {
        Ok(()) => ok(200, json!({ "deleted": body.id })),
        Err(CourseError::NotDraft) => error(
            409,
            "only a draft that was never published can be deleted; take it back to a draft first",
        ),
        Err(e) => course_error(e),
    }
}

// --- GET /api/course/search ----------------------------------------------------------------------

pub async fn search<S: CourseStore>(
    query: Option<String>,
    kind: Option<String>,
    store: &S,
) -> ApiResponse {
    let Some(query) = query else {
        return error(400, "q is missing");
    };
    let query = query.trim().to_string();
    if query.is_empty() {
        return ok(200, json!({ "items": [] }));
    }
    if query.chars().count() > MAX_QUERY {
        return error(400, "that search is too long");
    }
    let kinds: Vec<String> = match kind.filter(|k| !k.is_empty()) {
        Some(k) if COURSE_KINDS.contains(&k.as_str()) => vec![k],
        Some(_) => return error(400, "unknown kind"),
        None => Vec::new(),
    };
    let mut queries = vec![query.clone()];
    queries.extend(romaji::to_hiragana(&query).filter(|k| *k != query));
    match store.search_items(&queries, &kinds, SEARCH_LIMIT).await {
        Ok(items) => ok(200, json!({ "items": items })),
        Err(e) => course_error(e),
    }
}
