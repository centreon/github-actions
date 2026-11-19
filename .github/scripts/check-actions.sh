#!/usr/bin/env bash
# Repository rules for the shared actions (every action.yml outside .github):
# - no local "uses: ./...": it resolves in the caller's workspace, not here;
# - every remote action is pinned to a full commit SHA with a version comment.
set -euo pipefail

errors=0

while IFS= read -r -d '' action_file; do
  while IFS= read -r line; do
    number=${line%%:*}
    ref=${line#*uses:}
    ref=${ref#"${ref%%[![:space:]]*}"}
    ref=${ref#[\"\']}
    if [[ "$ref" == ./* ]]; then
      echo "::error file=${action_file},line=${number}::local action '${ref}' resolves in the caller's workspace; call a script through github.action_path instead"
      errors=$((errors + 1))
    elif [[ ! "$ref" =~ ^[^@[:space:]]+@[0-9a-f]{40}[\"\']?[[:space:]]+#[[:space:]]*v?[0-9]+(\.[0-9]+)*$ ]]; then
      echo "::error file=${action_file},line=${number}::'${ref}' must be pinned to a full commit SHA followed by a '# vX.Y.Z' comment"
      errors=$((errors + 1))
    fi
  done < <(grep -nE '^[[:space:]-]*uses:' "$action_file" || true)
done < <(find . -path ./.git -prune -o -path ./.github -prune -o -name action.yml -print0)

if ((errors > 0)); then
  echo "${errors} error(s) found"
  exit 1
fi
echo "All actions are self-contained and SHA-pinned"
