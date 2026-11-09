# Review site visual refresh (spec step 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the review site (`review/web`) in the iOS light paper-and-ink look: new tokens, pill buttons, a new header, Home, Queue and inbox, and fix the failing muted text colour.

**Architecture:** Tokens and the shared control styles live in `src/app.css`. Each page keeps its own scoped `<style>`. New markup goes in small components (`SiteHeader`, `HomeView`) so it can be rendered in tests with `svelte/server`, the same way `suggestion-card.test.ts` does. Pure helpers (`contrast.ts`, `queue-items.ts`) carry the testable rules. The API is unchanged.

**Tech Stack:** SvelteKit 3 / Svelte 5 runes, adapter-static, Vite 8, Vitest 5 (node environment), TypeScript.

**Spec:** `docs/superpowers/specs/2026-11-08-review-site-polish-design.md` (Principles, Tokens, Layout and phone rules › Header and Width, Screens › Home, Queue, Inbox; Build order step 1). Canvas boards: *Home · desktop*, *Home · phone*, *Queue · desktop*, *Inbox · phone*, *Style guide*.

## Global Constraints

- Light only: keep `color-scheme: light`; no dark-mode media queries.
- CSP: no `style="…"` attributes, no `style:` directives, no Svelte transitions (`vite.config.ts` comment; `src/csp.test.ts` checks every built page). Dynamic widths stay SVG attributes, as in `Progress.svelte`.
- Tokens, copied from the spec: `--paper #F6F7F4`, `--card #FFFFFF`, `--ink #1E2633`, `--muted #5F6673`, `--rule #DCE0D8`, `--red #C2372B`, `--red-soft #FBECEB`, `--green #2E6B45`, `--green-soft #E2F0E6`, `--well #ECEEE9`, `--grid #B9CBB8` (genkō lines at 38%).
- Radii: 16 px cards, 12 px wells and inputs, 999 px buttons and pills.
- Red only for seals, red-pen corrections, open-suggestion progress and errors; green only for saved or "live" states.
- Touch targets ≥ 44 px; text ≥ 4.5:1 on paper and card.
- Furigana on every kanji, including decorative labels (`<ruby>添削<rt>てんさく</rt></ruby>`).
- Fonts: Zen Kaku Gothic New for UI, Shippori Mincho for `:lang(ja)`, with `'Hiragino Mincho ProN', serif` and `system-ui, sans-serif` fallbacks. Already loaded in `src/app.html`; don't add other font hosts (CSP `font-src`).
- Out of scope for this plan: the phone queue sheet and action bar (spec step 2), the bell and alerts (step 4), the teacher role (step 3), filter counts from the API.
- Run everything from `review/web`. Full check: `npm run check && npm test && npm run build && npm run test:csp` (or `make review-test` from the repo root).

## Review Focus

1. Long names and titles on a 390 px screen (a 30-character display name, a 60-character queue title) wrap or truncate with no horizontal page scroll. Pinned in Task 2 and Task 3 by a browser check at 390 px.
2. No queues at all: Home still shows the greeting and the "Nothing is waiting for you yet" card. Pinned in Task 3 (`HomeView` empty test).
3. The snapshot fails to load (`files = []`): every Browse card says "Not loaded yet" and nothing throws. Pinned in Task 3.
4. A queue where everything is done: the "To do" filter shows "Nothing left to do in this queue." rather than an empty box. Pinned in Task 5.
5. Fonts blocked or slow: text renders in the fallback stacks; the token test asserts both stacks keep their fallbacks (Task 1).

---

### Task 1: Tokens, base controls and a contrast check

**Files:**
- Modify: `review/web/src/app.css`
- Create: `review/web/src/lib/contrast.ts`
- Create: `review/web/src/tokens.test.ts`

**Interfaces:**
- Produces: `contrastRatio(foreground: string, background: string): number` (WCAG 2 ratio from `#RRGGBB`); CSS variables `--well`, `--radius` (16px), `--radius-input` (12px); classes `.chip` (with `[aria-pressed='true']`), `.segmented` (container with `button[aria-pressed='true']`), `.card`, `.eyebrow` (12 px bold caps), `.quiet`; button classes keep their names (`.primary`, `.danger`, `.link`, `.small`).

- [ ] **Step 1: Write the failing tests** in `src/tokens.test.ts`. Read `src/app.css` with `readFileSync`; small helpers `cssVar(name)` (regex on `--name:\s*([^;]+);`) and `ruleBody(selector)` (the first `selector {…}` block).

```ts
test('contrastRatio follows WCAG', () => {
	expect(contrastRatio('#000000', '#FFFFFF')).toBeCloseTo(21, 5);
	expect(contrastRatio('#7C8390', '#F6F7F4')).toBeLessThan(4.5); // the old muted colour
});
test('tokens match the spec', () => {
	expect(cssVar('muted')).toBe('#5f6673');
	expect(cssVar('well')).toBe('#eceee9');
	expect(cssVar('radius')).toBe('16px');
	expect(cssVar('radius-input')).toBe('12px');
});
test('every text token passes 4.5:1 on paper and card', () => {
	for (const fg of ['ink', 'muted', 'red', 'green'])
		for (const bg of ['paper', 'card'])
			expect(contrastRatio(cssVar(fg), cssVar(bg)), `${fg} on ${bg}`).toBeGreaterThanOrEqual(4.5);
});
test('buttons are pills with 44px targets', () => {
	expect(ruleBody('button')).toMatch(/min-height:\s*44px/);
	expect(ruleBody('button')).toMatch(/border-radius:\s*999px/);
	expect(ruleBody('.chip')).toMatch(/border-radius:\s*999px/);
});
test('font stacks keep their fallbacks', () => {
	expect(cssVar('sans')).toContain('system-ui');
	expect(cssVar('mincho')).toContain('Hiragino Mincho ProN');
});
test('the old muted colour and 6px radius are gone from src', () => {
	// walk src/**/*.{svelte,css,ts} except this file
	for (const [file, text] of sourceFiles()) {
		expect(text.toLowerCase(), file).not.toContain('#7c8390');
		expect(text, file).not.toMatch(/border-radius:\s*6px/);
	}
});
```

Lower-case the values in `cssVar`.

- [ ] **Step 2: Run them to see them fail**

Run: `npx vitest run src/tokens.test.ts`
Expected: FAIL (`contrast.ts` missing; `--muted` is `#7c8390`).

- [ ] **Step 3: Implement `contrastRatio` in `src/lib/contrast.ts`** using WCAG relative luminance (sRGB channel `c ≤ 0.04045 ? c/12.92 : ((c+0.055)/1.055)^2.4`; `(L1+0.05)/(L2+0.05)` with the lighter first).

- [ ] **Step 4: Update `src/app.css`**:
  - **Tokens:** set the values above. `--grid` stays `#b9cbb8`, used at 38% via `color-mix`. Add `--radius-input: 12px` and set `--radius: 16px`.
  - **Base `button`:** `min-height: 44px`, `padding: 0 1.3rem`, `border: 1.5px solid var(--ink)`, `border-radius: 999px`, `font-weight: 500`, `display: inline-flex; align-items: center; justify-content: center; gap: .5rem`.
  - **`.primary`:** ink fill. **`.danger`:** keep.
  - **`.small`:** keeps `min-height: 44px` but uses `padding: 0 1rem; font-size: .9rem`.
  - **`.link`:** `min-height: 44px`, no border, muted, underlined.
  - **Inputs:** `input`, `textarea` and `select` get `min-height: 44px; border-radius: var(--radius-input)`.
  - **Chips:** add `.chip` (min-height 36px, 1px ink border, pill, pressed = ink fill with card text). `.chip` sits inside a list toolbar; the 36 px height is accepted for filter chips, as on the canvas.
  - **Segmented:** add `.segmented` (well background, 4px padding, pill; buttons borderless, pressed = card background with a `0 0 0 1px var(--rule)` shadow and 700 weight).
  - **Shared classes:** add `.card` (card fill, rule border, `--radius`), `.eyebrow` and `.quiet { color: var(--muted) }`.
  - **Type:** headings `h1 { font-size: 2rem; font-weight: 500; line-height: 1.25 }`, and `1.65rem` under `@media (max-width: 720px)`.
  - Then replace every `#7c8390` and `border-radius: 6px` left in `src` with the tokens; most files already use `var(--radius)`.

- [ ] **Step 5: Run the tests to see them pass**

Run: `npx vitest run src/tokens.test.ts && npm run check`
Expected: PASS, and svelte-check reports 0 errors and 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add src/app.css src/lib/contrast.ts src/tokens.test.ts
git commit -m "review-web: paper-and-ink tokens, pill controls, muted contrast fix"
```

### Task 2: Site header

**Files:**
- Create: `review/web/src/lib/SiteHeader.svelte`
- Create: `review/web/src/lib/site-header.test.ts`
- Modify: `review/web/src/routes/+layout.svelte` (replace the `<header class="bar">` block and its styles)

**Interfaces:**
- Consumes: `Me` from `#lib/api.ts`.
- Produces: `<SiteHeader me={Me | null} />`.

- [ ] **Step 1: Write the failing tests** (`render` from `svelte/server`):

```ts
const admin: Me = { email: 'm@x', display_name: 'Martin', role: 'admin', public_role: 'owner', public_name: null };
const reviewer: Me = { ...admin, display_name: 'Aiko', role: 'reviewer', public_role: 'teacher' };
test('the mark has furigana and the name', () => {
	const { body } = render(SiteHeader, { props: { me: null } });
	expect(body).toContain('<ruby>添削<rt>てんさく</rt></ruby>');
	expect(body).toContain('Kotoba Table');
	expect(body).not.toContain('Sign out');
});
test('admins see Reviewers; everyone sees their initial, name and Sign out', () => {
	const a = render(SiteHeader, { props: { me: admin } }).body;
	expect(a).toContain('href="/admin"');
	expect(a).toContain('>M<');
	expect(a).toContain('href="/cdn-cgi/access/logout"');
	const r = render(SiteHeader, { props: { me: reviewer } }).body;
	expect(r).not.toContain('href="/admin"');
	expect(r).toContain('Aiko');
});
test('the phone account menu holds the same links', () => {
	const { body } = render(SiteHeader, { props: { me: admin } });
	expect(body).toMatch(/<details class="account-menu"[\s\S]*href="\/account"[\s\S]*Sign out[\s\S]*<\/details>/);
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/site-header.test.ts`. Expected: FAIL (no component).

- [ ] **Step 3: Implement `SiteHeader.svelte`**:
  - **Bar:** full-width card-coloured bar with a bottom rule, holding a 1120 px max container.
  - **Mark:** the 添削 mark as a rotated (-4deg) red-outlined stamp on `--red-soft`, then "Kotoba Table" in 700 weight and "review" in muted 400.
  - **Desktop links:** a `nav.links` with Reviewers (admins only), an initial circle (ink, 32 px) next to the name linking to `/account`, and Sign out. Keep `data-sveltekit-reload` on these links, as today.
  - **Phone menu:** a `<details class="account-menu">` whose `<summary>` is a 44 px button with the initial circle and `aria-label="Account: {name}"`. Its panel lists "Your name" (`/account`), Reviewers (admins only) and Sign out.
  - **Breakpoint:** at `max-width: 720px` show `.account-menu` and hide `nav.links`; otherwise the reverse.
  - **Long names:** the name truncates with an ellipsis (`max-width: 12rem`).

- [ ] **Step 4: Use it in `+layout.svelte`**: `<SiteHeader {me} />`. Widen `main` to `max-width: 1120px` and set its padding to `3rem 1rem 4.5rem`.

- [ ] **Step 5: Run the tests to see them pass.** Run: `npx vitest run src/lib/site-header.test.ts && npm run check`. Expected: PASS.

- [ ] **Step 6: Browser check.** Start the `review-web` preview (it uses the mock API). At 1280 px the links sit inline. At 390 px, with the mock user's display name set to 30 characters on the account page, the header fits without horizontal scroll and the menu opens with all links. Take a screenshot of each width.

- [ ] **Step 7: Commit**

```bash
git add src/lib/SiteHeader.svelte src/lib/site-header.test.ts src/routes/+layout.svelte
git commit -m "review-web: new header with stamped mark and a phone account menu"
```

### Task 3: Home

**Files:**
- Create: `review/web/src/lib/HomeView.svelte`
- Create: `review/web/src/lib/home-view.test.ts`
- Modify: `review/web/src/routes/+page.svelte` (fetching stays; markup moves to `HomeView`)
- Modify: `review/web/src/lib/QueueStack.svelte`
- Modify: `review/web/src/lib/labels.ts`

**Interfaces:**
- Consumes: `QueueSummary`, `SnapshotFile`, `DATASETS` from `#lib/api.ts`; `QueueStack`.
- Produces: `DATASET_JAPANESE: Record<Dataset, { kanji: string; reading: string }>` with verbs 動詞/どうし, words 単語/たんご, counters 助数詞/じょすうし, grammar 文法/ぶんぽう; `<HomeView name={string} queues={QueueSummary[]} files={SnapshotFile[] | null} next={QueueItem | undefined} readings={Record<string, string>} />` (Task 4 fills in `next` and `readings`; until then pass `undefined` and `{}`); `<QueueStack queue featured={boolean} />`.

- [ ] **Step 1: Write the failing tests**:

```ts
const q = (id: number, done: number, total: number): QueueSummary =>
	({ id, title: `Queue ${id}`, description: '', total, done, with_suggestion: 0, archived: false });
test('greets by name and features the first unfinished queue', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [q(1, 40, 40), q(2, 18, 40)], files: [], next: undefined, readings: {} } });
	expect(body).toContain('Hello, Aiko.');
	expect(body).toMatch(/class="stack featured"[^>]*href="\/queue\?id=2"/);
	expect(body).toContain('Continue reviewing');
});
test('a finished queue carries the seal', () => {
	const { body } = render(QueueStack, { props: { queue: q(1, 40, 40), featured: false } });
	expect(body).toContain('All done, thank you');
	expect(body).toContain('<ruby>確認<rt>かくにん</rt></ruby>');
});
test('no queues: the empty card', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [], files: [], next: undefined, readings: {} } });
	expect(body).toContain('Nothing is waiting for you yet.');
});
test('browse cards have Japanese labels with furigana, and survive a failed snapshot', () => {
	const { body } = render(HomeView, { props: { name: 'Aiko', queues: [], files: [], next: undefined, readings: {} } });
	expect(body).toContain('<ruby>助数詞<rt>じょすうし</rt></ruby>');
	expect(body.match(/Not loaded yet/g)).toHaveLength(4);
});
```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/home-view.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**:
  - **Header:** `HomeView` starts with an eyebrow "Waiting for you", then `h1` "Hello, {name}." and the lead "Martin has {n} queue(s) for you. Pick up where you left off, or browse the data." (singular and plural).
  - **Featured queue:** the first queue with `done < total` renders as `<QueueStack featured>`, a wide card with "Continue" and a fake "Continue reviewing" pill. It is a `span.button-look` inside the link, never a nested button.
  - **Other queues:** the rest go in a grid (`repeat(auto-fill, minmax(280px, 1fr))`, 28 px gap).
  - **Empty state:** the existing card copy.
  - **Browse:** a section titled "Browse the data" with a rule under the heading. Each card has a 64×56 genkō tile with the ruby label, the English title and the version line.
  - **`QueueStack`:** cards get radius 16. A finished queue shows a small rotated 確認 seal (ruby) beside its title. A `featured` queue has a larger 24 px title.
  - **Long titles:** titles wrap; no `white-space: nowrap`.

- [ ] **Step 4: Wire `+page.svelte`** to render `HomeView` with `getSession().me().display_name` (`#lib/session.ts`), and `next={undefined} readings={{}}` for now.

- [ ] **Step 5: Run the tests to see them pass.** Run: `npx vitest run src/lib/home-view.test.ts && npm run check`. Expected: PASS.

- [ ] **Step 6: Browser check** at 1280 and 390 px, with a mock queue titled with 60 characters. Expected: no horizontal scroll, and Browse shows two columns at 390 px (`repeat(auto-fill, minmax(150px, 1fr))` under 720 px). Take a screenshot of each width.

- [ ] **Step 7: Commit**

```bash
git add src/lib/HomeView.svelte src/lib/home-view.test.ts src/lib/QueueStack.svelte src/lib/labels.ts src/routes/+page.svelte
git commit -m "review-web: Home with a Continue card, sealed finished queues and Japanese browse labels"
```

### Task 4: "Next up" on the Continue card

**Files:**
- Create: `review/web/src/lib/queue-items.ts`
- Create: `review/web/src/lib/queue-items.test.ts`
- Modify: `review/web/src/routes/+page.svelte`, `review/web/src/lib/HomeView.svelte`, `review/web/src/routes/queue/+page.svelte` (use the helper)

**Interfaces:**
- Consumes: `getQueue(id: number): Promise<Queue>`, `QueueItem` from `#lib/api.ts`; `loadReference()` from `#lib/reference.ts`; `Japanese.svelte`.
- Produces: `firstUndone(items: QueueItem[]): QueueItem | undefined` (the first item with no `mine` and not `gone`).

- [ ] **Step 1: Write the failing tests**: `firstUndone` skips approved, suggested, skipped and gone items and returns `undefined` when all are done. A `HomeView` test with `next = { ...item, title: '食べる' }` and `readings = { 食: 'た' }` expects `Next up` and the rendered ruby, matched as `/<ruby[^>]*>食<rt>た<\/rt><\/ruby>/` because `Japanese.svelte` writes `<ruby lang="ja">`.

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/queue-items.test.ts src/lib/home-view.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**:
  - **The helper:** add `firstUndone` and use it in the queue page's `current` derivation.
  - **Home:** after the queues load, fetch `getQueue(featured.id)` and `loadReference()` in parallel and pass `next` and `readings` on. If the fetch fails, `next` stays `undefined` and the card shows no preview.
  - **`HomeView`:** shows "Next up" and the title through `<Japanese text={next.title} {readings} />` on a genkō background. The preview is hidden under 720 px to keep the phone card short; the canvas phone board shows it, but a shorter card is the better trade on a phone.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/queue-items.ts src/lib/queue-items.test.ts src/lib/HomeView.svelte src/routes/+page.svelte src/routes/queue/+page.svelte
git commit -m "review-web: show the next item on the Continue card"
```

### Task 5: Queue page

**Files:**
- Modify: `review/web/src/lib/queue-items.ts`, `review/web/src/lib/queue-items.test.ts`
- Modify: `review/web/src/routes/queue/+page.svelte`, `review/web/src/lib/ReviewCard.svelte`, `review/web/src/lib/ReviewBar.svelte`, `review/web/src/lib/Sentence.svelte`, `review/web/src/lib/Progress.svelte`

**Interfaces:**
- Consumes: `firstUndone` (Task 4); `.chip` (Task 1).
- Produces: `type ItemFilter = 'all' | 'todo' | 'done'`; `filterItems(items: QueueItem[], filter: ItemFilter): QueueItem[]` (todo = no `mine` and not `gone`; done = the rest).

- [ ] **Step 1: Write the failing tests**:
  - `filterItems` splits a mixed list correctly.
  - `filterItems(allDone, 'todo')` returns `[]`.
  - Rendering `ReviewBar` for a loaded, unapproved target contains `class="primary"` on "Looks right", plus a check-mark `<svg aria-hidden="true"`.

  `ReviewBar` shows its actions only once `review.hashOf(kind, id)` is defined, so pass a stub instead of a real `EntryReview`:

  ```ts
  const review = { approvalsOf: () => [], suggestionsOf: () => [], approvedByMe: () => false,
  	hashOf: () => 'h', isJustApproved: () => false } as unknown as EntryReview;
  ```

- [ ] **Step 2: Run them to see them fail.** Run: `npx vitest run src/lib/queue-items.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**:
  - **The filter:** add `filterItems`.
  - **Queue header:** back link with a chevron, `h1`, description, and on the right a progress block: "**18** of 40 done" with a red dot and "{n} with suggestions". `Progress` gets an 8 px height and a 4 px radius.
  - **Item list:** in a card. Three `.chip` buttons (All, To do, Done) with `aria-pressed`. Each row shows a status icon: a red rotated-square check for approved, a pencil for suggested, a filled ink dot for current, a hollow muted ring for to do. The current row gets a paper background with a 1.5 px inset ink ring instead of today's left bar. Items render in Mincho. When the filter leaves nothing: "Nothing left to do in this queue."
  - **`ReviewCard`:**
    - **Size:** padding 28/32 and radius 16.
    - **Top line:** "Example on <entry>" on the left, "Open the whole entry ↗" on the right.
    - **Martin's question:** "Martin asks:" sits in a paper well with a speech-bubble icon.
  - **`Sentence`:**
    - **Japanese line:** `.jp` at 2rem (1.6rem under 720 px), line-height 2.5, genkō lines at 38% `--grid`.
    - **Form label:** an outlined ink pill.
  - **`ReviewBar`:**
    - **Looks right:** a `primary` pill with a check icon, no longer `small`.
    - **Suggest a change:** a default pill with a pencil icon.
    - **Quiet actions:** "Not sure, skip", "Suggest removing it" and "Leave a note for Martin" stay `.link`, pushed right by a flex spacer, with a top rule above the action row.
    - **Approved:** keeps the red outline.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Browser check** on `/queue?id=<mock queue>` at 1280 px: approve one item, and the seal presses and the next item comes up. Switch to "Done", then to "To do" on an all-done mock queue: the empty message shows. At 390 px the list is hidden as today and the card has no horizontal scroll. Take screenshots.

- [ ] **Step 6: Commit**

```bash
git add src/lib/queue-items.ts src/lib/queue-items.test.ts src/routes/queue/+page.svelte src/lib/ReviewCard.svelte src/lib/ReviewBar.svelte src/lib/Sentence.svelte src/lib/Progress.svelte
git commit -m "review-web: restyled queue with list filters, status icons and pill actions"
```

### Task 6: Inbox and suggestion cards

**Files:**
- Modify: `review/web/src/routes/admin/inbox/+page.svelte`, `review/web/src/lib/SuggestionCard.svelte`, `review/web/src/lib/RedPen.svelte`
- Test: `review/web/src/lib/suggestion-card.test.ts`

**Interfaces:**
- Consumes: `.segmented`, `.card`, the button classes (Task 1).

- [ ] **Step 1: Write the failing test** in `suggestion-card.test.ts`: a change suggestion renders the author's initial in `class="avatar"`, and its buttons are pills (no `class="small"` on Accept). Also check that the inbox page source wraps its Open / Accepted / Declined tabs in `class="segmented"`: read `src/routes/admin/inbox/+page.svelte` as text.

- [ ] **Step 2: Run it to see it fail.** Run: `npx vitest run src/lib/suggestion-card.test.ts`. Expected: FAIL.

- [ ] **Step 3: Implement**:
  - **Tabs:** the three tabs become a `.segmented` group with `aria-pressed`, and the open count in red.
  - **Groups:** each group header reads "Example on <entry>" in Mincho, with the data set and count on the right.
  - **`SuggestionCard`:**
    - **Card:** radius 16 and padding 18/20.
    - **Author line:** a 28 px initial `avatar`, the name in bold, and the time in muted text.
    - **Comment:** sits in a paper well.
    - **Actions:** Accept (`primary`), Edit and Decline as pills that wrap. On phones each takes a third of the row (`flex: 1` under 720 px).
  - **`RedPen`:** use `--red` as is, with 11 px caps field labels.

- [ ] **Step 4: Run the tests to see them pass.** Run: `npx vitest run src/lib && npm run check`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/routes/admin/inbox/+page.svelte src/lib/SuggestionCard.svelte src/lib/RedPen.svelte src/lib/suggestion-card.test.ts
git commit -m "review-web: inbox with segmented tabs and restyled suggestion cards"
```

### Task 7: Remaining pages and full verification

**Files:**
- Modify: `review/web/src/routes/item/+page.svelte`, `routes/browse/[dataset]/+page.svelte`, `lib/BrowseList.svelte`, `routes/account/+page.svelte`, `routes/add/+page.svelte`, `lib/AddPart.svelte`, `lib/SuggestForm.svelte`, `routes/admin/+page.svelte`, `routes/admin/queues/+page.svelte`, `routes/admin/export/+page.svelte`

**Interfaces:**
- Consumes: everything from Task 1.

- [ ] **Step 1: Sweep each file:**
  - **Cards:** `background: var(--card); border: 1px solid var(--rule); border-radius: var(--radius)`, or the shared `.card` class.
  - **Buttons:** primary actions get `primary`; destructive keeps `danger`; quiet actions keep `link`.
  - **Headings:** page titles use the `h1` scale and section labels use `.eyebrow`.
  - **Muted text:** uses `var(--muted)` and nothing else.
  - **Behaviour:** no other changes.

- [ ] **Step 2: Run the full check**

Run: `npm run check && npm test && npm run build && npm run test:csp`
Expected: everything passes. `test:csp` must still find no `style="` and no `unsafe-inline`.

- [ ] **Step 3: Browser pass** with the `review-web` preview at 1280 and 390 px over every page in `csp.test.ts`'s list:
  - Nothing scrolls sideways at 390 px.
  - Every button is at least 44 px tall (check `getBoundingClientRect` in the console).
  - The console shows no CSP errors.

  Screenshots go in the PR description.

- [ ] **Step 4: Commit**

```bash
git add src/routes src/lib
git commit -m "review-web: restyle item, browse, account, add and admin pages"
```
