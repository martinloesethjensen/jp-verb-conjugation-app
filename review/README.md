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

## Loading data

The site shows the published data, not the repo's working copy. After a data PR merges (and is signed), open
**Reviewers → Published data → Load published data**. The Worker fetches each file from GitHub's main branch,
checks your signature and each file's hash, and refuses a file that is older than the one already loaded. A
refused file keeps its previous version, and the page shows why.

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
