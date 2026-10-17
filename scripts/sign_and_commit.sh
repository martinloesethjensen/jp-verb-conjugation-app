#!/bin/bash
# Signs data/manifest.json, verifies the signature against the key the app trusts, and
# commits data/manifest.sig. Run it on your own machine: the private key never leaves it.
#
#   scripts/sign_and_commit.sh              sign, verify, commit
#   scripts/sign_and_commit.sh --push       ...and push the current branch
#   scripts/sign_and_commit.sh --no-commit  sign and verify only
#
# It stops, changing nothing, if the data is stale (run `make data` first), if any file
# other than data/manifest.sig has uncommitted changes, or if you are on main. The key is
# read from $VERBTABLE_SIGNING_KEY or ~/.config/verbtable/manifest-signing.key.
# See docs/security/data-signing.md.
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python3}"
SIG=data/manifest.sig
commit=1
push=0

fail() { echo "error: $*" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --push) push=1 ;;
        --no-commit) commit=0 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "unknown option '$arg' (try --help)" ;;
    esac
done
[ "$push" = 1 ] && [ "$commit" = 0 ] && fail "--push needs a commit; drop --no-commit"

"$PYTHON" -c "import cryptography" 2>/dev/null \
    || fail "needs the 'cryptography' package: $PYTHON -m pip install -r scripts/requirements.txt"

if [ "$commit" = 1 ]; then
    branch="$(git symbolic-ref --short -q HEAD || true)"
    [ -n "$branch" ] || fail "detached HEAD; check out a branch first"
    case "$branch" in
        main|master) fail "you are on $branch; sign on the pull request's branch instead" ;;
    esac
    others="$(git status --porcelain | grep -v " $SIG\$" || true)"
    [ -z "$others" ] || fail "uncommitted changes besides $SIG; commit or stash them first:
$others"
fi

echo "==> checking the data is up to date"
"$PYTHON" scripts/update_data.py --check \
    || fail "the data is stale or invalid; run 'make data', commit the result, then sign"

# Keep the old signature so a failed run leaves the tree as it found it.
backup="$(mktemp)"
trap 'rm -f "$backup"' EXIT
cp "$SIG" "$backup" 2>/dev/null || : > "$backup"

echo "==> signing"
"$PYTHON" scripts/sign_manifest.py sign

echo "==> verifying"
if ! "$PYTHON" scripts/sign_manifest.py verify; then
    cp "$backup" "$SIG"
    fail "the signature does not verify, so $SIG was put back; is your key the one the app trusts?"
fi

[ "$commit" = 1 ] || { echo "signed and verified; nothing committed"; exit 0; }

if [ -z "$(git status --porcelain -- "$SIG")" ]; then
    echo "$SIG is unchanged; nothing to commit"
else
    git add -- "$SIG"
    git commit -q -m "data: sign manifest" -- "$SIG"
    echo "committed: $(git log --oneline -1)"
fi

if [ "$push" = 1 ]; then
    echo "==> pushing $branch"
    git push -u origin HEAD
fi
