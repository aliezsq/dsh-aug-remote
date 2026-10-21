#!/usr/bin/env bash
# Rebase this fork onto the newest upstream dsh-zen-remote tag, then rebuild.
#
#   ./scripts/sync-upstream.sh            # newest upstream tag
#   ./scripts/sync-upstream.sh v2.2.7     # a specific tag
#
# The script never pushes anything. If the rebase stops on a conflict (the
# version lines of package.json / the READMEs are the usual ones), resolve it,
# keep THIS fork's version, and continue with `git rebase --continue`.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "add the upstream remote first:" >&2
  echo "  git remote add upstream https://github.com/KyoMio/dsh-zen-remote.git" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is not clean; commit or stash first" >&2
  git status --short >&2
  exit 1
fi

echo "== fetching upstream tags"
git fetch upstream --tags --prune

TAG="${1:-$(git ls-remote --tags --refs upstream 'v*' | sed 's#.*/##' | sort -V | tail -n1)}"
[ -n "$TAG" ] || { echo "could not resolve an upstream tag" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/${TAG#v}" >/dev/null || git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || {
  echo "unknown tag: $TAG" >&2
  exit 1
}

echo "== rebasing main onto $TAG"
git rebase "$TAG"

echo "== install"
pnpm install --prefer-offline

echo "== build"
pnpm build

echo "== verify"
pnpm verify

cat <<'TXT'

done. Next:
  1. bump the fork's version (npm version patch --no-git-tag-version) if the
     rebase changed the version line
  2. pnpm test   (two socket-buffer cases may fail on some hosts even stock)
  3. commit, push main, then tag and push the tag so CI builds the release
TXT
