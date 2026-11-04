#!/bin/bash
# Publishes every data change merged into main since the last release, with one signature.
# Run it on your own machine: the private key never leaves it.
#
#   scripts/data_release.sh            branch, sign, push and open the release pull request
#   scripts/data_release.sh --no-pr    ...but stop after pushing the branch
#
# It makes data-release/<date> from origin/main, regenerates the data in case two merged pull
# requests left it stale (committing that), then signs with scripts/sign_and_commit.sh and opens
# a pull request. Merge it and the apps pick up the whole batch. It stops if main's manifest is
# already signed (nothing to release) or if you have uncommitted changes.
# See docs/security/data-signing.md.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3}"
open_pr=1

fail() { echo "error: $*" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --no-pr) open_pr=0 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "unknown option '$arg' (try --help)" ;;
    esac
done

[ -z "$(git status --porcelain --untracked-files=no)" ] \
    || fail "uncommitted changes; commit or stash them first"
if [ "$open_pr" = 1 ]; then
    command -v gh >/dev/null || fail "needs the GitHub CLI (gh) to open the pull request; or pass --no-pr"
fi

echo "==> fetching origin/main"
git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main

start="$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)"
branch="data-release/$(date +%Y-%m-%d)"
n=2
while git show-ref --quiet "refs/heads/$branch" || git ls-remote --exit-code --heads origin "$branch" >/dev/null; do
    branch="data-release/$(date +%Y-%m-%d)-$n"; n=$((n + 1))
done

git switch -q -c "$branch" origin/main
# Leave the user on a release branch only once something worth keeping is on it.
abandon() { git switch -q "$start" && git branch -q -D "$branch"; }

if "$PYTHON" scripts/sign_manifest.py verify >/dev/null 2>&1 \
        && "$PYTHON" scripts/update_data.py --check >/dev/null 2>&1; then
    abandon
    echo "main's data is already signed and up to date; nothing to release"
    exit 0
fi

echo "==> regenerating"
if ! "$PYTHON" scripts/update_data.py; then
    git checkout -q -- . && abandon
    fail "the data on main is invalid; fix it in a pull request first"
fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    git commit -q -am "data: regenerate for release"
    echo "committed: $(git log --oneline -1)"
fi

# Signs, verifies, commits data/manifest.sig and pushes.
scripts/sign_and_commit.sh --push || { git reset -q --hard origin/main; abandon; exit 1; }

if [ "$open_pr" = 1 ]; then
    echo "==> opening the pull request"
    changes="$(git log --no-merges --format='- %s' "$(git log -1 --format=%H origin/main -- data/manifest.sig)..origin/main" -- data | head -50)"
    gh pr create --base main --head "$branch" --title "data: release $(date +%Y-%m-%d)" --body "Signs the data changes merged since the last release.

${changes:-"- (no data commits found since the last signature)"}

Merge this to publish them: apps only accept a manifest signed by the owner's key."
fi
echo "released on $branch"
