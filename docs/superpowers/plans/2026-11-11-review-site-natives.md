# Review site step 3b: natives accept Japanese fields — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new `native` access role whose holders accept, edit-then-accept or decline other people's
`change` suggestions that edit only Japanese text (plus furigana), with the Worker enforcing it and the
inbox mirroring it.

**Architecture:** The Worker gains one pure module, `review/api/src/japanese.rs`, holding the Japanese
field list and `japanese_only(proposed, current)`. `/api/decide` asks it before letting a native decide,
and `/api/inbox` returns its answer per suggestion as `japanese_only`, so the web never re-derives the rule.
`Role::can_decide` widens to "may decide some suggestions" (teacher, native, owner) and `Role::decides_all`
keeps "decides everything" (teacher, owner); the web's `roles.ts` mirrors both names.

**Tech Stack:** Rust Cloudflare Worker + D1 (SQLite in tests), SvelteKit / Svelte 5, Vitest.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (Roles; build order 3b), read
from `origin/claude/review-open-questions` until PR 230 merges.

## Global Constraints

- `users.role` is `admin | teacher | native | reviewer`; `public_role` stays a credit label only.
- Japanese fields = the web's `JAPANESE_FIELDS` in `review/web/src/lib/labels.ts`; a test keeps the Worker's list equal to it.
- A native decides only another person's `change` whose every edited field is Japanese; furigana it adds is allowed. Every `add`, `delete`, `note`, and any change touching English, a choice field or an id, needs a teacher or the owner.
- A native's Edit then accept may only edit Japanese fields.
- Nobody decides their own suggestion (existing guard, unchanged).
- Migration number **0010** (`0009` is taken by the unmerged step 5 branch).
- Don't touch the Settings or Account page, `SiteHeader.svelte`, or tour/onboarding files.
- CSP: no `style=""`, `style:` or Svelte transitions. Light-only tokens; touch targets ≥ 44 px; kanji through `Japanese.svelte`.
- Never touch `data/`, never run `make data-release`, `make sign-commit` or `make review-pull`.

## Rulings (decisions this plan makes where the spec is silent)

1. **What "edited" means.** A change's edited fields are the keys whose values differ between its
   `proposed` item and the item **as loaded now** (`current`). `particle_blanks` is ignored: reviewers
   can't edit it, and it only differs because a `jp` edit dropped blanks that export marks again. An empty
   difference, or a target no longer in the data, is not Japanese-only.
2. **Stale changes fail closed.** Diffing against the current item means a suggestion whose item later
   changed in a non-Japanese field goes to a teacher. Teachers already handle stale changes with Edit then
   accept.
3. **Native's edits** are checked by key: every key in `edits` must be a Japanese field (edits are applied to
   the current item, so the keys are exactly what changes).
4. **Declining** follows the same rule as accepting: a native can't decline what they couldn't accept.
5. **Names.** `can_decide`/`canDecide` now means "opens the inbox and decides some suggestions" (teacher,
   native, owner); `decides_all`/`decidesAll` means teacher or owner. `Need::Teacher` becomes `Need::Decider`.
   Because `SiteHeader.svelte` already shows the Inbox link on `canDecide`, natives get the link without
   editing that file.
6. **Copy.** Refusal: `a teacher or Martin decides this one: it changes more than Japanese text` (403). Inbox
   line on a suggestion a native can't decide: `A teacher or Martin decides this one.` A native's own open
   suggestion: `Yours. Someone else accepts it.` Reviewers page "Can" options: `review and suggest`,
   `also accept Japanese fixes` (native), `also accept suggestions` (teacher).

## Review Focus

- A native accepting a change that edits `jp` **and** `en` — must be refused by the Worker even if the UI showed a button (Task 2 test).
- A native's Edit then accept that sneaks in an `en` edit on a Japanese-only suggestion — refused (Task 2 test).
- A `jp` edit that drops particle blanks — still Japanese-only (Task 1 test).
- A stale Japanese-only change where the item's English changed since — not Japanese-only for a native (Task 1 test: diff against current).
- A demoted native (back to reviewer) hitting `/api/decide` — 403 (Task 2 test, mirrors the teacher one).

---

### Task 1: The `native` role, the migration, and the Japanese-field rule (Worker, pure parts)

**Files:**
- Create: `review/api/migrations/0010_native_role.sql` (rebuild `users` like `0007`, CHECK gains `'native'`)
- Create: `review/api/src/japanese.rs`; register in `review/api/src/lib.rs`
- Modify: `review/api/src/store.rs` (`Role::Native`, `can_decide`, `decides_all`)
- Modify: `review/api/src/auth.rs` (`Need::Teacher` → `Need::Decider`), `review/api/src/app.rs` (two routes)
- Test: `review/api/tests/japanese.rs` (new), `review/api/tests/store.rs`

**Interfaces:**
- Produces: `review_api::japanese::JAPANESE_FIELDS: &[&str]`; `is_japanese_field(name: &str) -> bool`;
  `edited_fields(proposed: &Value, current: &Value) -> BTreeSet<String>` (ignores `particle_blanks`);
  `japanese_only(proposed: &Value, current: &Value) -> bool` (non-empty and all Japanese; false when either isn't an object).
- Produces: `Role::Native` (`"native"`), `Role::can_decide()` = admin|teacher|native, `Role::decides_all()` = admin|teacher; `Need::Decider`.

- [ ] **Step 1: Failing tests** in `tests/japanese.rs`: `jp`-only diff is true; `jp`+`en` false; `id` change false; `particle_blanks` difference alone is false (empty) and with `jp` true; identical items false; `Value::Null` current false; and `the_list_matches_the_web` — read `../web/src/lib/labels.ts`, take the quoted names between `JAPANESE_FIELDS = new Set([` and `]);`, compare as sets with `JAPANESE_FIELDS`. In `tests/store.rs`: `migration_0010_keeps_every_user_and_allows_native` (copy of the 0007 test with `with_migrations_before("0010")`), role tests (`Role::parse("native")`, `can_decide`/`decides_all` per role), and the authorize test extended: a native passes `Need::Decider` on both audiences and fails `Need::Admin`.
- [ ] **Step 2:** `cargo test` in `review/api` — fails to compile (`japanese`, `Native`, `Decider` missing).
- [ ] **Step 3:** Implement the migration, module, role and rename.
- [ ] **Step 4:** `cargo test` — all pass.
- [ ] **Step 5:** Commit `review-api: native access role (migration 0010) and the Japanese-field rule`.

### Task 2: `/api/decide`, `/api/inbox` and `/api/admin/users/access` for natives

**Files:**
- Modify: `review/api/src/review_routes.rs` (`inbox`, `decide`, new const `NATIVE_LIMIT`)
- Modify: `review/api/tests/support/review.rs` (seed `HANA`, display name "Hana", role native)
- Test: `review/api/tests/inbox_api.rs`, and the access-role test in `review/api/tests/app.rs`

**Interfaces:**
- Consumes: Task 1's `japanese_only`, `is_japanese_field`, `Role::decides_all`.
- Produces: every inbox suggestion carries `"japanese_only": bool` (`action == "change"` and `japanese_only(proposed, current)`); `pub const NATIVE_LIMIT: &str = "a teacher or Martin decides this one: it changes more than Japanese text";`.

- [ ] **Step 1: Failing tests** in `inbox_api.rs` (suggest via the existing helpers; add a `suggest_jp` helper that edits the example's `jp`):
  `a_native_sees_the_inbox_with_japanese_only_flags` (jp change → true, en change → false);
  `a_native_accepts_and_declines_a_japanese_only_change` (`decided_by` is Hana);
  `a_native_cannot_decide_english_or_mixed_changes` (en, jp+en: accept and decline → 403 `NATIVE_LIMIT`);
  `a_native_cannot_decide_additions_removals_or_notes` (403 each);
  `a_natives_edit_then_accept_may_only_edit_japanese` (edits `{"en": …}` → 403; `{"jp": …}` → 200);
  `a_native_does_not_decide_their_own_suggestion` (403 `OWN_SUGGESTION`);
  `a_demoted_native_can_no_longer_decide`.
  In `app.rs`: the owner sets `native` through `POST /api/admin/users/access` and the user reads back `"role": "native"`.
- [ ] **Step 2:** `cargo test` — the new tests fail.
- [ ] **Step 3:** In `decide`, right after the own-suggestion and decided checks: if `!by.role.decides_all()`, require `s.action == "change"`, `japanese_only(proposed, current_json(..))`, and every edit key `is_japanese_field`; else 403 `NATIVE_LIMIT`. In `inbox`, set `value["japanese_only"]`.
- [ ] **Step 4:** `cargo test` and `cargo clippy --all-targets` (if the repo uses it) — pass.
- [ ] **Step 5:** Commit `review-api: natives decide Japanese-only changes`.

### Task 3: The web — roles, inbox, Reviewers page, mock

**Files:**
- Modify: `review/web/src/lib/api.ts` (`Role` gains `'native'`; `InboxSuggestion.japanese_only: boolean`; `setAccessRole` takes `'teacher' | 'native' | 'reviewer'`)
- Modify: `review/web/src/lib/roles.ts`, `review/web/src/routes/inbox/+page.svelte`, `review/web/src/routes/admin/+page.svelte`
- Modify: `review/web/src/dev/mock-api.ts`, `review/web/src/dev/mock-review.ts` (a native "Hana"; `MOCK_ROLE=native`; inbox `japanese_only`; `/decide` mirrors the rule)
- Test: `review/web/src/lib/roles.test.ts`

**Interfaces:**
- Consumes: Task 2's `japanese_only` field and Rulings copy.
- Produces (`roles.ts`): `canDecide(role)` (teacher|native|admin), `decidesAll(role)` (teacher|admin),
  `mayDecide(role, s: { japanese_only: boolean }) => boolean`, `editableFields(role, fields: Field[]) => Field[]` (natives get only `JAPANESE_FIELDS`),
  `TEACHER_DECIDES = 'A teacher or Martin decides this one.'`, `ownSuggestionLine('native') === 'Yours. Someone else accepts it.'`.

- [ ] **Step 1: Failing tests** in `roles.test.ts`: the role cases above; `mayDecide('native', {japanese_only: false})` false and true case; `editableFields('native', [jp, en])` keeps only `jp`, teachers keep both; source checks — the inbox page uses `mayDecide(` and `TEACHER_DECIDES`, and `editableFields(`; the Reviewers page has `<option value="native">`.
- [ ] **Step 2:** `npx vitest run src/lib/roles.test.ts` in `review/web` — fails.
- [ ] **Step 3:** Implement. Inbox: `{#if s.mine}` own line `{:else if !mayDecide(me().role, s)}` `<p class="hint">{TEACHER_DECIDES}</p>` `{:else}` existing buttons; `SuggestForm fields={editableFields(me().role, fieldsOf(s))}`; `canEdit` uses the same filtered list. The "not allowed" notice reads `Only teachers, native speakers with accept access and Martin can open the inbox.`
- [ ] **Step 4:** `make review-test` from the repo root — passes.
- [ ] **Step 5:** Browser check with `MOCK_ROLE=native` (launch config on its own port in the untracked `.claude/launch.json`): Inbox link shows; Japanese-only suggestion has the three buttons and Edit shows only Japanese fields; English one shows the teacher line; phone width too. Remove the launch config afterwards.
- [ ] **Step 6:** Commit `review-web: natives in the inbox and on the Reviewers page`.

### Task 4: Docs and review

**Files:** `review/README.md` (Teachers paragraph gains Natives; Deploying gains the 0010 migration note), the spec's Roles section ("As built (step 3b, 2026-11-11)").

- [ ] **Step 1:** Write both, in the step 3 note's style.
- [ ] **Step 2:** One whole-branch review by a fresh reviewer; fix findings.
- [ ] **Step 3:** Commit, push, open a ready PR against `main`.
