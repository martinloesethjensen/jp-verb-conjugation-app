# A review site for teachers and native speakers

Status: draft for the owner's approval, 2026-10-27 (all questions answered). The owner's decisions are stated as theirs; everything
marked *my call* is the assistant's and can be overturned.

## Intent

Most of the app's data (verb examples, grammar lessons, counters, words) was written by the assistant and has
not been checked by a native speaker. The owner wants a Japanese teacher and a few native-speaker friends to
review it, correct it and add to it. None of them have GitHub accounts, so today the only route is the owner
copying their remarks into issues by hand (see #179).

The site makes reviewing something these people can do in ten minutes on a phone, and turns their work into
the owner's normal signed data PRs without weakening the data-signing model.

## Goals

- Reviewers sign in, see what the owner has asked them to look at, and can also browse all the data.
- Reviewers can **approve** an item, **suggest a change**, **suggest removing** it, **add** a new item (a verb,
  word, counter, grammar lesson or example sentence: the owner's decision, "it can be all"), and skip what they
  are unsure about.
- The owner has full admin power: accept, decline or reply to suggestions, edit before accepting, set up review
  queues, and export accepted work.
- Accepted work reaches the app only through the owner's existing flow: `data/` change, `update_data.py`,
  `make sign-commit`, PR.
- Approvals become the existing `review` stamps (see "Fits what exists").
- Works well on a phone and a laptop (owner: responsive).

## Non-goals

- Reviewers editing `data/` directly, or anything the site does reaching users without the owner's signature.
- Real-time collaboration, or several reviewers editing one item at once.
- Self-sign-up, public pages, or any reviewer-facing features beyond review (no stats, no gamification).
- Changes to the iOS app in this project, beyond what extending the review stamps needs (see below).
- Android or other clients. Release work of any kind.

## Anti-goals

- The site holding any credential that can change the repo or sign data. A compromise of the site, a
  reviewer's email or Cloudflare must not be able to change what users get.
- Reviewers' names or email addresses ending up in the public repo without their consent.
- A tool that feels like an admin panel or a spreadsheet. Reviewers are friends doing a favour; the bar is "nicer
  than a shared Google Doc".
- Suggestions silently pointing at the wrong sentence after the data changes.

## Constraints

- The repo is public (owner). No secrets in code; secrets only in Cloudflare settings and the owner's Keychain.
- `data/` is Ed25519-signed by the owner (`scripts/sign_manifest.py`, `make sign-commit`); the app rejects
  unsigned data. The site never signs.
- Monorepo: the site lives in this repo (owner's earlier decision); `data/` stays at the root.
- `scripts/update_data.py` owns generated fields (verb forms from `apply_other_forms`, `apply_nd_forms`,
  `apply_potential_forms`, `apply_auxiliary_forms`; word forms; counter `readings`, `changed`, `distractors`)
  and the furigana coverage check. The site only edits authored fields.

## Decided by the owner

- **People:** a teacher and native-speaker friends, none with GitHub. The owner is the only admin.
- **Reviewer powers:** add, approve, suggest a change, suggest deletion. Adding covers all data types.
- **Hosting:** Cloudflare, on the owner's existing domain: `review.martinloeseth.dev`.
- **Frontend:** Svelte. **Backend:** Rust.
- **Responsive:** phone and laptop.
- **Look:** the "teacher's marking desk" direction (below), approved from the mockup.
- **Home screen:** queues the owner set up on top, browse everything below (the owner agreed with option C).

## Architecture

```
reviewer / owner browser
        │  HTTPS, review.martinloeseth.dev
        ▼
Cloudflare Access ── one-time email PIN, allow-list of emails
        │  signed JWT (Cf-Access-Jwt-Assertion)
        ▼
Pages (Svelte, static)          Worker (Rust, workers-rs) at /api/*
                                    │            │
                                    ▼            ▼
                                   D1      raw.githubusercontent.com (public, read-only)
                                                 ▲
owner's Mac: make review-pull ── Access service token ── /api/export (read-only)
        │
        ▼
data/*.json → update_data.py → make sign-commit → PR → main
```

- **Pages + Worker on one hostname** (*my call*): the static Svelte build (SvelteKit with the static adapter) on
  Cloudflare Pages, the Rust Worker routed at `review.martinloeseth.dev/api/*`. One Access application covers
  both; no cross-origin requests.
- **D1** stores users, suggestions, approvals, queues and an append-only audit log.
- **Published data** is read by the Worker from the same public raw GitHub URLs the app uses, at `main`, and the
  Worker verifies the manifest signature and hashes (the public key is public) before using it. *My call*: the
  Worker refreshes its snapshot on demand from an admin button and caches it in D1, keyed by manifest version,
  rather than polling.
- **Code layout** (*my call*): `review/web` (Svelte, TypeScript), `review/api` (Rust), `review/README.md`. A
  `review.yml` workflow builds and tests both, triggered only by `review/**`. Deployment is manual
  (`wrangler deploy` by the owner) at first; *my call*, revisit once it is stable.

## Authentication and authorisation

1. **Access application** for `review.martinloeseth.dev`, policy "allow these emails". Login method: one-time
   PIN by email. Session length 24 hours (*my call*). No passwords anywhere.
2. **The Worker verifies the Access JWT on every request**: RS256 signature against the team's certs endpoint
   (cached, rotation handled), `aud` equals the application's AUD tag, `iss` equals the team domain, `exp` in
   the future. It never trusts a plain email header. Then it looks up the email in D1 `users`; unknown emails get
   403 even if Access let them in.
3. **Roles:** `admin` (the owner's email only) and `reviewer`. Every endpoint declares the role it needs; the
   default is deny.
4. **Owner's stronger sign-in** (owner: GitHub with a passkey): a second Access policy on `/admin*` and
   `/api/admin/*` that allows only the GitHub identity provider and only the owner's GitHub account
   (`martinloesethjensen`). The owner's GitHub account uses a passkey, so admin sign-in is a passkey prompt via
   GitHub. Setup: a GitHub OAuth app for Access (client ID and secret in Cloudflare only). Reviewers keep the email
   PIN and never need GitHub. The Worker also requires the admin role from D1, so passing the policy alone is not
   enough.
5. **Export** uses an Access service token (client ID and secret in the owner's macOS Keychain), allowed only on
   `GET /api/export`; the Worker accepts service-token identity nowhere else. Export is read-only.
6. **Bypasses closed:** the Worker's `workers.dev` route disabled; Pages preview deployments disabled or behind
   Access; state-changing requests require a matching `Origin` header (CSRF); strict CSP, no third-party
   scripts except Google Fonts.
7. **Adding and removing reviewers** happens in the Cloudflare dashboard (Access allow-list) plus a D1 `users`
   row added from the admin page. No Cloudflare API token lives in the Worker. Removing someone: delete from the
   allow-list, delete or disable the row, revoke their session in Zero Trust.
8. **Tests:** forged, expired, wrong-audience and wrong-issuer tokens are rejected; a reviewer gets 403 on every
   admin endpoint; a service token gets 403 everywhere but export.

## Data model

### Stable ids first (a prerequisite data PR)

Example sentences (in verbs, counters and grammar usages) and pitfalls are identified only by their position in
a list today, so a suggestion on "example 3 of 食べる" would point at the wrong sentence after an insert. Before
the site: a data PR gives each of them a short stable `id`, `update_data.py` checks they are present and unique
within their parent, and the app ignores the field. Verbs (`Verb.id`), counters, grammar points and words
already have ids or a unique `dict`. Signed by the owner like any data change.

### D1 tables (*my call* on the details)

- `users(email, display_name, role, active, created_at)`
- `items` snapshot: `(dataset, item_id, parent_id, manifest_version, json)` for every reviewable item at the
  current published version.
- `queues(id, title, description, created_by)` and `queue_items(queue_id, dataset, item_id, note, position)`.
  The note is the owner's question for that item ("would 住むことになりました be more natural?").
- `suggestions(id, kind[add|change|delete], dataset, item_id, parent_id, base_hash, proposed_json, comment,
  author, status[open|accepted|declined|exported], admin_edit_json, created_at, decided_at)`. `base_hash` is the
  item's content hash when the reviewer saw it, so a suggestion against text that has since changed is shown as
  stale instead of being applied blindly.
- `approvals(dataset, item_id, content_hash, reviewer, created_at)`. An approval counts only while
  `content_hash` matches the current item.
- `comments(suggestion_id, author, body, created_at)` for the owner's replies.
- `audit_log(at, actor, action, target, detail)`, insert-only.

### Ids are frozen (*my call*)

Verb `dict` and `kanji` and word `dict` form ids that users' favourites, quiz history, widgets, Spotlight and
deep links store (`2026-10-17-verb-id-scheme-design.md`). The forms lock these fields: a reviewer who thinks one
is wrong leaves a comment, which reaches the owner's inbox as a "needs the owner" suggestion with no automatic
change. Accepting a delete of a whole verb or word shows a warning that saved state pointing at it will be
dropped. Adding new verbs and words is unrestricted.

### Furigana for new kanji (*my call*)

The add and change forms check every kanji run in the new text against the site's `furigana.json` snapshot and
ask the reviewer for the reading of any run it doesn't know (native speakers are the best source). A suggestion
can therefore carry furigana additions alongside its item; the owner sees and can edit them before accepting,
and export writes them to `furigana.json`. The live preview shows ruby from the snapshot plus the entered
readings.

### Validation

The Worker parses every proposed item with strict `serde` types that mirror the JSON shapes in `data/` (unknown
fields rejected) and runs the cheap checks: required fields, JLPT level values, form ids exist in `forms.json`,
the tagged form appears in an example sentence (kana or kanji spelling). Furigana coverage and generated fields
are left to `update_data.py` at export time, which is the source of truth; the export script reports any
failure back to the owner before anything is written.

## Exporting accepted work

`make review-pull` (*my call* on the name), a Python script in `scripts/` so it can reuse `update_data.py`:

1. Fetches accepted, not yet exported suggestions and current approvals from `/api/export`.
2. Applies them to `data/*.json` in a fresh branch, preserving the hand formatting of `grammar.json` the way
   `mark_reviewed.py` does.
3. Writes `review` stamps for approvals (see below).
4. Runs `update_data.py`; on failure, reports which suggestion caused it and stops.
5. Prints a summary for the PR body: each change with its author's display name or role (see open question 2).
6. The owner signs (`make sign-commit`) and opens the PR. After merge, the owner marks the batch exported on
   the site (or the script does it with the next pull, by seeing the new manifest version).

## Fits what exists: review stamps

`docs/superpowers/specs/2026-10-27-review-status-design.md` already gives counters and grammar points a
`review: {by, on, sha256}` stamp, checked by `update_data.py`, and the app shows "Not yet reviewed" or
"Reviewed". The site's approvals export as these stamps. Two gaps, both open questions:

- **Reviewer names:** `REVIEWERS` is `("owner", "teacher")`. Native-speaker friends need a value too.
- **Scope:** stamps exist on counters and grammar points only. Verbs and words have no stamp, and individual
  example sentences have none.

## The site

### Look: a teacher's marking desk (approved from the mockup)

Japanese teachers mark work in red pen (添削) and approve with a seal (確認印). Approving presses a red 確認
seal with the reviewer's name onto the card; a suggested change shows as a red-pen correction, the old text
struck through and the new text written above. The seal is the one bold element; everything else is quiet.

- Colour: paper `#F6F7F4`, card `#FFFFFF`, ink `#1E2633`, muted `#7C8390`, genkō grid `#B9CBB8`, rule
  `#DCE0D8`, red `#C2372B`. Red only where a reviewer has acted.
- Type: Shippori Mincho for Japanese sentences (large, furigana above via `<ruby>` from `furigana.json`), Zen Kaku
  Gothic New for everything else. Sentence case, no all-caps labels.
- One animation: the seal press, which respects reduced motion.
- Mockup: `.superpowers/brainstorm/99169-1793131292/content/marking-desk.html` (not committed).

### Screens

- **Home:** "Waiting for you" queues as small paper stacks with a progress bar (a red segment for items with a
  suggestion), then search and browse by dataset.
- **Review card** (queue mode, one item at a time): what the item is, the sentence on a faint genkō grid, the
  English, the owner's question, then Looks right / Suggest a change, with Not sure, skip and Suggest removing
  it as quieter links.
- **Browse:** lists per dataset, each item showing how much of it is approved; an item page shows every field and
  lets the reviewer act on any part (one example, the meaning, a pitfall).
- **Suggest / add forms:** per-type forms for the authored fields only, with a live preview in the card style.
  For a new verb or word the preview shows what the reviewer entered; generated forms appear only after export
  (*my call*: no conjugation engine in the site).
- **Admin:** suggestions inbox (red-pen view, Accept, Edit then accept, Reply, Decline), queue builder (pick
  items by dataset, JLPT level, "never approved", or paste a list), reviewers list, refresh data, export status.
- **Layout:** one column on phones; on laptops the queue or list on the left and the card on the right.

## Delivery order (*my call*)

1. Data PR: stable ids for examples and pitfalls, pipeline check. Owner signs.
2. Skeleton: `review/` layout, Access set up, Worker with JWT verification and roles, D1 schema and migrations,
   Svelte shell, CI. Auth tests.
3. Read path: snapshot import with signature check, browse and item pages.
4. Review path: queues, approve, suggest change and delete, the admin inbox.
5. Add path: per-type add forms.
6. Export: `make review-pull`, stamps, PR summary.
7. Stamps for verbs, words and examples: pipeline, `mark_reviewed.py`, VerbKit models, app capsule and example
   check. Owner signs the data side.
8. First real use with one reviewer on the #179 and #180 items.

## Left to the builder

Svelte component structure, routing, state management; Rust crate layout and which JWT/crypto crates (must
compile to wasm32; prefer pure Rust or WebCrypto); D1 migration tooling; exact API shapes; test framework
choices; the per-type form fields, derived from the data schemas.

## Questions the owner answered (2026-10-27)

1. ~~Whose approval makes the app say "Reviewed"?~~ Decided (owner, 2026-10-27): part approvals only show
   progress on the site; the owner turns a fully approved entry into a stamp when accepting it, and the stamp
   names the most senior reviewer involved. A reviewer's approval alone never changes the app.
2. ~~How reviewers are named in the public repo~~ Decided (owner): each reviewer's choice. *My call* on the
   shape: every reviewer has a role (`owner`, `teacher`, `native`; `REVIEWERS` gains `native`) and a "public
   name" setting on the site: anonymous (the default; only the role, e.g. "native speaker", is public), a first
   name or anything they like. The stamp keeps
   `by` as the role and gains an optional `name`; PR summaries use the public name or the role. The email never
   leaves D1. Old app builds ignore the new field.
3. ~~Can reviewers see each other's work?~~ Decided (owner): yes, approvals and open suggestions, with names,
   before the owner rules on them. *My call*: on the site everyone sees each other's site display name (a
   private name among the group, separate from the public name, which stays anonymous by default); a reviewer can
   approve an item that has an open suggestion, or add a counter-suggestion, and the owner sees both.
4. ~~Stamp scope~~ Decided (owner): extend stamps to verbs, words and individual example sentences. This
   reverses a non-goal of the review-status design. *My call* on the shape:
   - A verb or word stamp hashes its authored fields only (generated forms excluded, like counters'
     `COUNTER_GENERATED`), and does not cover its examples, so editing one example doesn't un-review the verb.
   - Each example sentence (verbs, counters, grammar usages) can carry its own stamp, keyed by its new stable id.
     A counter or grammar point stamp keeps covering its whole entry, as today.
   - `update_data.py` and `mark_reviewed.py` gain the new targets; the iOS app shows the existing capsule on verb
     and word pages and a small check on a reviewed example, with the same "Show review status" switch. This adds
     an app step to the delivery order (after export works).
5. ~~The owner's stronger admin sign-in~~ Decided (owner): GitHub with a passkey (see Authentication, item 4).

All open questions are answered.
