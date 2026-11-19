#!/usr/bin/env bash
# Repository rules for the shared actions. A package is a top-level directory
# released on its own by release-please; it holds one or several actions.
# - every action belongs to a package declared in release-please-config.json,
#   whose component is the directory name (it prefixes the release tags);
# - no local "uses: ./...": it resolves in the caller's workspace, not here;
# - no path leaving the package: a change there would not release it;
# - every remote action is pinned to a full commit SHA with a version comment.
# Usage: check-actions.sh [repository root]
set -euo pipefail

cd "${1:-.}"
CONFIG=release-please-config.json
errors=0

error() {
  echo "::error file=$1::$2"
  errors=$((errors + 1))
}

mapfile -t action_files < <(find . -mindepth 2 -name action.yml -not -path './.*' | sed 's|^\./||' | sort)

for action_file in "${action_files[@]}"; do
  package=${action_file%%/*}
  component=$(jq -r --arg p "$package" '.packages[$p].component // empty' "$CONFIG")
  if [[ "$component" != "$package" ]]; then
    error "$action_file" "package '${package}' must be declared in ${CONFIG} with \"component\": \"${package}\""
  fi

  while IFS= read -r line; do
    number=${line%%:*}
    ref=${line#*uses:}
    ref=${ref#"${ref%%[![:space:]]*}"}
    ref=${ref#[\"\']}
    if [[ "$ref" == ./* ]]; then
      error "$action_file" "line ${number}: local action '${ref}' resolves in the caller's workspace; call a script through github.action_path instead"
    elif [[ ! "$ref" =~ ^[^@[:space:]]+@[0-9a-f]{40}[\"\']?[[:space:]]+#[[:space:]]*v?[0-9]+(\.[0-9]+)*$ ]]; then
      error "$action_file" "line ${number}: '${ref}' must be pinned to a full commit SHA followed by a '# vX.Y.Z' comment"
    fi
  done < <(grep -nE '^[[:space:]-]*uses:' "$action_file" || true)
done

while IFS= read -r package; do
  if [[ -z "$(find "$package" -name action.yml 2> /dev/null)" ]]; then
    error "$CONFIG" "package '${package}' holds no action.yml"
    continue
  fi
  while IFS= read -r file; do
    directory=${file%/*}
    depth=$(awk -F/ '{print NF - 1}' <<< "$directory")
    while IFS= read -r match; do
      ups=$(grep -o '\.\./' <<< "$match" | wc -l)
      if ((ups > depth)); then
        error "$file" "'${match}' leaves the package '${package}'"
      fi
    done < <(grep -oE '(\.\./)+' "$file" | sort -u || true)
  done < <(find "$package" -type f \( -name '*.yml' -o -name '*.sh' \) -not -path '*/tests/*')
done < <(jq -r '.packages | keys[]' "$CONFIG")

if ((errors > 0)); then
  echo "${errors} error(s) found"
  exit 1
fi
echo "${#action_files[@]} action(s) checked: packaged, self-contained and SHA-pinned"
