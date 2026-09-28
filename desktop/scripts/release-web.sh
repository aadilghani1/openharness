#!/usr/bin/env bash
# Ship the browser app to harness.autonomous.ai from THIS repo, end to end:
#
#   1. tag this commit vX.Y.Z_web and push it — ../.github/workflows/release-web.yml builds the bundle
#      and publishes the archive, its SHA-256 and harness-web-release.json as a GitHub Release;
#   2. wait for that run, download the manifest;
#   3. open a PR on the website repo pinning apps/web/harness-web-release.json to it, and merge it;
#   4. run the website's OWN scripts/release-web.sh on its main — that tag (its own vA.B.C_web line)
#      builds the website image with the bundle inside, and ArgoCD rolls it out.
#
# The website keeps serving the app (its next.config rewrites `/`, `/s/:id` and `/auth/callback` into
# /harness-web/, and its build verifies the archive's checksum); this script only drives it, so
# nobody has to open the website repo for a web release. Its version line is left to its script.
#
# Usage (from the repo root, `make release-web ARGS=...` runs the same thing):
#   bash desktop/scripts/release-web.sh              # bump the patch of the last v*_web tag and ship
#   bash desktop/scripts/release-web.sh --dry-run    # print the plan, tag/push/merge nothing
#   bash desktop/scripts/release-web.sh --minor      # bump the MINOR version
#   bash desktop/scripts/release-web.sh 0.2.0        # an explicit version
#
# RESUMING: every step skips itself when already done, so after a failure (CI red, PR not mergeable)
# re-run with the SAME explicit version — `bash desktop/scripts/release-web.sh 0.1.5`. An existing tag
# for that version is reused rather than moved.
#
# ⚠️ Step 4 releases the website's whole main, not only the bundle: the script lists any website commits
# since its last release so you can see what else goes live.
#
# Requires: git, gh (signed in, with push access to both repos).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# --- config (all overridable via env) ---
BRANCH="${BRANCH:-main}"
WORKFLOW="${WORKFLOW:-release-web.yml}"
WEBSITE_REPO="${WEBSITE_REPO:-autonomous-ai/autonomous-code}"
WEBSITE_BRANCH="${WEBSITE_BRANCH:-main}"
WEBSITE_MANIFEST="${WEBSITE_MANIFEST:-apps/web/harness-web-release.json}"
RUN_APPEAR_TIMEOUT="${RUN_APPEAR_TIMEOUT:-180}"   # seconds for the tag's workflow run to show up

DRY_RUN=0
DO_MINOR=0
NEW_VER=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --minor) DO_MINOR=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ERROR unknown flag: $arg" >&2; exit 1 ;;
    *) NEW_VER="${arg#v}" ;;
  esac
done

say() { echo ">> $*"; }
die() { echo "ERROR $*" >&2; exit 1; }

# Same rollover as release-desktop.sh: .99 goes to the next MINOR at .1.
next_version() {
  local current="$1" minor_bump="$2"
  [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "version '$current' must look like X.Y.Z"
  local major=$((10#${BASH_REMATCH[1]})) minor=$((10#${BASH_REMATCH[2]})) patch=$((10#${BASH_REMATCH[3]}))
  if [ "$minor_bump" -eq 1 ] || (( patch >= 99 )); then
    printf '%d.%d.1\n' "$major" "$((minor + 1))"
  else
    printf '%d.%d.%d\n' "$major" "$minor" "$((patch + 1))"
  fi
}

# --- preflight ---
for tool in git gh; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found — it is needed to ship the web app"
done
gh auth status >/dev/null 2>&1 || die "gh is not signed in — run: gh auth login"
REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
git fetch --tags --quiet origin

# --- the version: an explicit one (possibly resuming), or a bump of the last v*_web tag ---
LAST_VER="$(git tag -l 'v*_web' \
  | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+_web$' || true; } \
  | sed -E 's/^v//; s/_web$//' | sort -V | tail -1)"
LAST_VER="${LAST_VER:-0.0.0}"
if [ -n "$NEW_VER" ]; then
  VER="$NEW_VER"
else
  VER="$(next_version "$LAST_VER" "$DO_MINOR")"
fi
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version '$VER' must look like X.Y.Z — release-web.yml rejects anything else"
TAG="v${VER}_web"

# An existing tag is a resume: reuse it wherever it points. A new one must capture tested, pushed source.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_EXISTS=1
  SHA="$(git rev-list -n1 "$TAG")"
else
  TAG_EXISTS=0
  [ -z "$(git status --porcelain)" ] || { git status --short >&2; die "working tree is dirty — the tag must capture the tested source exactly"; }
  SHA="$(git rev-parse HEAD)"
  git merge-base --is-ancestor "$SHA" "origin/$BRANCH" 2>/dev/null \
    || die "HEAD is not on origin/$BRANCH — merge and push it first; the web ships from $BRANCH"
  [ "$(printf '%s\n%s\n' "$VER" "$LAST_VER" | sort -V | tail -1)" = "$VER" ] && [ "$VER" != "$LAST_VER" ] \
    || die "$VER is not higher than the last web release $LAST_VER"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SITE="$WORK/site"

say "bundle  : $TAG @ ${SHA:0:8}  $(git log -1 --format=%s "$SHA" | cut -c1-60)$([ "$TAG_EXISTS" -eq 1 ] && echo '  (tag exists — resuming)')"
say "website : $WEBSITE_REPO $WEBSITE_BRANCH → $WEBSITE_MANIFEST"

# --- what else the website release will carry ---
gh repo clone "$WEBSITE_REPO" "$SITE" -- --quiet --filter=blob:none --branch "$WEBSITE_BRANCH" >/dev/null 2>&1 \
  || die "could not clone $WEBSITE_REPO"
SITE_LAST_TAG="$(git -C "$SITE" tag -l 'v*_web' | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+_web$' || true; } | sort -V | tail -1)"
if [ -n "$SITE_LAST_TAG" ]; then
  PENDING="$(git -C "$SITE" log --oneline "$SITE_LAST_TAG..HEAD")"
  if [ -n "$PENDING" ]; then
    say "website commits since $SITE_LAST_TAG that will ALSO go live:"
    echo "$PENDING" | sed 's/^/      /'
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  say "DRY RUN — the website's release script would then cut:"
  (cd "$SITE" && bash scripts/release-web.sh --dry-run) | sed 's/^/      /'
  say "DRY RUN — nothing tagged, pushed or merged."
  exit 0
fi

# --- 1. the bundle tag ---
if [ "$TAG_EXISTS" -eq 0 ]; then
  git tag -a "$TAG" -m "Harness web $VER" "$SHA"
  git push origin "$TAG"
  say "pushed $TAG"
fi

# --- 2. the bundle release: wait for CI unless it is already published ---
if ! gh release view "$TAG" --json assets -q '.assets[].name' 2>/dev/null | grep -qx 'harness-web-release.json'; then
  RUN_ID=""
  for _ in $(seq 1 $((RUN_APPEAR_TIMEOUT / 5))); do
    RUN_ID="$(gh run list --workflow "$WORKFLOW" --limit 20 --json databaseId,headBranch \
      -q ".[] | select(.headBranch == \"$TAG\") | .databaseId" | head -1)"
    [ -n "$RUN_ID" ] && break
    sleep 5
  done
  [ -n "$RUN_ID" ] || die "no $WORKFLOW run appeared for $TAG — check: gh run list --workflow $WORKFLOW"
  say "waiting for the bundle build: https://github.com/$REPO/actions/runs/$RUN_ID"
  gh run watch "$RUN_ID" --exit-status >/dev/null \
    || die "bundle build failed — fix it, delete the tag, and release again: gh run view $RUN_ID --log-failed"
fi
gh release download "$TAG" -p harness-web-release.json -D "$WORK" --clobber
grep -q "\"version\": \"$VER\"" "$WORK/harness-web-release.json" \
  || die "the release's manifest is not for $VER"
say "bundle published: https://github.com/$REPO/releases/tag/$TAG"

# --- 3. pin the website to it (skipped when its main already does) ---
if ! cmp -s "$WORK/harness-web-release.json" "$SITE/$WEBSITE_MANIFEST"; then
  PR_BRANCH="harness-web-$VER"
  PR_STATE="$(gh pr view "$PR_BRANCH" --repo "$WEBSITE_REPO" --json state -q .state 2>/dev/null || true)"
  if [ "$PR_STATE" != "OPEN" ] && [ "$PR_STATE" != "MERGED" ]; then
    git -C "$SITE" checkout -q -B "$PR_BRANCH"
    cp "$WORK/harness-web-release.json" "$SITE/$WEBSITE_MANIFEST"
    git -C "$SITE" add "$WEBSITE_MANIFEST"
    git -C "$SITE" commit -q -m "chore(web): ship Harness web $VER" \
      -m "Pins $WEBSITE_MANIFEST to $REPO@${SHA:0:8} ($TAG)."
    git -C "$SITE" push -q --force-with-lease origin "$PR_BRANCH"
    gh pr create --repo "$WEBSITE_REPO" --base "$WEBSITE_BRANCH" --head "$PR_BRANCH" \
      --title "chore(web): ship Harness web $VER" \
      --body "Pins \`$WEBSITE_MANIFEST\` to [$TAG](https://github.com/$REPO/releases/tag/$TAG) (\`$REPO@${SHA:0:8}\`). Opened by \`make release-web\` in $REPO." >/dev/null
  fi
  if [ "$PR_STATE" != "MERGED" ]; then
    gh pr merge "$PR_BRANCH" --repo "$WEBSITE_REPO" --squash --delete-branch >/dev/null \
      || die "could not merge $(gh pr view "$PR_BRANCH" --repo "$WEBSITE_REPO" --json url -q .url) — merge it, then re-run with $VER"
  fi
  say "website pinned to $VER"
  git -C "$SITE" fetch -q origin "$WEBSITE_BRANCH"
  git -C "$SITE" checkout -q -B "$WEBSITE_BRANCH" "origin/$WEBSITE_BRANCH"
fi
cmp -s "$WORK/harness-web-release.json" "$SITE/$WEBSITE_MANIFEST" \
  || die "$WEBSITE_REPO $WEBSITE_BRANCH does not pin $VER after the merge — someone else changed it; check before releasing"

# --- 4. the website release, by the website's own script (skipped when its last release already pins it) ---
if [ -n "$SITE_LAST_TAG" ] && git -C "$SITE" show "$SITE_LAST_TAG:$WEBSITE_MANIFEST" 2>/dev/null \
  | cmp -s - "$WORK/harness-web-release.json"; then
  say "website $SITE_LAST_TAG already ships $VER — nothing to release"
  exit 0
fi
(cd "$SITE" && bash scripts/release-web.sh)
say "done — once the website build is deployed, https://harness.autonomous.ai/harness-web/release.json reports $VER"
say "watch : gh run list --repo $WEBSITE_REPO --workflow 'Docker production web build' --limit 3"
