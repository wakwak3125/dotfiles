#!/usr/bin/env bash
# Claude Code WorktreeCreate hook.
# Places worktrees at <parent-of-repo>/worktree/<repo-name>/<name>
# to match the user's `wt` shell function layout.

set -euo pipefail

INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.name')
CWD=$(echo "$INPUT" | jq -r '.cwd')

if [[ -z "$NAME" || "$NAME" == "null" || -z "$CWD" || "$CWD" == "null" ]]; then
  echo "worktree-create: missing name or cwd" >&2
  exit 1
fi

GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel)
REPO_PARENT=$(dirname "$GIT_ROOT")
REPO_NAME=$(basename "$GIT_ROOT")
DIR="$REPO_PARENT/worktree/$REPO_NAME/$NAME"
BRANCH="worktree-$NAME"

BASE=$(git -C "$GIT_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [[ -z "$BASE" ]]; then
  BASE=$(git -C "$GIT_ROOT" rev-parse --abbrev-ref HEAD)
fi

mkdir -p "$(dirname "$DIR")"
git -C "$GIT_ROOT" worktree add -b "$BRANCH" "$DIR" "$BASE" >&2

echo "$DIR"
