# Kotoba Table review

A small site where a Japanese teacher and native-speaker friends review the app's data. Design:
`docs/superpowers/specs/2026-10-27-data-review-site-design.md`.

| Path | What |
|---|---|
| `api/` | The API: a Rust Cloudflare Worker on `review.martinloeseth.dev/api/*`, with a D1 database |
| `web/` | The pages: SvelteKit, prerendered to static files for Cloudflare Pages on `review.martinloeseth.dev` |

Everyone signs in through Cloudflare Access before reaching either. The Worker checks the Access token on every
request and looks the person up in D1. Nothing here can change `data/`: accepted work reaches the app only
through your normal signed data PRs.

## Working on it

```bash
make review-test     # Worker tests (native), page type checks and tests, build, CSP check
make review-build    # Worker bundle (review/api/build) and pages (review/web/build)
```

For the pages, `npm run dev` in `review/web` serves them with a mock API that reads the repo's own `data/`
(you're signed in as the owner; `MOCK_ROLE=reviewer npm run dev` signs you in as a reviewer, and
`MOCK_LOADED=1` starts with the data already loaded). `npm run build && npm run preview` serves the built site,
with its content security policy, against the same mock.

## Deploying

Both halves deploy themselves when main changes; CI never holds Cloudflare credentials.

- **Pages** (`review/web`) is connected to the repo: Cloudflare builds and deploys pushes that touch
  `review/web/`.
- **Worker** (`review/api`) uses Workers Builds: Cloudflare builds and deploys pushes that touch `review/api/`.
- **Database migrations** are manual. When a PR adds a file under `review/api/migrations/`, run
  `npm run migrate` in `review/api` after it merges.
- **Hash changes reset approvals.** Plan 7 (2026-11-08) made a verb's entry hash include its common phrases,
  so the first data load after that deploy gives every verb entry a new hash. Approvals of verb entries made
  before it stop counting (approve them again), and open or accepted-but-unexported changes to verb entries
  show as stale (export skips them; apply by hand or suggest again). Examples, phrases, counters and grammar
  are unaffected. Before deploying such a change, check D1 for approvals and suggestions on verb entries.

## Loading data

The site shows the published data, not the repo's working copy. After a data PR merges (and is signed), open
**Reviewers → Published data → Load published data**. The Worker fetches each file from GitHub's main branch,
checks your signature and each file's hash, and refuses a file that is older than the one already loaded. A
refused file keeps its previous version, and the page shows why.

Workers Free allows about 10 ms of CPU per request, so a big file loads in several requests: one to begin,
one per slice of about 24 KB (verbs.json takes about 18), and one to finish, which swaps the new data in at
once. Reviewers never see a half-loaded file. Closing the page mid-load leaves the previous version; press
the button again.

Never do these:

- Add a sign-in bypass to the Worker, even for local development. Use the mock.
- Trust an identity header such as `Cf-Access-Authenticated-User-Email`. Only the verified token counts.
- Put a Cloudflare API token, the team domain, the AUD tags or anyone's email in the repo.

## Setting it up (owner, once)

Each step says what to do and what you should see.

1. **D1 database** (done: `kotobatable-review`, its id is in `api/wrangler.toml`). Create the tables:
   `cd review/api && npm install && npm run migrate`. You should see `0001_users_and_audit.sql ✅`.
2. **Sign-in methods.** Zero Trust → Settings → Authentication → Login methods:
   - **One-time PIN**: add it if it isn't there. Reviewers use it.
   - **GitHub**: add it. On GitHub, github.com/settings/developers → **OAuth Apps** → New OAuth App (not a
     GitHub App): homepage `https://review.martinloeseth.dev`, authorization callback URL the one Cloudflare
     shows (`https://<team>.cloudflareaccess.com/cdn-cgi/access/callback`). Generate a client secret and put
     the client ID and secret into Cloudflare only. **Test** should show your GitHub profile.
   - Make sure your GitHub account signs in with a passkey: that's what protects the admin pages.
3. **Access application "Kotoba Table review"**: Zero Trust → Access → Applications → Add → Self-hosted.
   Domain `review.martinloeseth.dev`, no path. Session 24 hours. Login methods: One-time PIN and GitHub.
   Policy "Reviewers": Allow, Include → Emails → your email and each reviewer's. Copy the application's
   **AUD tag** into your password manager as `ACCESS_AUD`.
4. **Access application "Kotoba Table review admin"**: another self-hosted application on the same domain
   with the paths `admin` and `api/admin`. Session 24 hours. Login method: **GitHub only**. Policy "Owner":
   Allow, Include → Emails → the email on your GitHub account, and Require → Login Methods → GitHub. Copy its
   AUD tag as `ACCESS_ADMIN_AUD`. Access uses the most specific path, so `/admin` and `/api/admin/*` get this
   application and everything else gets step 3's. GitHub reports your **primary** email: use that one address
   in both policies and in step 7, or the admin pages say "That account does not have access".
5. **Worker secrets and first deploy**, in `review/api` (later deploys are automatic, see Deploying):
   ```bash
   npx wrangler secret put ACCESS_TEAM_DOMAIN   # yourteam.cloudflareaccess.com
   npx wrangler secret put ACCESS_AUD
   npx wrangler secret put ACCESS_ADMIN_AUD
   npm run deploy
   ```
   In the dashboard, Workers → `kotobatable-review-api` → Settings → Domains & Routes: the route
   `review.martinloeseth.dev/api/*` is there, and `workers.dev` and preview URLs are off.
6. **Pages** (first deploy; later ones are automatic once the project is connected to the repo), in `review/web`: `npm run build`, then
   `npx wrangler pages project create kotobatable-review --production-branch main` (once) and
   `npx wrangler pages deploy build --project-name kotobatable-review`. In the dashboard, add the custom
   domain `review.martinloeseth.dev` to the project, and turn preview deployments off (or put
   `*.kotobatable-review.pages.dev` behind an Access application that allows only you).
7. **Make yourself the admin** (your email is typed here, never committed):
   ```bash
   npx wrangler d1 execute kotobatable-review --remote --command \
     "INSERT INTO users (email, display_name, role, active, created_at) VALUES ('<your email, lowercase>', 'Martin', 'admin', 1, datetime('now'))"
   ```
8. **Smoke test**, in a private window:
   - `https://review.martinloeseth.dev`: sign in with the email PIN, see "Nothing is waiting for you yet."
   - Click **Reviewers**: GitHub sign-in (passkey), then the reviewers list with you in it.
   - `curl -i https://review.martinloeseth.dev/api/me` without a session: a redirect to Access, or 401/403,
     never 200.

## Adding and removing reviewers

- **Add:** put their email in the "Reviewers" policy (step 3), then add them on the Reviewers page. Both are
  needed: Access lets them reach the site, the Reviewers page lets them use it.
- **Remove:** Deactivate them on the Reviewers page, remove them from the policy, and revoke their session
  under Zero Trust → Users. Deactivating takes effect immediately, even before the session ends.

## Reviewing

Reviewers work on any item they open, and on the queues you build for them. On every entry and every part of
one (each example, common phrase, usage, pitfall and thing counted) they can:

- **Looks right**: stamps their red 確認 seal. An approval counts only while the item is unchanged; after you
  load new data that changes it, it shows as "<name> approved an earlier version". Approving a usage or pitfall
  covers the examples inside it, so editing one of those examples also makes it an earlier version.
- **Suggest a change**: a form with only the fields that can change. Ids, and the spellings ids are built from
  (a verb's dictionary form and kanji, a word's class and dictionary form), never change here. Kanji with no
  furigana ask for a reading. Editing a sentence keeps the particle blanks that still line up and drops the
  others; the suggestion says how many to mark again at export.
- **Suggest removing it** (with an optional reason) or **Leave a note for Martin** (for anything the form
  can't change).
- **Not sure, skip** (in a queue only).

Everyone sees everyone's seals and suggestions, by display name. A suggestion made against data that has since
changed shows "Changed since"; one whose item left the data shows "No longer in the data".

**Your inbox** (Reviewers → Suggestions) shows each change as a red-pen correction, grouped by item so
counter-suggestions sit side by side. For each one: **Accept**, **Edit then accept** (fix it before accepting;
this is the only way to accept a change made against older data), **Reply**, or **Decline**. Accepting the
removal of a whole verb or word asks you to confirm, because saved favourites, quiz history and widgets that
point at it are dropped when it is exported. Accepting only marks a suggestion accepted: nothing reaches
`data/` until the export step (plan 6), and then only through your normal signed data PRs.

## Queues

Reviewers → Queues builds a queue from a dataset, the kinds of item, JLPT levels, "Never approved", or pasted
ids (one per line; the preview lists the lines that matched nothing). A queue holds at most 500 items. Each item
can carry your question for reviewers ("Is this natural?"), and you can remove items, rename a queue, or archive
it (it leaves reviewers' home page). Reviewers see every open queue on their home page with their own progress:
an item is done for them once they approved it, suggested something, or skipped it, and an item that left the
data counts as done for everyone.

After the PR that adds the review tables merges, run `npm run migrate` in `review/api` once (migration
`0004_review.sql`), then wait for Workers Builds and Pages to deploy.

## Adding

Reviewers can suggest new items, and you rule on them in the same inbox:

- **New parts:** every list on an item page that can take more ends with a button: "Add an example", "Add a
  common phrase", "Add a thing counted", "Add a usage", "Add a pitfall". The examples under a usage or pitfall
  have their own button. New parts go at the end of their list. "Compared with" examples can't be added.
- **New entries:** each browse page has "Suggest a new verb" (or word, counter, grammar point). Its form asks only
  for what the app can't work out:
  - For a verb, that's its dictionary form, meaning, notes, the nine basic forms (ます, て, plain, and their
    negatives and pasts), and one first example.
  - A word needs its class, dictionary form, meaning and level.
  - A grammar point comes with one usage and one example, because the app needs them.
  - A counter's symbol starts as `number` for you to change.

  The other conjugations, a counter's readings and distractors, and word forms are filled in by `update_data.py`
  when you export.
- **Ids are given when the suggestion is made and kept through export:**
  - A part gets a 6-character stable id.
  - A verb gets its kana, or `kana:kanji` when that kana is already a verb with other kanji. A verb already
    loaded with the same kana and kanji, or a kana-only duplicate, is refused.
  - A word gets `class:dictionary form`.
  - A counter or grammar point gets the id the reviewer types.

  Suggesting an entry someone else already suggested is refused, with a pointer to the earlier suggestion. Sending
  your own pending entry again returns it unchanged; a changed version is refused until you withdraw the first.
- **Links from the inbox:** a new part opens the item page at the part it goes under, and a new entry opens its
  list of suggested additions.
- **In the inbox:** an addition shows the new item itself, marked "New". Edit then accept fills its add form
  from the proposal and keeps its ids. If the place it was added to leaves the data, it shows "No longer in the
  data" and plain Accept is refused. After you export and reload, it shows "Now in the data".

After the PR that adds suggested additions merges, run `npm run migrate` in `review/api` once (migration
`0005_additions.sql`). It rebuilds the suggestions table and keeps everything already stored.

## Exporting

Accepted work reaches the app through an ordinary data PR that you make with `make review-pull`. The site never
writes to the repository: the command reads from the site with a read-only token and does everything else on
your Mac.

**Credits.** Each reviewer is credited by role: "a teacher" or "a native speaker", which you set on the admin
page. A reviewer can choose a public name on their account page; it then appears in stamps and PR summaries
instead of the role. Emails never leave the site.

**Stamps.** On the Export page, "Ready to stamp" lists what can take a stamp now: counters, grammar points,
verbs and words whose every part has a current approval, with nothing open, and verb example sentences with
a current approval of their own. A verb's stamp covers its meaning, notes and common phrases; each example
sentence is stamped on its own, so the list groups a verb's ready examples under it, with "Stamp all". A
stamp names the most senior reviewer who approved (owner, then teacher, then native speaker) and becomes a
`review` stamp in the data at the next pull.

**Setting it up (once):**

1. In Zero Trust, create a service token (Access → Service credentials). Keep its client id and secret.
2. Add a third Access application for the path `review.martinloeseth.dev/api/export` with one policy: action
   Service Auth, include that service token. Copy its AUD tag.
3. Give the Worker two secrets, `ACCESS_EXPORT_AUD` (that AUD tag) and `ACCESS_EXPORT_CLIENT_ID` (the token's
   client id), with `npx wrangler secret put` in `review/api`. Without them, `/api/export` answers 403. After
   deploying, try `make review-pull` once: if it reports a 403, the token's `common_name` isn't the client id
   the Worker expects.
4. Store the token in your Keychain:

   ```bash
   security add-generic-password -s kotobatable-review-export -a client-id -w
   security add-generic-password -s kotobatable-review-export -a client-secret -w
   ```

5. Run `npm run migrate` in `review/api` for migration `0006_export.sql` (credits, stamps, exported marks).

**Each time:**

1. Load the published data on the admin page, so the site's copy matches `main`. If `main` has unreleased data
   changes, run `make data-release` first.
2. In a clean checkout, run `make review-pull`. It starts `review-pull/<date>` from `origin/main`, writes the
   accepted changes, additions, removals, readings and stamps, runs `update_data.py`, commits, and prints a PR
   summary. Anything it couldn't apply is listed under "Skipped". If the site's copy of a file is older than
   `main`, it stops without writing anything.
3. Push the branch and open the PR with the summary. It isn't signed; `make data-release` signs merged batches.
4. After it merges, open Export on the admin page, paste the summary's last line ("Site suggestion ids: …
   Stamp ids: …") and press "Tick these", then "Mark ticked as exported". Only what the pull wrote is marked;
   anything it skipped, or anything accepted since, stays waiting for the next pull.

A change the pull skips as "the data changed since it was accepted" was built against older data: apply it by
hand or have it suggested again. Two accepted changes to different fields of one item both land; if they set
the same field differently, the later one is skipped.

A change to an entry that already had a stamp removes that stamp ("needs a new review"); stamp it again once it
is approved.
