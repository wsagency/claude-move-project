#!/usr/bin/env bash
#
# release.sh - Cut a clamp release from a clean working tree.
#
# Bumps VERSION in the clamp script, runs the test suite, commits and
# creates an annotated tag. Pushing is left to you so nothing publishes
# by accident. The Release GitHub Action takes over once the tag lands
# on GitHub.
#
# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 1.5.0

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NEW_VERSION="${1:-}"
if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/release.sh <version>   (example: 1.5.0)" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree is not clean, commit or stash first" >&2
    exit 1
fi

if git rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo "Error: tag v$NEW_VERSION already exists" >&2
    exit 1
fi

CURRENT_VERSION=$(grep -m1 '^VERSION=' clamp | cut -d'"' -f2)
echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"

# sed -i needs a suffix argument on macOS (BSD sed)
sed -i.bak "s/^VERSION=\"$CURRENT_VERSION\"/VERSION=\"$NEW_VERSION\"/" clamp
rm -f clamp.bak

if [[ "$(grep -m1 '^VERSION=' clamp | cut -d'"' -f2)" != "$NEW_VERSION" ]]; then
    echo "Error: failed to update VERSION in clamp" >&2
    git checkout -- clamp
    exit 1
fi

echo "Running test suite..."
./test.sh

git add clamp
git commit -m "chore: release v$NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "clamp v$NEW_VERSION"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo
echo "Tagged v$NEW_VERSION. To publish, push the commit and the tag:"
echo
echo "  git push origin $BRANCH v$NEW_VERSION"
echo
echo "The Release workflow will build the artifacts and create the GitHub release."
