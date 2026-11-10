# Review site polish, roles, courses and onboarding — design

Status: design agreed on the canvas, not built. Canvas: https://claude.ai/artifact/NKfDy5o7H7BbneLj9y5kzF
(private; board names in *italics* below).

## Goal

Bring the Kotoba Table review site (`review/web`, `review/api`) up to the iOS app's paper-and-ink look,
make every page work on a phone, and add what reviewers asked for: alerts for replies, a record of what
reached the app, keyboard shortcuts, teacher decisions, second opinions, courses written by
reviewers, a first-run tour, settings and opt-in email.

## Principles

1. **Light only.** The site uses the iOS `light` palette (paper-and-ink spec) and keeps
   `color-scheme: light`. No dark mode, no theme picker.
2. **Red is earned.** `mark` colours seals, red-pen corrections, unread counts, the "new since your last
   visit" line and open-suggestion progress. Nothing decorative is red.
3. **Green means shipped.** `good` marks only "Live in the app" and saved states.
4. **Ink is the one strong colour.** Primary buttons are ink-filled pills; secondary are ink-outlined
   pills; tertiary actions are underlined muted links.
5. **Furigana on every kanji**, in mockups and in the site, through `Japanese.svelte`.
6. **Touch targets ≥ 44 px** (48 px in phone action bars). Text ≥ 4.5:1.
7. **Nothing reaches the app without review**, and only the owner signs data releases
   (`make data-release`).

## Tokens (`review/web/src/app.css`)

| Token | Value | Change |
|---|---|---|
| `--paper` | `#F6F7F4` | — |
| `--card` | `#FFFFFF` | — |
| `--ink` | `#1E2633` | — |
| `--muted` | `#5F6673` | was `#7C8390` (3.6:1 on paper, fails); now 5.4:1, matching iOS |
| `--rule` | `#DCE0D8` | — |
| `--red` (`mark`) | `#C2372B` | — |
| `--red-soft` | `#FBECEB` | — |
| `--green` (`good`) | `#2E6B45` | — |
| `--green-soft` | `#E2F0E6` | — |
| `--well` | `#ECEEE9` | new: segmented-control track, "Start a course" panel |
| `--grid` | `#B9CBB8` at 38% | genkō grid, 1.6em cells |
| `--radius` | 16 px cards, 12 px wells and inputs, 999 px buttons and pills | was 6 px everywhere |

Type: Zen Kaku Gothic New for UI (titles 500 weight, 34 px desktop / 28 px phone; section headings
20–22 px; body 16–17 px; labels 12 px bold caps with 0.12em tracking). Japanese uses Shippori Mincho
with Hiragino Mincho as fallback; furigana at 48%, muted.

Shared pieces to add or restyle in `src/lib` and `app.css`: pill buttons (`.primary`, default,
`.link`), filter chips, segmented control, outlined level and role pills, the 確認 seal (already
`Seal.svelte`), the progress bar (ink done, red open suggestions), `kbd` hints, cards, and the 添削
seal in the header.

## Layout and phone rules

- **Header:** desktop shows the seal, name and nav (Review, Inbox for teachers and the owner, Courses,
  Your contributions), the bell and the account. Phone keeps the seal, a short name, the bell and an
  account button; the nav moves to the account menu (*Home · phone*).
- **Width:** content max 1120–1180 px; 16 px gutter on phones; no horizontal page scroll.
- **Queue:** from 960 px the item list sits beside the card (as today). Below that, the list opens as a
  bottom sheet from an "Items" button, and the actions sit in a fixed bottom bar: "Looks right"
  full width, then "Suggest a change" and "More" (skip, note, suggest removing) (*Queue · phone*).
- **Wide content:** tables and tab rows scroll inside their own box. Filter rows scroll sideways on phones.
- **Reduced motion:** the seal press, card-in and sheet animations are skipped.

## Screens

| Screen | Boards | Behaviour |
|---|---|---|
| Home | *Home · desktop*, *Home · phone* | Greeting, a "Continue" card with the next item on the genkō grid, the other queues as paper stacks (finished ones carry a 確認 seal), then Browse with Japanese labels for each data set. |
| Queue | *Queue · desktop*, *Queue · phone* | As today, restyled. List filters All / To do / Done; status icons for approved, suggested and current. Approving presses the viewer's seal and offers "Next item" and "Undo". |
| Suggest a change | *Suggest a change · phone* | Live red-pen preview of the edit; changed fields get an ink outline with "Was: … · Undo"; Send stays disabled until something differs. Existing rules unchanged (no spelling or id edits; new kanji ask for a reading). |
| Inbox | *Inbox · desktop*, *Inbox · phone* | Grouped by item. Conflicting suggestions sit side by side with a "they disagree" banner; accepting one declines the others. Filters: Open, Waiting for an opinion, Accepted, Declined. |
| Second opinion | *Inbox · desktop* | A teacher or the owner picks another reviewer (one who hasn't seen the item comes first), adds an optional question and asks. The item moves to "Waiting for an opinion"; the person asked gets it under Replies; the authors are told. The asker can cancel. The opinion is advice; a teacher or the owner still decides. |
| Replies | *Replies · desktop*, *Replies page · phone*, *Thread · phone* | See "Reply alerts". |
| Your contributions | *Your contributions · desktop/phone* | Counts (approved, suggested, accepted, live in the app); the viewer's changes grouped by the data release they shipped in, then "next release", waiting and declined (with the reason); the credit shown in the app (`public_name`, `public_role`); counts per data set. |
| Keyboard shortcuts | *Queue · desktop*, *Keyboard shortcuts* | A, S, X (skip), N (note), U (undo approval), J/→ and K/← (move), O (open entry), R (reply), Esc, ⌘Enter (send), ? (help). Off while typing in a field. Removal has no shortcut. Can be switched off in Settings. |
| Onboarding | *First-run tour · desktop*, *Welcome · phone* | See "Onboarding". |
| Settings | *Settings · desktop/phone* | See "Settings". |
| Courses | *Courses*, *Course builder*, *Add to a lesson · phone*, *propose a new grammar point*, *Course review* | See "Courses". |

## Roles

Access roles widen from `admin | reviewer` to `admin | teacher | reviewer` (`users.role`), and later
gain `native` (step 3b). `public_role` (owner, teacher, native) stays a credit label only. Martin sets both.

| Can… | Reviewer | Native (step 3b) | Teacher | Owner (`admin`) |
|---|---|---|---|---|
| Approve items, suggest, note, comment, write courses | yes | yes | yes | yes |
| Accept or decline others' changes to Japanese fields of existing items | no | yes | yes | yes |
| Accept or decline others' other suggestions (English, additions, removals, notes), approve others' courses | no | no | yes | yes |
| Accept own suggestion or approve own course | no | no | no | no |
| Ask for a second opinion | no | no | yes | yes |
| Manage reviewers, roles and queues; export | no | no | no | yes |
| Sign a data release | no | no | no | yes, locally (`make data-release`) |

**Japanese fields** (decided 2026-11-11): a `change` suggestion qualifies only when every edited field is
Japanese text (the Worker's list matching the web's `JAPANESE_FIELDS`: `jp`, `reading`, `kana`, `word`,
`counter`, `wrong`, `kanji`, `dict` and the conjugated forms) and any furigana it adds. A suggestion that
also touches English, a choice field or an id, and every `add`, `delete` and `note`, still needs a teacher
or the owner. A native's "Edit then accept" may only edit the same Japanese fields.

One teacher's acceptance is enough; there is no second check. `suggestions.decided_by` already
records who decided, and the audit log covers every decision.

**As built (step 3, 2026-11-09):** `users.role` gained `teacher` (migration 0007). The inbox and its
decisions left `/api/admin/*`, which only the owner's GitHub sign-in reaches, for `/api/inbox` and
`/api/decide`, open to teachers and the owner through either sign-in; the web inbox moved to `/inbox`. The
owner sets access roles on the Reviewers page (`POST /api/admin/users/access`, teacher or reviewer only; the
owner's own role never changes there). Deciding one's own suggestion is refused for everyone, the owner
included.

## Reply alerts

- **Who is told:** the author of a suggestion or note; anyone who commented in its thread; the author
  when it is accepted or declined; the person asked for a second opinion; the course author on review
  events. Never yourself.
- **Where:** a bell with a red count in the header; on desktop it opens a panel with "Mark all read".
  Home shows a "New replies" section on desktop and a one-line banner on phones; the phone bell opens a
  Replies page with New and Earlier groups.
- **In a thread:** a red "New since your last visit" line sits above unread comments.
- **Data:** a new table `thread_reads(user, suggestion_id, read_at)` and one route that returns unread
  events for the signed-in user. Unread counts come from comments, decisions and requests newer than
  `read_at`. No push, no service worker.

**As built (step 4, 2026-11-10):** events are worked out from `comments` and `suggestions.decided_at` on each
request; only `thread_reads` is stored (migration 0008, which seeds a row for everyone already in a thread so
earlier activity counts as read). Writing a suggestion, comment or decision marks that thread read for its
writer, and a thread card marks itself read when it shows something new. `GET /api/replies` returns the newest
50 events (comments cut to 140 characters) and the unread count; `POST /api/replies/read` takes ids or `all`.
The site checks when it loads and after each navigation. Second-opinion and course events come with steps 6
and 7.

## Onboarding

- **Desktop:** on first sign-in, a welcome dialog, then five highlighted steps on the queue page:
  item list, the sentence, Looks right, Suggest a change, the bell. Back, Next and Skip on each step;
  a closing card points to Settings › Help.
- **Phone:** four full-screen cards (welcome, read it like a teacher, stamp or fix, what happens next)
  with dots and Skip.
- **Tips:** one-time hints the first time someone opens the inbox, courses or a thread.
- **Copy:** says "another teacher or Martin accepts it", never "Martin decides".
- **Data:** `user_settings.tour_seen_at` and `tips_dismissed` (a list of tip ids). "Show the tour
  again" clears `tour_seen_at`, so the tour starts the next time Home opens.

## Settings

A new page (replacing today's Account page) with three sections, saved automatically:

- **Profile:** your name (today's display name); your role with what it allows.
- **Email:** an "Email me" switch, **off by default**. When on: replies to me; accepted or declined;
  second-opinion requests; suggestions waiting for a teacher (teachers only); new queues for me.
  How often: as it happens, daily digest (default when turned on), or weekly digest. Sent to the
  sign-in email. Every email has a one-click unsubscribe.
- **Help:** Show the tour again; Tips on pages; Keyboard shortcuts.

Data: `user_settings(user, email_on, email_kinds, email_frequency, tour_seen_at, tips_on,
tips_dismissed, shortcuts_on)`.

## Courses

Teachers, native speakers and the owner write courses that learners pick in the app, next to Genki I
and II.

- **Start:** from scratch; following a textbook (lesson numbers only, never the book's text or
  examples, the same rule as `taught_in`); or copying a published course. A copy is independent (decided 2026-11-11): it is credited "Copied
  from … by …", but later fixes to the original don't flow into it, and its author decides every change.
- **Builder:** a lesson outline; per lesson a title, a "what learners can do after it" goal, items in
  teaching order and an optional note; "Add from the data" searches by English, kana, kanji or romaji
  and filters by Verbs, Words, Grammar, Counters, Examples.
- **Only reviewed data:** items are stable ids from the published data. A missing word or sentence
  goes through "Suggest adding it". A missing grammar point goes through "Propose a new grammar point",
  which reuses today's add flow for `grammar/entry` and puts the proposal in the lesson as
  "Proposed · waiting for a teacher". A course can't be approved while it holds unaccepted proposals. The author's own proposals need another
  teacher or the owner, even inside their own course (decided 2026-11-11; the own-suggestion guard).
- **Review:** Written → approved by a teacher who isn't the author (or the owner) → in the app with the
  next signed data release. Automatic checks: every lesson has items; every id exists; unreviewed
  counters are flagged; the author confirms nothing is copied from a textbook.
- **Data on the site:** `courses`, `course_lessons`, `course_items(course_id, lesson, position,
  dataset, kind, item_id)`, plus status and reviewer columns like `suggestions`.
- **Published contract:** export writes a new `data/courses.json` with a schema in
  `schema/courses.schema.json` and a spec in `docs/`, signed with the batch like every data file.
  It must stay free of Apple-only assumptions (see AGENTS.md, Android). The app's course picker
  and "start from this course" in My course get their own iOS design; *Course review* only sketches it.

## Email (to investigate before building)

Checked on 8 November 2026 in the Cloudflare docs; Email Sending is in beta, so re-check before building.

- Cloudflare Email Sending can send to any address only on **Workers Paid** ($5/month; 3,000 emails a
  month included, then $0.35 per 1,000). It isn't on Workers Free.
- Free on every plan: sending only to **verified destination addresses** (each reviewer confirms once
  through a Cloudflare email). Workable for a few reviewers.
- The sending domain must use Cloudflare DNS; onboarding adds SPF, DKIM and DMARC records. New accounts
  start with a low daily quota.
- We provide unsubscribe links and add a suppression entry for each opt-out; Cloudflare suppresses bounces and
  complaints itself.

Decide first: is the account that runs the review Worker on Workers Paid? If yes, use the Worker's
`send_email` binding. If not, choose between $5/month and verified addresses. Ship in-site alerts first;
email stays opt-in and off by default.

## Build order

Each step is its own plan and PR.

1. **Visual refresh:** tokens, type, buttons, header, Home, Queue, inbox restyle, the muted fix.
2. **Phone layouts:** queue sheet and action bar, suggest form, inbox, browse.
3. **Roles:** the `teacher` access role, accept and decline for teachers, the own-suggestion guard,
   copy changes.
3b. **Natives accept Japanese fields:** the `native` access role (a migration), the Japanese-field rule in
   `/api/decide`, the Reviewers page picker, and inbox buttons shown only on suggestions a native may decide.
4. **Reply alerts:** `thread_reads`, the unread route, the bell, Home section, thread marker.
5. **Settings and onboarding:** `user_settings`, the Settings page, the tour, the phone welcome, tips,
   keyboard shortcuts and help.
6. **Second opinions** and **Your contributions** (contributions needs export to record which data
   release each accepted suggestion went out in).
7. **Courses on the site:** tables, builder, review, grammar proposals.
8. **Courses in the app:** `data/courses.json`, schema, docs spec, sync, picker. This needs an iOS
   design first.
9. **Email**, after the investigation above.

## Out of scope

- Dark mode, themes and push notifications.
- New example sentences written inside the course builder; they go through suggestions.
- Changing who signs data releases.

## Decided questions (2026-11-11)

- **Natives accept Japanese fields:** yes, for changes to the Japanese text, readings and furigana of
  existing items only; see Roles. Built as step 3b.
- **Copied courses are independent:** credited to the original, but fixes don't flow through.
- **No accepting your own proposals in your own course:** another teacher or the owner decides.

## Open questions

- Email: Workers Paid ($5/month, any address) or the free verified-addresses route? See Email.
