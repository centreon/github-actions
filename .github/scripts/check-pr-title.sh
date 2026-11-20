#!/usr/bin/env bash
# release-please only releases conventional commits, and the pull request
# title becomes the squash commit: reject a title it would silently ignore.
# Usage: check-pr-title.sh "<title>"
set -euo pipefail

TITLE="${1:-}"
TYPES="feat|fix|perf|refactor|revert|docs|test|ci|chore"

if [[ ! "$TITLE" =~ ^(${TYPES})(\([a-z0-9._/-]+\))?!?:\ [^[:space:]] ]]; then
  echo "::error::'${TITLE}' is not a conventional commit title: <type>(<scope>)!: <description>, type one of ${TYPES//|/, }"
  exit 1
fi
echo "Pull request title is a conventional commit title"
