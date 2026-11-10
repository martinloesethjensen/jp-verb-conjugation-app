# Review site phone layouts (spec step 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the review site work properly on a phone. That means:
- the queue's Items bottom sheet and fixed action bar;
- the suggest form with a live red-pen preview and per-field undo;
- the inbox and browse pages laid out for a phone.

**Architecture:**
- **Shared components:** a `Sheet` (native `<dialog>`, bottom or full screen) and a `FilterChips` row are shared by the queue, inbox and browse.
- **Phone mode:** `ReviewBar` gets a `docked` mode. Below 960 px its actions move into a fixed bottom bar, and its forms open in sheets. The 960 px switch uses Svelte's `MediaQuery` from `svelte/reactivity`.
- **Approving in a queue:** approving no longer jumps to the next item. It presses the seal and offers "Next item" and "Undo", as the spec's Queue row says.
- **API:** unchanged. Change suggestions already accept a `comment` (`review_routes.rs:220`).

**Tech Stack:** SvelteKit 3 / Svelte 5 runes (`MediaQuery` from `svelte/reactivity`), adapter-static, Vitest 5 (node environment, `svelte/server` `render`), TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md`:
- Principles 2, 4, 5 and 6;
- Layout and phone rules › Queue, Wide content, Reduced motion;
- Screens › Queue, Suggest a change, Inbox;
- Build order step 2.

Canvas boards: *Queue · phone*, *Suggest a change · phone*, *Inbox · phone*.

## Global Constraints

- CSP: no `style="…"` attributes, no `style:` directives, no Svelte transitions (`src/csp.test.ts`). Animate with CSS keyframes in `app.css`; the global `prefers-reduced-motion` rule there must keep switching them off.
- Light only. Use the tokens from step 1 (`--paper`, `--card`, `--ink`, `--muted`, `--rule`, `--red`, `--well`, `--radius`, `--radius-input`) and the button classes `.primary`, `.danger`, `.link`, plus `.chip`.
- Touch targets ≥ 44 px, **48 px in phone action bars**. Text ≥ 4.5:1.
- Red only for seals, red-pen corrections, open-suggestion counts and errors.
- Furigana on every kanji, through `Japanese.svelte`.
- The phone breakpoint for the queue is `max-width: 959px`, because the side list starts at 960 px today. Other pages keep `max-width: 720px`.
- No horizontal page scroll at 390 px. Filter and tab rows scroll sideways inside their own box.
- Run from `review/web`. Full check: `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp` (or `make review-test`).
- A parallel PR (`claude/review-web-minors`) touches `app.css` `.chip`, `SiteHeader`, `HomeView`, `ReviewCard`'s entry link, `SuggestionCard` dates and the inbox Open tab label. Start this plan from a `main` that has it merged. If it isn't merged yet, rebase onto it before Task 6.
- Out of scope:
  - the author's public role on suggestion cards ("Kenji · Teacher"): it needs the API, so it goes with roles in step 3;
  - the admin nav links and Inbox count (step 3);
  - the "they disagree" banner and the "Waiting for an opinion" filter (step 6);
  - keyboard shortcuts (step 5).

## Review Focus

1. **Phone keyboard and the fixed bar:** on a phone, the action bar must never cover the last suggestion card or the form being typed in. The card pane gets bottom padding the height of the bar, plus `env(safe-area-inset-bottom)`, and forms open in sheets above the bar. Pinned in Task 4 by a browser check at 390 px: scroll to the bottom, and the last card is fully visible.
2. **Crossing 960 px with a sheet open** (rotating a tablet, resizing a window): the sheet closes and the desktop list or inline form takes over, with nothing stuck open behind a backdrop. Pinned in Task 4 by a browser check, resizing from 390 to 1280 with the More sheet open.
3. **A queue of 500 items in the Items sheet:** the sheet scrolls inside itself, the page behind doesn't scroll, and choosing an item closes the sheet and shows that item. Pinned in Task 2 by a browser check on the 483-item mock queue.
4. **Approve → Undo → approve again:** the seal presses each time, and the bar flips between "Looks right" and "Next item" with no stale state. Pinned in Task 3 by a `ReviewBar` render test for each state, and a browser check of the round trip.
5. **Reduced motion:** the sheet's slide-up is skipped. Pinned in Task 1: the token test asserts that the `sheet-up` keyframes exist and that the global reduced-motion rule is still in `app.css`.

---

### Task 1: `Sheet` and `FilterChips`

**Files:**
- Create: `review/web/src/lib/Sheet.svelte`, `review/web/src/lib/FilterChips.svelte`, `review/web/src/lib/sheet.test.ts`
- Modify: `review/web/src/app.css` (the `sheet-up` keyframes), `review/web/src/tokens.test.ts`

**Interfaces:**
- Produces:
  - `<Sheet open={boolean} title={string} variant={'bottom' | 'full'} onclose={() => void}>{children}</Sheet>`. A native `<dialog class="sheet {variant}" aria-labelledby>` that calls `showModal()` and `close()` from an `$effect` on `open`. The `cancel` event (Esc) and a click on the backdrop call `onclose`. The heading is an `h2` with `title`. The `full` variant also has a header row with a "Cancel" `.link` button that calls `onclose`.
  - `<FilterChips label={string} options={{ value: string; label: string; count?: number }[]} bind:value={string} />`. A `div.filter-chips` with `role="group" aria-label={label}` holding `.chip` buttons with `aria-pressed`. A count renders as `label` + a space + `count`. The row doesn't wrap and scrolls sideways (`overflow-x: auto`).

- [ ] **Step 1: Write the failing tests** in `src/lib/sheet.test.ts`:

```ts
test('a sheet is a labelled dialog with its title', () => {
	const { body } = render(Sheet, { props: { open: false, title: 'Items', variant: 'bottom', onclose: () => {}, children: textSnippet('List') } });
	expect(body).toMatch(/<dialog[^>]*class="sheet bottom[^"]*"[^>]*aria-labelledby="([^"]+)"/);
	expect(body).toContain('>Items</h2>');
});
test('a full-screen sheet has a Cancel button', () => {
	const { body } = render(Sheet, { props: { open: false, title: 'Suggest a change', variant: 'full', onclose: () => {}, children: textSnippet('Form') } });
	expect(body).toMatch(/<button[^>]*class="link[^"]*"[^>]*>Cancel<\/button>/);
});
test('filter chips mark the chosen one and show counts', () => {
	const { body } = render(FilterChips, { props: { label: 'Show', value: 'todo', options: [{ value: 'all', label: 'All' }, { value: 'todo', label: 'To do', count: 22 }] } });
	expect(body).toMatch(/role="group"[^>]*aria-label="Show"/);
	expect(body).toMatch(/aria-pressed="true"[^>]*>To do 22</);
	expect(body).toMatch(/aria-pressed="false"[^>]*>All</);
});
```

`textSnippet` uses `createRawSnippet` from `svelte`. In `tokens.test.ts`, add:

```ts
test('sheets slide up, and reduced motion still switches animations off', () => {
	expect(css).toMatch(/@keyframes sheet-up/);
	expect(css).toMatch(/prefers-reduced-motion: reduce[\s\S]*animation: none !important/);
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/sheet.test.ts src/tokens.test.ts`. Expected: FAIL (the components and keyframes don't exist yet).

- [ ] **Step 3: Implement.**
  - **The bottom variant:**
    - pinned to the bottom, full width, `max-height: 85dvh`;
    - card fill, top corners `--radius`, a 36×4 px grab bar in `--rule`;
    - the content scrolls inside (`overflow-y: auto`), and the backdrop is `rgb(30 38 51 / 0.35)`.
  - **The full variant:** fills the viewport (`100dvh`), with a header row: Cancel on the left, the title centred.
  - **Animation:** `animation: sheet-up 220ms ease-out` with `@keyframes sheet-up { from { transform: translateY(100%) } to { transform: none } }` in `app.css`.
  - **Padding:** `env(safe-area-inset-bottom)` padding on the bottom variant.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib/sheet.test.ts src/tokens.test.ts && npm run check`. Expected: PASS, 0 errors and 0 warnings.

- [ ] **Step 5: Commit**

```bash
git add src/lib/Sheet.svelte src/lib/FilterChips.svelte src/lib/sheet.test.ts src/app.css src/tokens.test.ts
git commit -m "review-web: Sheet and FilterChips for phone layouts"
```

### Task 2: Queue item list and the Items sheet

**Files:**
- Create: `review/web/src/lib/QueueItemList.svelte`, `review/web/src/lib/queue-item-list.test.ts`
- Modify: `review/web/src/routes/queue/+page.svelte` (move the list markup and its styles out; add the Items button and sheet)

**Interfaces:**
- Consumes: `FilterChips`, `Sheet` (Task 1); `filterItems`, `ItemFilter` from `queue-items.ts`.
- Produces: `<QueueItemList items={QueueItem[]} currentKey={string | undefined} bind:filter={ItemFilter} onselect={(item: QueueItem) => void} />`. It holds:
  - the chips All / To do {n} / Done, with the count on To do only, matching the board;
  - the status icons and the empty-filter messages, moved from the queue page unchanged.
- Also produces: `keyOf(item: QueueItem): string` exported from `queue-items.ts`. The format `${dataset}/${kind}/${item_id}` moves there from the page.

- [ ] **Step 1: Write the failing tests:**

```ts
test('the list counts what is left to do and marks the current item', () => {
	const items = [item('a', 'approved'), item('b'), item('c')];
	const { body } = render(QueueItemList, { props: { items, currentKey: keyOf(items[1]), filter: 'all', onselect: () => {} } });
	expect(body).toMatch(/>To do 2</);
	expect(body).toMatch(/class="entry current[^"]*"[^>]*aria-current="true"/);
});
test('an all-done queue says so under To do', () => {
	const { body } = render(QueueItemList, { props: { items: [item('a', 'approved')], currentKey: undefined, filter: 'todo', onselect: () => {} } });
	expect(body).toContain('Nothing left to do in this queue.');
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/queue-item-list.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - **Desktop:** the page renders `QueueItemList` in the side `nav.list` at ≥ 960 px, as today.
  - **Below 960 px:**
    - an "Items" button (outlined pill with a list icon) sits in the header's progress block;
    - it opens `<Sheet title="{total} items" variant="bottom">` holding the same `QueueItemList`;
    - choosing an item sets `selected` and closes the sheet.
  - **Filter:** both lists share one `filter` state.
  - **Crossing the breakpoint:** use `new MediaQuery('max-width: 959px')`. When it stops matching, an `$effect` closes the sheet (Review Focus 2).

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check** (`review-web` preview, mock API; the setup snippet that loads the mock data and creates queues is in Task 8):
  - At 390 px on the 483-item queue: Items opens the sheet, the sheet scrolls inside itself and the page behind doesn't move. Picking an item closes the sheet and shows it.
  - At 1280 px the side list behaves as before.

- [ ] **Step 6: Commit**

```bash
git add src/lib/QueueItemList.svelte src/lib/queue-item-list.test.ts src/lib/queue-items.ts src/routes/queue/+page.svelte
git commit -m "review-web: queue items in a bottom sheet on phones"
```

### Task 3: Approving offers "Next item" and "Undo"

**Files:**
- Modify: `review/web/src/lib/ReviewBar.svelte`, `review/web/src/lib/ReviewCard.svelte`, `review/web/src/routes/queue/+page.svelte`
- Test: `review/web/src/lib/review-bar.test.ts` (new). Move the "Looks right is the primary pill" test here from `queue-items.test.ts`.

**Interfaces:**
- Produces:
  - `ReviewBar` and `ReviewCard` get an optional `onnext?: () => void`.
  - When it is set, approving does **not** call `onaction`.
  - While `approvedByMe` is true, the bar shows a `primary` "Next item" button (calling `onnext`), then "You approved this." and an `Undo` `.link`.
  - Without `onnext` (the item page), the approved state is today's "Approved" + "Undo".
  - Suggesting, skipping and notes still call `onaction` / `onskip` and move on.

- [ ] **Step 1: Write the failing tests.** Use a stub `EntryReview` with `approvedByMe` switchable, as in step 1's stub:

```ts
const stub = (approved: boolean) => ({ approvalsOf: () => [], suggestionsOf: () => [], approvedByMe: () => approved,
	hashOf: () => 'h', isJustApproved: () => false }) as unknown as EntryReview;
const props = { kind: 'example', id: 'x', value: {}, fields: [], readings: {}, forms: {} };
test('in a queue, an approved item offers Next item and Undo', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true), onnext: () => {} } });
	expect(body).toMatch(/class="primary[^"]*"[^>]*>[\s\S]*?Next item/);
	expect(body).toContain('You approved this.');
	expect(body).toMatch(/>Undo</);
	expect(body).not.toContain('Looks right');
});
test('outside a queue, approved stays as it was', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true) } });
	expect(body).toContain('Approved');
	expect(body).not.toContain('Next item');
});
test('before approving, Looks right is the primary pill with a check icon', () => { /* moved from queue-items.test.ts */ });
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/review-bar.test.ts`. Expected: FAIL (there is no `onnext` yet).

- [ ] **Step 3: Implement.** The queue page passes `onnext={next}` through `ReviewCard`. `next()` stays as it is: it clears `selected` and refreshes. The seal's press still keys off `isJustApproved`, which works now that the card stays.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check at 1280 px.**
  - Approve, and the seal presses; "Next item" and "Undo" show.
  - Undo brings "Looks right" back.
  - Approve again, and the seal presses again.
  - "Next item" shows the next undone item.

- [ ] **Step 6: Commit**

```bash
git add src/lib/ReviewBar.svelte src/lib/ReviewCard.svelte src/lib/review-bar.test.ts src/lib/queue-items.test.ts src/routes/queue/+page.svelte
git commit -m "review-web: approving in a queue offers Next item and Undo"
```

### Task 4: The fixed action bar and the More sheet

**Files:**
- Modify: `review/web/src/lib/ReviewBar.svelte`, `review/web/src/lib/ReviewCard.svelte`, `review/web/src/routes/queue/+page.svelte`
- Test: `review/web/src/lib/review-bar.test.ts`

**Interfaces:**
- Consumes: `Sheet` (Task 1); `onnext` (Task 3).
- Produces: `ReviewBar` and `ReviewCard` get an optional `docked?: boolean`. The queue passes `docked`; the item page doesn't. With `docked`, below 960 px (`MediaQuery('max-width: 959px')`):
  - **The bar:** the actions render in `div.action-bar`, `position: fixed` at the bottom, card fill, a top rule, 16 px gutters and `env(safe-area-inset-bottom)` padding.
  - **Before approving:** "Looks right" fills the width (`primary`, 48 px). Below it, "Suggest a change" and "More" share a row (outlined, 48 px).
  - **After approving:** "Next item" fills the width, and below it "You approved this. Undo".
  - **The More sheet:** "More" opens `<Sheet title="More" variant="bottom">` with three full-width rows: "Not sure, skip" (only when `onskip` is set), "Leave a note for Martin" and "Suggest removing it". A Cancel `.link` follows.
  - **The quiet links:** the inline ones are not rendered in the bar.
  - **Forms:** "Suggest a change" opens `SuggestForm` in `<Sheet title="Suggest a change" variant="full">`. The note and removal forms open in a bottom sheet titled "Leave a note for Martin" / "Suggest removing it". Sending closes the sheet and runs `done()` as today.
  - **Desktop:** above 960 px nothing changes; everything is inline, as in Task 3.
  - **Crossing the breakpoint:** an `$effect` closes any open sheet when the query stops matching. The form state (`mode`) carries over to the inline form, so nothing typed is lost.

- [ ] **Step 1: Write the failing tests.** In the node environment `MediaQuery` reads as not matching, so these assert the markup for the docked mode with a `phone` override prop. Add `phone?: boolean`, for tests only, defaulting to the media query:

```ts
test('docked on a phone: Looks right, Suggest a change and More in the action bar', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(false), docked: true, phone: true, fields: [field('en')], onskip: async () => {} } });
	expect(body).toMatch(/class="action-bar[^"]*"[\s\S]*Looks right[\s\S]*Suggest a change[\s\S]*More/);
	expect(body).not.toMatch(/class="link[^"]*"[^>]*>Not sure, skip/);
});
test('docked on a phone after approving: Next item and Undo in the bar', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(true), docked: true, phone: true, onnext: () => {} } });
	expect(body).toMatch(/class="action-bar[^"]*"[\s\S]*Next item[\s\S]*Undo/);
});
test('not docked: no action bar', () => {
	const { body } = render(ReviewBar, { props: { ...props, review: stub(false), phone: true } });
	expect(body).not.toContain('action-bar');
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/review-bar.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.** Below 960 px, the queue page's `.card-pane` gets `padding-bottom: calc(9rem + env(safe-area-inset-bottom))`, so the bar never covers the last card (Review Focus 1).

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check at 390 px.**
  - The bar sits at the bottom. Scroll to the end, and the last suggestion card is fully visible above it.
  - More → Leave a note → send: the note lands and the queue moves on.
  - Suggest a change opens full screen, and Cancel returns to the card.
  - Resize to 1280 with the More sheet open: the sheet closes and the inline actions show.
  - Every bar button measures ≥ 48 px.
  - Take a screenshot.

- [ ] **Step 6: Commit**

```bash
git add src/lib/ReviewBar.svelte src/lib/ReviewCard.svelte src/lib/review-bar.test.ts src/routes/queue/+page.svelte
git commit -m "review-web: fixed action bar and More sheet for the queue on phones"
```

### Task 5: Suggest form with live red pen, per-field undo and a reason

**Files:**
- Modify: `review/web/src/lib/SuggestForm.svelte`, `review/web/src/lib/ReviewBar.svelte` (pass the comment through)
- Test: `review/web/src/lib/suggest-form.test.ts` (new)

**Interfaces:**
- Consumes: `RedPen` (`before`, `after`, `names`).
- Produces:
  - **Signature:** `SuggestForm`'s `onsubmit` becomes `(edits: Record<string, string>, furigana: Record<string, string>, comment: string) => Promise<void>`. Existing callers ignore the third argument.
  - **New prop:** `askWhy?: boolean` (default `false`). When true, an optional textarea labelled "Why? (optional, helps whoever decides)" is shown, and its trimmed value is passed as `comment`.
  - **ReviewBar:** sets `askWhy` and sends `review.suggest(kind, id, 'change', { edits, furigana, comment: comment || undefined })`.
  - **Changed fields:** a field whose value differs from `current` gets the class `changed` (a 1.5 px ink outline). Under it: "Was: {current value}", then a `·` and an `Undo` `.link` that resets that field. An empty current value reads "Was: (empty)".
  - **Send:** the submit button is `disabled` while `edits` is empty, which replaces the "nothing changed" error.
  - **Preview:** under the existing preview, while edits exist, `<RedPen before={current} after={proposed} names={Object.keys(edits)} />` shows the live correction.

- [ ] **Step 1: Write the failing tests:**

```ts
const fields = [{ name: 'en', input: 'text', optional: false, choices: [] }] as Field[];
const base = { fields, readings: {}, forms: {}, onsubmit: async () => {}, oncancel: () => {} };
test('Send is disabled until something differs', () => {
	const { body } = render(SuggestForm, { props: { ...base, current: { en: 'I ate bread.' } } });
	expect(body).toMatch(/<button[^>]*class="primary[^"]*"[^>]*disabled/);
	expect(body).not.toContain('Was:');
});
test('a changed field shows what it was, an undo and the red pen', () => {
	const { body } = render(SuggestForm, { props: { ...base, current: { en: 'I ate bread.' }, initial: { en: 'I used to eat bread.' } } });
	expect(body).toContain('Was: I ate bread.');
	expect(body).toMatch(/class="link[^"]*"[^>]*>Undo</);
	expect(body).toMatch(/<del>/);
	expect(body).not.toMatch(/<button[^>]*class="primary[^"]*"[^>]*disabled/);
});
test('the reason field shows only when asked for', () => {
	expect(render(SuggestForm, { props: { ...base, current: { en: 'x' }, askWhy: true } }).body).toContain('Why? (optional, helps whoever decides)');
	expect(render(SuggestForm, { props: { ...base, current: { en: 'x' } } }).body).not.toContain('Why?');
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/suggest-form.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - **Existing rules stay:** no spelling or id fields, and new kanji still ask for a reading.
  - **Inbox:** the inbox's "Edit then accept" use keeps working. It passes no `askWhy` and ignores `comment`. For it, the comparison base is the current item, and the inputs start from the proposal, so its fields show "Was:" too, which is right for an owner reviewing an edit.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check at 390 px:**
  - Edit the English of a queue example in the full-screen sheet: the field outlines, "Was: …" and Undo appear, and the red pen updates as you type.
  - Undo resets the field and disables Send again.
  - Send with a reason: the reason shows on the new suggestion card.

- [ ] **Step 6: Commit**

```bash
git add src/lib/SuggestForm.svelte src/lib/ReviewBar.svelte src/lib/suggest-form.test.ts
git commit -m "review-web: suggest form with live red pen, per-field undo and a reason"
```

### Task 6: Inbox on a phone

**Files:**
- Create: `review/web/src/lib/InboxGroupHeader.svelte`, `review/web/src/lib/inbox-group-header.test.ts`
- Modify: `review/web/src/routes/inbox/+page.svelte`

**Interfaces:**
- Consumes: `PartView`, `groupTitle`, `DATASET_TITLES`, `suggestionHref`, `InboxSuggestion`.
- Produces: `<InboxGroupHeader first={InboxSuggestion} count={number} {readings} {forms} />`.
  - It moves today's `h2` out of the page: "Example on {entry}" with the entry in Mincho, plus "{dataset} · {n} suggestion(s)" on the right.
  - It then shows the item as it is now, from `first.current`, in a paper well through `PartView`. This matches the board's sentence above the cards.
  - When `first.current` is null (a new entry, or gone), there is no well.

- [ ] **Step 1: Write the failing tests:**

```ts
test('the group header shows the item as it is now, with furigana', () => {
	const first = { ...inboxSuggestion, kind: 'example', current: { id: 'e1', form: 'masu_past', jp: '食べました。', en: 'I ate.' } };
	const { body } = render(InboxGroupHeader, { props: { first, count: 2, readings: { 食: 'た' }, forms: {} } });
	expect(body).toContain('2 suggestions');
	expect(body).toMatch(/class="now[^"]*"[\s\S]*<ruby[^>]*>食<rt>た<\/rt><\/ruby>/);
});
test('no current item: no well', () => {
	const { body } = render(InboxGroupHeader, { props: { first: { ...inboxSuggestion, current: null }, count: 1, readings: {}, forms: {} } });
	expect(body).toContain('1 suggestion');
	expect(body).not.toContain('class="now');
});
```

Build `inboxSuggestion` from the `addition` fixture in `suggestion-card.test.ts`. Move the fixture into `src/lib/fixtures.ts` so both tests share it.

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/inbox-group-header.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - **Tabs:** under 720 px the segmented tabs scroll sideways inside their own box (`overflow-x: auto` on a wrapper).
  - **Spacing:** groups use 16 px padding, and the suggestion cards inside lose their side margin.
  - **Actions:** the Accept / Edit / Decline row keeps its step 1 phone rule, with each taking a third.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check at 390 px** with two suggestions on one item: no horizontal scroll, the well shows the sentence with furigana, and Edit then accept opens the form and works.

- [ ] **Step 6: Commit**

```bash
git add src/lib/InboxGroupHeader.svelte src/lib/inbox-group-header.test.ts src/lib/fixtures.ts src/lib/suggestion-card.test.ts src/routes/inbox/+page.svelte
git commit -m "review-web: inbox groups show the current item; phone spacing"
```

### Task 7: Browse on a phone

**Files:**
- Modify: `review/web/src/lib/BrowseList.svelte`
- Test: `review/web/src/lib/browse-filters.test.ts` (new)

**Interfaces:**
- Consumes: `FilterChips` (Task 1).
- Produces: `browseFilter(items: ItemSummary[], search: string, level: string): ItemSummary[]` in `src/lib/browse.ts`. This moves the `shown` logic out of the component, unchanged: level match, then a case-insensitive search of `title` + `subtitle`.

- [ ] **Step 1: Write the failing tests:**

```ts
test('browseFilter keeps the level and search rules', () => {
	const items = [summary('a', '食べる', 'to eat', 'N5'), summary('b', '飲む', 'to drink', 'N5'), summary('c', '考える', 'to think', 'N4')];
	expect(browseFilter(items, '', 'N5').map((i) => i.item_id)).toEqual(['a', 'b']);
	expect(browseFilter(items, 'DRINK', '').map((i) => i.item_id)).toEqual(['b']);
	expect(browseFilter(items, '', '')).toHaveLength(3);
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/browse-filters.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - **Logic:** `browseFilter`, used by `BrowseList`.
  - **Level filter:** the level `<select>` becomes `<FilterChips label="JLPT level">` with All, N5, N4, N3, N2 and N1. On phones it sits on its own row under the search field, which takes the full width, and scrolls sideways.
  - **Rows:** each row is a 44 px+ link card with the title (`Japanese`), the level pill and the review counts. Under 720 px the subtitle wraps onto its own line.
  - **Header:** "Suggest a new …" becomes an outlined pill link under the title on phones.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check at 390 px** on all four browse pages: no horizontal scroll, the chips scroll sideways and filter, and search works.

- [ ] **Step 6: Commit**

```bash
git add src/lib/BrowseList.svelte src/lib/browse.ts src/lib/browse-filters.test.ts
git commit -m "review-web: browse with level chips and phone rows"
```

### Task 8: Full verification

- [ ] **Step 1: Run the full check.** Run `npm run check && npm test -- --exclude src/csp.test.ts && npm run build && npm run test:csp`. Expected: everything passes, and `test:csp` finds no `style="` and no `unsafe-inline`.

- [ ] **Step 2: Browser pass** with the `review-web` preview at 1280 and 390 px over every page in `csp.test.ts`'s list:
  - nothing scrolls sideways at 390 px;
  - any table or tab row wider than the screen (admin reviewers, export, queue builder) scrolls inside its own box. Wrap it in `div.scroll-x { overflow-x: auto }` where it doesn't already;
  - every button is ≥ 44 px, and the phone action bar's buttons are ≥ 48 px;
  - the console is clean.

  Set up the mock first. In the browser console, `POST /api/admin/snapshot/begin` then `/finish` for each file, then create a verbs-example queue and a words queue through `POST /api/admin/queues`.

  Then on the production build (`review-web-build` preview), check the console: the only CSP errors allowed are SvelteKit's route announcer style (hash `S8qMpvofolR8…`), which is known and hidden by `app.css`.

- [ ] **Step 3: Commit** anything the pass fixed, with a message that says what.
