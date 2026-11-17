# Review site settings and onboarding (polish spec step 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give reviewers a Settings page, keyboard shortcuts on the queue, a first-run tour (desktop and phone) and one-time tips, all remembered per person.

**Architecture:** A new `user_settings` row per person (migration 0009) holds the tour state, tips and the shortcuts switch. One route reads it and one changes it. On the site, a `settings` rune store loads with the session; the Settings page replaces Account. Shortcuts are a pure keymap plus `data-shortcut` attributes on the queue's existing buttons, so a key presses the same button a mouse would. The desktop tour adds a class to `data-tour` targets instead of positioning anything, which keeps to the CSP.

**Tech Stack:** Rust workers-rs Worker with D1 (tests on in-memory SQLite), SvelteKit 5 static site with runes, Vitest (`svelte/server` render tests).

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md`: Settings, Onboarding, Screens › Keyboard shortcuts and Onboarding, Build order step 5.

## Global Constraints

- **The owner's decisions for this plan:**
  - No Email section until step 9: no email columns, switches or copy now.
  - The desktop tour waits for the first queue. The welcome dialog comes first, and the tour is marked seen only when the queue steps finish or are skipped.
  - One plan.
- **Settings sections:**
  - Profile: the name; the public credit already on the Account page; the role and what it allows.
  - Help: Show the tour again; Tips on pages; Keyboard shortcuts.
  - Saved automatically: no Save button for switches.
- **Shortcuts** (queue page, desktop):
  - A Looks right; S Suggest a change; X skip; N note; U undo approval.
  - J or → next item; K or ← previous item; O open the entry; R reply.
  - Esc cancels or closes; ⌘Enter (Ctrl+Enter off Mac) sends; ? opens help.
  - Off while typing in a field, except Esc and ⌘Enter. Removal has no shortcut. Settings can switch them off.
- **Tour copy** says "another teacher or Martin accepts it", never "Martin decides".
- **Tips:** one-time hints the first time someone opens the inbox or a thread. The courses tip waits for step 7.
- **"Show the tour again"** clears the tour state, so the tour starts the next time Home opens.
- D1 migrations are run by the owner by hand (`npm run migrate` in `review/api`). Never run them against production.
- **Web rules:**
  - CSP: no `style="…"`, no `style:` directives, no transitions.
  - Light only. Red only for counts, the new-since line, errors and corrections.
  - Touch targets ≥ 44 px (48 px in phone bars). Furigana on every kanji.
  - Reduced motion skips any animation.
  - The phone breakpoint is `@media (max-width: 720px)` (`MediaQuery('max-width: 720px')` in script).
- **Full check:** `make review-test`, plus `cd review/api && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo clippy --target wasm32-unknown-unknown -- -D warnings`. Never hold the test store's `RefCell` borrow across an `.await`.

## Review Focus

1. **Settings fail to load:** the site works, shortcuts stay on, and neither the tour nor tips appear, so nobody gets nagged on every page. Pinned in Task 2 (`a_failed_load_keeps_defaults_and_shows_no_onboarding`).
2. **Typing in a reply box or a field:** letters never trigger actions, while Esc and ⌘Enter still work. Pinned in Task 3 (`letters_do_nothing_while_typing`).
3. **A tour step whose target isn't on the page** (a finished queue has no Looks right; an approved item shows Undo): that step is skipped, never stuck. Pinned in Task 4 (`steps_without_a_target_are_skipped`).
4. **"Show the tour again" then Home:** the welcome appears again. On a phone, the cards appear. Pinned in Tasks 1 and 4.
5. **Dismissing a tip twice, an unknown tip id, or a burst of requests:** the list never holds duplicates, and an unknown id gets 400. Pinned in Task 1.

---

### Task 1: `user_settings` in the Worker

**Files:**
- Create: `review/api/migrations/0009_user_settings.sql`, `review/api/src/settings_routes.rs`, `review/api/tests/settings_api.rs`
- Modify: `review/api/src/store.rs` (types, SQL, `Store` trait), `review/api/src/d1.rs`, `review/api/tests/support/sqlite.rs`, `review/api/src/app.rs` (routes), `review/api/src/lib.rs`

**Interfaces:**
- Produces:
  - **Table:** `user_settings (user TEXT PRIMARY KEY, welcome_seen_at TEXT, tour_seen_at TEXT, tips_on INTEGER NOT NULL DEFAULT 1 CHECK (tips_on IN (0, 1)), tips_dismissed TEXT NOT NULL DEFAULT '[]', shortcuts_on INTEGER NOT NULL DEFAULT 1 CHECK (shortcuts_on IN (0, 1)))`. No row means every default.
  - **`UserSettings`** (`Serialize`), in `store.rs`:
    - `{ welcome_seen_at: Option<String>, tour_seen_at: Option<String>, tips_on: bool, tips_dismissed: Vec<String>, shortcuts_on: bool }`
    - with `Default` (`tips_on` and `shortcuts_on` true).
  - **`pub const TIPS: &[&str] = &["inbox", "thread"];`**
  - **`Store::settings(&self, user: &str) -> Result<UserSettings, StoreError>`**
  - **`Store::change_settings(&self, user: &str, change: &SettingsChange, now: &str) -> Result<(), StoreError>`**, where
    `SettingsChange { tips_on: Option<bool>, shortcuts_on: Option<bool>, tour: Option<TourStep>, dismiss_tip: Option<String> }` and `TourStep` is `Welcomed | Done | Reset`.
    - Welcomed sets `welcome_seen_at = now`.
    - Done sets `tour_seen_at = now`, and `welcome_seen_at` too if null.
    - Reset clears both.
    - A dismissed tip is appended only if absent.
    - One upsert, no audit row: preferences aren't data changes.
  - **Routes** (both `Need::Reviewer`):
    - `GET /api/settings` returns `UserSettings`.
    - `POST /api/settings` takes a body (`deny_unknown_fields`) `{ tips_on?, shortcuts_on?, tour?: "welcomed" | "done" | "reset", dismiss_tip? }`. An empty body, or a `dismiss_tip` not in `TIPS`, gets 400. It returns the new `UserSettings`.

- [ ] **Step 1: Write the failing tests** in `settings_api.rs`, using `support::review`:
  - `a_new_person_gets_the_defaults`: the `GET` returns both times null, `tips_on` and `shortcuts_on` true, and `tips_dismissed` `[]`.
  - `switches_save_one_at_a_time`: `{"shortcuts_on": false}` leaves `tips_on` true, then `{"tips_on": false}` leaves `shortcuts_on` false.
  - `the_tour_moves_from_welcome_to_done_and_resets`:
    - `welcomed` sets only `welcome_seen_at`;
    - `done` sets `tour_seen_at`;
    - `reset` clears both;
    - `done` straight from new sets both.
  - `tips_are_dismissed_once_and_unknown_ones_refused`: dismissing `inbox` twice gives `["inbox"]`; `"nope"` gets 400; `{}` gets 400.
  - `settings_are_per_person`: Aiko's change doesn't show in Ben's `GET`.
- [ ] **Step 2: Run them.** `cd review/api && cargo test --test settings_api`. Expected: FAIL (404).
- [ ] **Step 3: Implement.**
  - The migration, with a header comment that the owner applies it by hand.
  - The SQL in `store.rs`, both stores, the handlers in `settings_routes.rs`, and the routes.
  - Read and write `tips_dismissed` as a JSON array: `serde_json` in Rust, so no SQLite JSON functions are needed.
- [ ] **Step 4: Run them.** `cargo test --no-fail-fast`, `cargo fmt --check` and both Clippy runs. Expected: all pass.
- [ ] **Step 5: Commit.** `review-api: user_settings (migration 0009) and the settings routes`

### Task 2: The settings store and the Settings page

**Files:**
- Create: `review/web/src/lib/settings.svelte.ts`, `review/web/src/routes/settings/+page.svelte`, `review/web/src/lib/settings.test.ts`, `review/web/src/lib/RoleSummary.svelte`
- Modify: `review/web/src/lib/api.ts`, `review/web/src/routes/+layout.svelte`, `review/web/src/routes/account/+page.svelte` (becomes a redirect), `review/web/src/lib/SiteHeader.svelte` ("Your name" becomes "Settings", linking to `/settings`), `review/web/src/lib/site-header.test.ts`, `review/web/src/dev/mock-api.ts`, `review/web/src/csp.test.ts` (add `settings.html`)

**Interfaces:**
- Consumes: the Task 1 routes.
- Produces:
  - **`api.ts`:** `type UserSettings` (as Task 1), `getSettings()`, and `changeSettings(change: { tips_on?: boolean; shortcuts_on?: boolean; tour?: 'welcomed' | 'done' | 'reset'; dismiss_tip?: string })`.
  - **`settings.svelte.ts`:** `export const settings` with
    - `$state` `value: UserSettings`, starting at the defaults;
    - `loaded: boolean`;
    - `load(): Promise<void>`: on failure keeps the defaults and `loaded = false`;
    - `change(c): Promise<void>`: optimistic; on failure puts the old value back and rethrows, so the page can say so.
    - Derived helpers: `showTips` (`loaded && value.tips_on`) and `tipOpen(id: string)` (`showTips` and the id not dismissed).
  - **`RoleSummary`** (`{ role: Role }`) shows the role name and what it allows, exactly:
    - reviewer: "Reviewer: you approve items, suggest changes, leave notes and reply."
    - teacher: "Teacher: you also accept or decline other people's suggestions."
    - admin: "Owner: you also manage reviewers, queues, stamps and exports."
  - **`/settings` page:** `h1` "Settings", with two sections.
    - **Profile:** the name form and the public-credit form, moved from `account/+page.svelte` unchanged, then `RoleSummary`.
    - **Help:**
      - a "Show the tour again" button: `change({ tour: 'reset' })`, then the status "The tour starts next time you open Home.";
      - a "Tips on pages" switch;
      - a "Keyboard shortcuts" switch with a "See the shortcuts" link button, which opens `KeyboardHelp` (Task 3).
      - Each switch shows "Saved" or the error next to it.
  - **`/account`** redirects with `location.replace('/settings')` in `onMount`, and shows a "Settings moved" link while it does.

- [ ] **Step 1: Write the failing tests** (`settings.test.ts`, with `fetch` stubbed as in `api.test.ts`):
  - **`a_failed_load_keeps_defaults_and_shows_no_onboarding`:** with `fetch` rejecting, `settings.load()` resolves, `value.shortcuts_on` is true, `showTips` is false and `tipOpen('inbox')` is false.
  - **`a_failed_change_puts_the_old_value_back`:** with `shortcuts_on` true and the POST answering 500, `change({ shortcuts_on: false })` rejects and `value.shortcuts_on` is true again.
  - **Render `RoleSummary`** for the three roles, checking the exact strings above.
  - **`site-header.test.ts`:** the header links to `/settings` with the text "Settings", and no longer to `/account`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** The layout calls `settings.load()` once `me` is known, next to `replies.refresh()`. The mock keeps settings per mock user and validates as Task 1 does.
- [ ] **Step 4: Run them.** `cd review/web && npm run check && npx vitest run --exclude src/csp.test.ts && npm run build && npm run test:csp`. Expected: all pass.
- [ ] **Step 5: Commit.** `review-web: Settings page (profile, role, help) replacing Account`

### Task 3: Keyboard shortcuts on the queue

**Files:**
- Create: `review/web/src/lib/shortcuts.ts`, `review/web/src/lib/KeyboardHelp.svelte`, `review/web/src/lib/shortcuts.test.ts`
- Modify: `review/web/src/lib/ReviewBar.svelte` (`data-shortcut` on its buttons and reply box), `review/web/src/lib/ReviewCard.svelte` (`data-shortcut="open"` on the entry link), `review/web/src/routes/queue/+page.svelte` (the key handler), `review/web/src/routes/settings/+page.svelte` (opens `KeyboardHelp`)

**Interfaces:**
- Consumes: `settings.value.shortcuts_on` (Task 2).
- Produces:
  - **`type Shortcut`:** `'approve' | 'suggest' | 'skip' | 'note' | 'undo' | 'next' | 'previous' | 'open' | 'reply' | 'cancel' | 'send' | 'help'`.
  - **`shortcutFor(e: { key: string; metaKey: boolean; ctrlKey: boolean; altKey: boolean; shiftKey: boolean }, typing: boolean): Shortcut | null`**, matching keys case-insensitively:
    - `a` approve, `s` suggest, `x` skip, `n` note, `u` undo;
    - `j` or `ArrowRight` next; `k` or `ArrowLeft` previous;
    - `o` open, `r` reply, `?` help;
    - `Escape` cancel; `Enter` with `metaKey` or `ctrlKey` send.
    - Any other modifier combination returns null. While `typing`, everything returns null except cancel and send.
  - **`isTyping(target: EventTarget | null): boolean`:** true for `input`, `textarea`, `select` and contenteditable.
  - **`SHORTCUT_HELP: [keys: string, what: string][]`**, the rows `KeyboardHelp` lists, in the spec's order.
  - **The queue page handler** (`<svelte:window onkeydown>`, desktop and only when `settings.value.shortcuts_on`):
    - `next` and `previous` move the selection within the current filter.
    - `help` opens `KeyboardHelp`.
    - `send` submits the form that holds the focused field.
    - Every other shortcut clicks the first visible `[data-shortcut="<name>"]` inside the current card, and focuses it for `reply`.
    - When nothing matches, nothing happens and the default isn't prevented.
  - **`KeyboardHelp`:** a `<dialog>` with a table of `SHORTCUT_HELP`, `kbd` keys and Esc to close.

- [ ] **Step 1: Write the failing tests** in `shortcuts.test.ts`:
  - **The keymap:** a, A, j, ArrowRight, ?, Escape and ⌘Enter each map as listed; Ctrl+A and Alt+N return null.
  - **`letters_do_nothing_while_typing`:** with `typing` true, a, j and ? return null, while Escape gives cancel and Ctrl+Enter gives send.
  - **`isTyping`:** checked against tag-shaped stubs.
  - **Render `ReviewBar`** for an unapproved item: it contains `data-shortcut="approve"` and `data-shortcut="suggest"`, and no `data-shortcut` for removal.
  - **Render `KeyboardHelp`:** it lists "Looks right" with the key A.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Find what attributes `ReviewBar` and `ReviewCard` need by rendering them, and keep the buttons' existing behaviour.
- [ ] **Step 4: Run them.** The full web check. Then, in the browser with the dev mock on a queue:
  - A stamps the item, U undoes it, J moves on;
  - typing "a" in the reply box only types it;
  - ? opens help and Esc closes it;
  - with the Settings switch off, A does nothing.
- [ ] **Step 5: Commit.** `review-web: keyboard shortcuts on the queue and their help`

### Task 4: The desktop tour

**Files:**
- Create: `review/web/src/lib/tour.ts`, `review/web/src/lib/WelcomeDialog.svelte`, `review/web/src/lib/TourGuide.svelte`, `review/web/src/lib/tour.test.ts`
- Modify: `review/web/src/routes/+page.svelte` (welcome), `review/web/src/routes/queue/+page.svelte` (`TourGuide` and the `data-tour` targets on the list), `review/web/src/lib/ReviewCard.svelte` (`data-tour="item"` on the item), `review/web/src/lib/ReviewBar.svelte` (`data-tour="approve"` and `data-tour="suggest"`), `review/web/src/lib/RepliesBell.svelte` (`data-tour="bell"`), `review/web/src/app.css` (`.tour-target`)

**Interfaces:**
- Consumes: `settings` (Task 2).
- Produces:
  - **`type TourTarget = 'list' | 'item' | 'approve' | 'suggest' | 'bell'`.** `TOUR_STEPS: { target: TourTarget; title: string; text: string }[]`, exactly:
    1. list: "Your queue". "These are the items Martin picked for you. Done ones get a check, and you can jump to any of them."
    2. item: "Read it like a teacher". "Check the Japanese, the reading and the English. Is it natural? Is it right?"
    3. approve: "Looks right". "If it's right, stamp it with your seal. You can undo it."
    4. suggest: "Suggest a change". "If something's off, fix it in place. Another teacher or Martin accepts it before it reaches the app."
    5. bell: "Replies". "When someone answers you, or your suggestion is accepted or declined, the bell shows a red count."
  - **`TOUR_CLOSING`** = `{ title: "You're ready", text: "Find this tour again, tips and keyboard shortcuts in Settings › Help." }`
  - **`availableSteps(has: (t: TourTarget) => boolean)`:** the steps whose target is present.
  - **`shouldWelcome(s: UserSettings, loaded: boolean, phone: boolean): boolean`:** `loaded`, not `phone`, and both times null.
  - **`shouldTour(s: UserSettings, loaded: boolean, phone: boolean): boolean`:** `loaded`, not `phone`, `welcome_seen_at` set and `tour_seen_at` null.
  - **`WelcomeDialog`:** a modal `<dialog>` on Home.
    - Title "Welcome to Kotoba Table review". Text: "You help make the app's Japanese right. A short tour shows you around the first time you open a queue."
    - **Start** sends `tour: 'welcomed'`. **Skip the tour** sends `tour: 'done'`.
  - **`TourGuide`** on the queue page, once `shouldTour` is true and the current item has rendered:
    - adds `.tour-target` to `[data-tour="<target>"]`, scrolls it into view (no smooth scroll under reduced motion), and shows the step in a fixed card (CSS class only);
    - **Back** goes to the previous step; **Next** goes to the next one, and the last step goes to `TOUR_CLOSING`; **Skip** and the closing **Done** send `tour: 'done'`;
    - removes the class on every step change and on unmount.

- [ ] **Step 1: Write the failing tests** in `tour.test.ts`:
  - `shouldWelcome` and `shouldTour` across the four states:
    - new: welcome;
    - welcomed: tour;
    - done: neither;
    - reset: welcome again.
    Neither when not loaded or on a phone.
  - **`steps_without_a_target_are_skipped`:** with `has` false for approve, `availableSteps` gives list, item, suggest and bell.
  - Render `WelcomeDialog` with the title and both buttons.
  - Render `TourGuide` at step 0, showing "Your queue", Back disabled, then Next and Skip.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** `.tour-target` raises the element above a dimmed page using `position: relative; z-index` and a 3 px ink outline with a paper gap. The dim is a fixed `::backdrop`-like sibling with a CSS class, never inline styles.
- [ ] **Step 4: Run them.** The full web check. Then a browser check with a fresh mock user and a queue:
  - Home shows the welcome, and Start closes it;
  - opening the queue starts the steps, which highlight in order;
  - Done or Skip ends the tour, and it doesn't come back after a reload;
  - Settings › Show the tour again brings the welcome back on Home.
- [ ] **Step 5: Commit.** `review-web: welcome dialog and the desktop tour on the first queue`

### Task 5: The phone welcome

**Files:**
- Create: `review/web/src/lib/PhoneWelcome.svelte`
- Modify: `review/web/src/routes/+page.svelte`, `review/web/src/lib/tour.ts`, `review/web/src/lib/tour.test.ts`

**Interfaces:**
- Consumes: `settings`, `tour.ts` (Task 4).
- Produces:
  - **`shouldPhoneWelcome(s, loaded, phone)`:** `loaded`, `phone` and `tour_seen_at` null.
  - **`PHONE_CARDS: { title: string; text: string }[]`**, exactly:
    1. "Welcome to Kotoba Table review". "You help make the app's Japanese right. Thank you for being here."
    2. "Read it like a teacher". "Each item is a word, a sentence or a grammar point. Check the Japanese, the reading and the English."
    3. "Stamp it or fix it". "Looks right stamps your seal. Suggest a change fixes it in place."
    4. "What happens next". "Another teacher or Martin accepts your change. It reaches the app with the next data release, and the bell tells you."
  - **`PhoneWelcome`:** full-screen cards over Home.
    - **Dots:** one per card, with the current one marked by `aria-current="step"`.
    - **Skip** and **Next**; the last card's button reads **Start reviewing**.
    - Skip and Start reviewing both send `tour: 'done'`.
    - 48 px buttons in a bottom bar.

- [ ] **Step 1: Write the failing tests:**
  - `shouldPhoneWelcome` for new, done and reset.
  - Render `PhoneWelcome`: four dots, the first card's title, Skip and Next.
  - At index 3 (a prop for tests, `start = 0`) it shows "Start reviewing".
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Home picks the welcome by `MediaQuery('max-width: 720px')`: `WelcomeDialog` on desktop, `PhoneWelcome` on phones.
- [ ] **Step 4: Run them.** The full web check. Then the browser at the mobile preset: four cards, Skip ends them, and they're gone after a reload.
- [ ] **Step 5: Commit.** `review-web: phone welcome cards`

### Task 6: Tips

**Files:**
- Create: `review/web/src/lib/Tip.svelte`
- Modify: `review/web/src/routes/inbox/+page.svelte`, `review/web/src/routes/item/+page.svelte`, `review/web/src/lib/settings.test.ts`

**Interfaces:**
- Consumes: `settings.tipOpen(id)` and `settings.change({ dismiss_tip })` (Task 2).
- Produces:
  - **`<Tip id={string}>`** with child text: an `aside` with a light ink border and a **Got it** button. It renders only while `settings.tipOpen(id)`, and Got it dismisses it.
  - **The two tips:**
    - Inbox, above the tabs: "Each suggestion is decided on its own. Edit then accept fixes one before accepting it, and your reply goes to everyone in the thread."
    - Thread (item page, shown when the entry has at least one suggestion): "Reply under a suggestion to talk it through. Its author and everyone who replied are told."

- [ ] **Step 1: Write the failing tests:**
  - Render `Tip` with `settings` loaded and nothing dismissed: the text and Got it render.
  - With `tips_dismissed: ['inbox']`, the inbox tip renders nothing.
  - With `tips_on: false`, nothing renders.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them.** The full web check.
- [ ] **Step 5: Commit.** `review-web: one-time tips on the inbox and threads`

### Task 7: Docs

**Files:**
- Modify: `review/README.md` (Reviewing: Settings, shortcuts, tour and tips; Deploying: migration 0009), the spec's Settings and Onboarding sections (an "As built" note)

- [ ] **Step 1: README.**
  - Settings replaces Account (`/account` redirects).
  - The shortcut list.
  - The tour waits for the first queue.
  - Tips and how to bring the tour back.
  - Deploying: run `0009_user_settings.sql` (`npm run migrate`) just before or right after merging. Until it runs, `/api/settings` fails: shortcuts stay on, and no tour or tips appear. Every other page works.
- [ ] **Step 2: Spec "As built":**
  - Email waits for step 9.
  - The welcome dialog, then the queue tour.
  - `welcome_seen_at` was added beside `tour_seen_at`.
  - Tips for the inbox and threads only.
  - Shortcuts work on the queue page.
- [ ] **Step 3: Check and commit.** `make review-test` and the Clippy runs. Expected: pass. Commit: `docs: settings, shortcuts and onboarding in the review README and the polish spec`
