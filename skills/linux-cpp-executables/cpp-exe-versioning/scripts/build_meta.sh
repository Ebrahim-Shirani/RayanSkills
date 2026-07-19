#!/usr/bin/env bash
# Print the BUILD component of the version: <commit-count>.g<short-hash>
# Usage: build_meta.sh [repo-dir] [branch]
#   repo-dir  defaults to .
#   branch    defaults to HEAD (pass e.g. 'main' to count the main branch)
set -euo pipefail

REPO="${1:-.}"
REF="${2:-HEAD}"

cd "$REPO"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: $REPO is not a git repository" >&2
    exit 1
fi

COUNT=$(git rev-list --count "$REF")
HASH=$(git rev-parse --short "$REF")

echo "${COUNT}.g${HASH}"
