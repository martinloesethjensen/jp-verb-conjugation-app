# Review site roles (polish spec step 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `teacher` access role: teachers (and the owner) accept and decline other people's suggestions, nobody decides their own, and the site's copy stops saying Martin decides everything.

**Architecture:** `users.role` widens to `admin | teacher | reviewer` (migration 0007 rebuilds the table, since SQLite can't change a `CHECK`). A new `Need::Teacher` lets a teacher or the admin through on the reviewer Access application. The inbox and decide routes move out of `/api/admin/*`, which only the owner's GitHub sign-in reaches, to `/api/inbox` and `/api/decide`. The owner sets access roles on the Reviewers page through a new admin route. The web inbox moves from `/admin/inbox` to `/inbox`.

**Tech Stack:** Rust workers-rs Worker with D1 (tests on in-memory SQLite: `tests/support/sqlite.rs`), SvelteKit 5 static site, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md`: Roles, Onboarding › Copy, Build order step 3.

## Global Constraints

- Roles table from the spec: reviewers approve, suggest, note and comment; teachers also accept or decline **others'** suggestions; the owner (`admin`) also manages reviewers, roles and queues, stamps and exports. **Nobody accepts their own suggestion**, the owner included.
- One teacher's acceptance is enough. `suggestions.decided_by` and the audit log already record who decided.
- `public_role` (owner, teacher, native) stays a credit label only. The owner sets both roles; neither changes the other.
- Copy says "another teacher or Martin accepts it", never "Martin decides".
- D1 migrations are run by the owner by hand (`npx wrangler d1 migrations apply kotobatable-review --remote`). Never run them against production.
- No secrets, AUD tags, team domain or emails in committed files.
- Worker: `cd review/api && cargo test`. Web: `cd review/web && npm run check && npm test && npm run build && npm run test:csp`. Or `make review-test`. Three Worker suites (`manifest`, `read_api`, `stepped_load`) fail on `main` already with BadSignature until the owner's next `make data-release`; every other suite must pass.
- Web CSP rules stay: no `style="…"`, no `style:` directives, no transitions.
- **Sequencing:** another branch, `claude/review-visual-refresh` (polish step 1), restyles `routes/admin/inbox/+page.svelte`, `SuggestionCard.svelte` and the header (`lib/SiteHeader.svelte`). Tasks 1–3 are Worker-only and can start now. Before Task 4, merge `main` into this branch once the visual refresh has merged there. If it hasn't merged yet, stop and ask rather than editing those files twice.

## Review Focus

1. A teacher deciding a suggestion they wrote, including an addition (`action = "add"`) and a removal: refused with 403 and the own-suggestion message. Pinned in Task 2.
2. The owner signed in with the email PIN (reviewer audience) opening `/api/inbox`: allowed, since teachers do the same. A reviewer through either audience: 403. Pinned in Task 2.
3. Demoting a teacher to reviewer while they have an inbox page open: their next decide is 403. Pinned in Task 3 (`a_demoted_teacher_can_no_longer_decide`).
4. Rows written before migration 0007 (users with `public_role`, `public_name`, inactive users) survive the table rebuild unchanged. Pinned in Task 1.
5. The owner trying to set someone's role to `admin`, or to change their own role: refused with 400, so the site never ends up with no owner or two. Pinned in Task 3.

---

### Task 1: The teacher role in the store and in `authorize`

**Files:**
- Create: `review/api/migrations/0007_teacher_role.sql`
- Modify: `review/api/src/store.rs` (`Role`), `review/api/src/auth.rs` (`Need`, `authorize`)
- Test: `review/api/tests/store.rs`, `review/api/tests/access.rs` (or wherever `authorize` is tested today; grep `fn authorize` in `tests/`)

**Interfaces:**
- Produces: `Role::Teacher` (`as_str` `"teacher"`, `parse("teacher")`); `Role::can_decide(self) -> bool` (true for `Teacher` and `Admin`); `Need::Teacher`.

- [ ] **Step 1: Write the failing tests.**
  - `tests/store.rs::migration_0007_keeps_every_user_and_allows_teacher`: build with `SqliteStore::with_migrations_before("0007")`, insert an admin (`public_role 'owner'`), an active reviewer with `public_name 'Aiko'`, and an inactive reviewer. Then `apply_migrations_from("0007")`. Assert `store.users()` returns the same three rows with identical fields. Then `UPDATE users SET role = 'teacher'` on the reviewer succeeds, and `role = 'boss'` fails the `CHECK`.
  - `authorize` tests: a `teacher` user passes `Need::Reviewer` and `Need::Teacher` with the reviewer audience and with the admin audience, and fails `Need::Admin`. A `reviewer` fails `Need::Teacher` on both audiences. An `admin` passes `Need::Teacher` on the reviewer audience. An inactive teacher fails everything.
- [ ] **Step 2: Run them.** `cargo test --test store --test access`. Expected: FAIL (no migration 0007, no `Role::Teacher`, no `Need::Teacher`).
- [ ] **Step 3: Implement.**
  - `0007_teacher_role.sql`: create `users_new` with the same columns as today: 0001's table plus 0006's `public_role TEXT NOT NULL DEFAULT 'native'` (keep 0006's `CHECK` if it has one) and `public_name TEXT`. `role` gets `CHECK (role IN ('admin', 'teacher', 'reviewer'))`. Then `INSERT INTO users_new SELECT <every column by name> FROM users`, `DROP TABLE users`, `ALTER TABLE users_new RENAME TO users`. Add a header comment saying the owner applies it by hand before deploying this Worker.
  - `Role::Teacher` with `can_decide`.
  - `authorize`: `Need::Teacher` needs `user.role.can_decide()` and either the reviewer or the admin audience. `Need::Admin` is unchanged.
- [ ] **Step 4: Run them.** Same command. Expected: PASS. Then `cargo test`. Expected: only the three known BadSignature suites fail.
- [ ] **Step 5: Commit.** `review-api: teacher access role (migration 0007, Need::Teacher)`

### Task 2: Inbox and decide for teachers, and the own-suggestion guard

**Files:**
- Modify: `review/api/src/app.rs` (route table), `review/api/src/review_routes.rs` (`decide`, the section comment "The owner's inbox")
- Test: `review/api/tests/inbox_api.rs`, `review/api/tests/additions.rs` or `add_api.rs` (whichever decides additions through `/api/admin/decide`; grep for it), `tests/support/review.rs`

**Interfaces:**
- Consumes: `Need::Teacher`, `Role::Teacher` (Task 1).
- Produces: `GET /api/inbox?status=` and `POST /api/decide`, with the same bodies and responses as today's admin routes. `pub const OWN_SUGGESTION: &str = "someone else decides your own suggestion; withdraw it instead"` in `review_routes.rs`. `/api/admin/inbox` and `/api/admin/decide` are removed (404).

- [ ] **Step 1: Write the failing tests.**
  - In `tests/support/review.rs`: add `pub const KEIKO: &str = "keiko@example.com";`, seeded as a teacher (`Role::Teacher`, display name "Keiko"). Add `pub fn jwt_via(email, aud)` and a `call_via` that takes the audience, so a test can send Martin through `"reviewer-aud"`. Every existing caller keeps today's behaviour.
  - Point the existing inbox and decide tests at `/api/inbox` and `/api/decide`.
  - `inbox_api.rs` new tests:
    - `a_teacher_sees_the_inbox_and_accepts_someone_elses_suggestion`: Aiko suggests, Keiko lists and accepts → 200. `decided_by` is Keiko (check through the response or `store.suggestion`).
    - `nobody_decides_their_own_suggestion`: Keiko suggests and tries to accept, then decline → 403 with `OWN_SUGGESTION` both times. Martin suggests and tries to accept → 403 with `OWN_SUGGESTION`. Keiko accepting Martin's → 200.
    - `an_own_addition_is_guarded_too`: Keiko adds through `/api/add`, then tries to accept it → 403.
    - `the_owner_decides_through_the_reviewer_sign_in`: Martin through `reviewer-aud` gets 200 from `GET /api/inbox`.
    - `reviewers_cannot_use_the_inbox` (rewrite): Aiko through either audience gets 403 on both routes.
    - `the_old_admin_inbox_routes_are_gone`: `GET /api/admin/inbox` → 404.
- [ ] **Step 2: Run them.** `cargo test --test inbox_api`. Expected: FAIL (404s on the new paths, no `KEIKO`).
- [ ] **Step 3: Implement.** Route table: replace the two admin routes with `GET /api/inbox` and `POST /api/decide`, `need: Need::Teacher`. In `decide`, right after the suggestion loads and before the status check, return `error(403, OWN_SUGGESTION)` when `s.mine`. Rename the section comment to "The inbox (teachers and the owner)".
- [ ] **Step 4: Run them.** `cargo test`. Expected: only the three known BadSignature suites fail.
- [ ] **Step 5: Commit.** `review-api: teachers decide suggestions; nobody decides their own`

### Task 3: The owner sets access roles

**Files:**
- Modify: `review/api/src/store.rs` (trait + `UPDATE_ROLE`), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/app.rs`
- Test: `review/api/tests/app.rs` (where `/api/admin/users/role` is tested; grep `users/role`)

**Interfaces:**
- Produces: `Store::set_role(&self, email: &str, role: Role, actor: &str, now: &str) -> Result<(), StoreError>`, writing audit row `user.role` with detail `role=<role>`; `pub const UPDATE_ROLE: &str = "UPDATE users SET role = ?1 WHERE email = ?2"`. Route `POST /api/admin/users/access`, `Need::Admin`, body `{email, role}` (`deny_unknown_fields`), response: the updated user (same shape as the other user routes).

- [ ] **Step 1: Write the failing tests.**
  - `the_owner_makes_a_reviewer_a_teacher_and_back`: role `teacher` → 200 with `role: "teacher"`, and `public_role` is unchanged. Role `reviewer` → 200. The audit log has two `user.role` rows.
  - `the_access_role_cannot_be_admin_or_touch_the_owner`: role `admin` → 400 `"there is only one owner"`. Changing Martin's own role → 400 `"the owner's role can't change here"`. Unknown email → 404. Role `boss` → 400.
  - `a_reviewer_cannot_set_roles`: Aiko → 403.
  - `a_demoted_teacher_can_no_longer_decide`: Keiko loads the inbox (200), Martin sets her to `reviewer`, Keiko's next `POST /api/decide` → 403.
- [ ] **Step 2: Run them.** Expected: FAIL (404 on the route).
- [ ] **Step 3: Implement.** `set_role` in both stores through the existing `update_user` helper, mirroring `set_public_role`. The handler mirrors `public_role` in `app.rs`: parse, `email_field`, load the user (404), refuse `Role::Admin` and refuse a target whose role is `Admin`, then `set_role` and `user_response`.
- [ ] **Step 4: Run them.** `cargo test`. Expected: only the three known BadSignature suites fail.
- [ ] **Step 5: Commit.** `review-api: the owner sets reviewers' access roles`

### Task 4: The web site: inbox for teachers, the role picker and copy

Start with the merge from Global Constraints › Sequencing.

**Files:**
- Move: `review/web/src/routes/admin/inbox/+page.svelte` → `review/web/src/routes/inbox/+page.svelte` (`git mv`)
- Modify: `review/web/src/lib/api.ts`, `review/web/src/routes/admin/+page.svelte`, the header (`lib/SiteHeader.svelte` after the visual refresh, else `routes/+layout.svelte`), `lib/SuggestionCard.svelte`, `lib/ReviewBar.svelte`, `lib/SuggestForm.svelte`, `routes/add/+page.svelte`, `routes/account/+page.svelte`, `src/dev/mock-api.ts`, `src/dev/mock-review.ts`
- Test: `lib/suggestion-card.test.ts`, `lib/site-header.test.ts` (if it exists after the merge), a new `lib/roles.test.ts`

**Interfaces:**
- Consumes: the routes from Tasks 2 and 3.
- Produces: in `api.ts`, `Role = 'admin' | 'teacher' | 'reviewer'`, `canDecide(role: Role): boolean`, `setAccessRole(email: string, role: 'teacher' | 'reviewer') => request<User>('/api/admin/users/access', …)`. The inbox fetches `/api/inbox` and decides through `/api/decide`.

- [ ] **Step 1: Write the failing tests.**
  - `roles.test.ts`: `canDecide('teacher')` and `canDecide('admin')` are true, `canDecide('reviewer')` is false.
  - `suggestion-card.test.ts`: a card rendered with `mine: true` in the inbox's decide mode shows "Yours. Another teacher or Martin accepts it." and no Accept or Decline buttons. A card with `mine: false` shows both.
  - Header test (if `site-header.test.ts` exists): `Inbox` links to `/inbox` for `role: 'teacher'` and `'admin'`, and isn't there for `'reviewer'`.
  - A source check, in the style of the visual-refresh plan's page-source tests: `src/routes/inbox/+page.svelte` exists, and no file under `src/` contains `/api/admin/inbox`, `/api/admin/decide`, `Leave a note for Martin` or `Martin will look at it`.
- [ ] **Step 2: Run them.** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - `api.ts`: the types, `canDecide`, `setAccessRole`, and the two new paths.
  - The inbox page at `/inbox`: guard with `canDecide(me.role)`. Otherwise show "Only teachers and Martin can open the inbox." Pass `mine` through, so own cards get the line above in place of the decision buttons. Its header comment says "teachers and the owner".
  - Header: an `Inbox` link for `canDecide` roles. `/inbox` is on the reviewer sign-in, so no `data-sveltekit-reload` is needed from reviewer pages. Keep the existing reload attribute on links into `/admin`.
  - Reviewers page (`routes/admin/+page.svelte`): the link to the inbox becomes `/inbox` with `data-sveltekit-reload` (it leaves the admin sign-in). For every user who isn't the admin, add a select labelled "Can" with options `review and suggest` (`reviewer`) and `also accept suggestions` (`teacher`), calling `setAccessRole`. The admin shows "Owner". Keep the "Credited as" select beside it, unchanged.
  - Copy, exactly:
    - `add`: "Sent. Martin will look at it." → "Sent. A teacher or Martin will look at it."
    - `SuggestionCard`: `'left a note for Martin'` → `'left a note'`, and "Martin's version:" → "Edited when accepted:".
    - `ReviewBar`: "Leave a note for Martin" → "Leave a note", and "Your note for Martin" → "Your note".
    - `SuggestForm`: "Leave a note for Martin if they're wrong." → "Leave a note if they're wrong."
    - `account`: "This is how Martin and the other reviewers see you on this site." → "This is how the other reviewers see you on this site."
    - Leave "Martin asks:" (queues), "Martin will add things to review here." and `ADD_NOTE` (export) as they are: those stay the owner's.
  - Dev mock: `mock-api.ts` adds a teacher user (`keiko@example.com`, "Keiko", `role: 'teacher'`, `public_role: 'teacher'`) and `MOCK_ROLE=teacher`. It serves `/inbox` and `/decide` in place of the admin paths (in `mock-review.ts`), refuses deciding one's own suggestion with the same message, refuses both for reviewers, and handles `/admin/users/access`.
- [ ] **Step 4: Run them.** `npm run check && npm test && npm run build && npm run test:csp`. Expected: all pass. Then a browser check with `MOCK_ROLE=teacher`: the inbox opens from the header, and an own suggestion has no Accept button.
- [ ] **Step 5: Commit.** `review-web: inbox for teachers, access-role picker, copy for shared decisions`

### Task 5: Docs

**Files:**
- Modify: `review/README.md`, `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (an "As built" note under Roles)

- [ ] **Step 1: README.**
  - Under "Adding and removing reviewers": how to make someone a teacher (Reviewers page › Can), and that teachers sign in like reviewers (email PIN). The admin Access application stays the owner's alone.
  - Under Deploying: before deploying this Worker, run migration 0007 with `npx wrangler d1 migrations apply kotobatable-review --remote`. The inbox moved from `/admin/inbox` to `/inbox`, and on the email-PIN sign-in.
  - Open suggestions written by the owner now need a teacher to decide them.
- [ ] **Step 2: Spec "As built".** The inbox and decide routes left `/api/admin/*` so teachers can reach them. The owner's decisions now go through the reviewer sign-in too.
- [ ] **Step 3: Check and commit.** `make review-test`. Expected: only the three known BadSignature suites fail. Commit: `docs: teacher role in the review README and the polish spec`
