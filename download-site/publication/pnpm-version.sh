#!/usr/bin/env bash
# Print the pnpm version the site repository pins in its package.json, as a step
# output. Inputs (env): GH_TOKEN, WEBAPP_REPO, and optionally WEBAPP_BASE.
set -euo pipefail

WEBAPP_REPO="${WEBAPP_REPO:-}"
WEBAPP_BASE="${WEBAPP_BASE:-develop}"

[[ -n "$WEBAPP_REPO" ]] || { echo "::error::the webapp_repo input is empty"; exit 1; }

pm="$(gh api -H 'Accept: application/vnd.github.raw' \
  "repos/${WEBAPP_REPO}/contents/package.json?ref=${WEBAPP_BASE}" --jq '.packageManager // ""')" \
  || { echo "::error::cannot read package.json of the site repository at ${WEBAPP_BASE}: check the token and the repository name"; exit 1; }

# exact X.Y.Z, optional corepack "+<hash>": a prerelease would install another version
if [[ ! "$pm" =~ ^pnpm@([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9A-Za-z.]+)?$ ]]; then
  echo "::error::no pnpm packageManager in the package.json of the site repository at ${WEBAPP_BASE} (got '${pm}')"
  exit 1
fi
echo "version=${BASH_REMATCH[1]}" >> "$GITHUB_OUTPUT"
