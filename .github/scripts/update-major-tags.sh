#!/usr/bin/env bash
# Point the floating major tag of a package (<package>/vX) at one of its
# releases (<package>/vX.Y.Z).
# - without argument: every package release-please just released, read from
#   RELEASES (JSON outputs of release-please-action);
# - with release tags as arguments: those releases, to roll a major tag back.
# Environment: GITHUB_REPOSITORY, GH_TOKEN.
set -euo pipefail

RELEASE_TAG_PATTERN='^([a-z0-9][a-z0-9-]*)/v([0-9]+)\.[0-9]+\.[0-9]+$'

# print the major tag of a release tag, fail on anything else
major_tag_of() {
  if [[ ! "$1" =~ $RELEASE_TAG_PATTERN ]]; then
    echo "::error::'$1' is not a release tag (<package>/vX.Y.Z)" >&2
    return 1
  fi
  echo "${BASH_REMATCH[1]}/v${BASH_REMATCH[2]}"
}

move_major_tag() {
  local tag=$1 sha=$2 major_tag
  major_tag=$(major_tag_of "$tag")
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::unexpected commit '${sha}' for the release ${tag}"
    return 1
  fi

  if gh api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${major_tag}" > /dev/null 2>&1; then
    gh api -X PATCH "repos/${GITHUB_REPOSITORY}/git/refs/tags/${major_tag}" -f "sha=${sha}" -F force=true > /dev/null
  else
    gh api -X POST "repos/${GITHUB_REPOSITORY}/git/refs" -f "ref=refs/tags/${major_tag}" -f "sha=${sha}" > /dev/null
  fi
  echo "${major_tag} -> ${tag} (${sha})"
  echo "- \`${major_tag}\` now points at \`${tag}\`" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

if (($# > 0)); then
  for tag in "$@"; do
    # validated before it reaches an api path: the tag is typed by a person
    major_tag_of "$tag" > /dev/null
    if ! sha=$(gh api "repos/${GITHUB_REPOSITORY}/commits/tags/${tag}" --jq .sha); then
      echo "::error::release tag '${tag}' does not exist"
      exit 1
    fi
    move_major_tag "$tag" "$sha"
  done
  exit 0
fi

paths=$(jq -r '(.paths_released // "[]") | fromjson | .[]' <<< "$RELEASES")
for path in $paths; do
  tag=$(jq -r --arg key "${path}--tag_name" '.[$key] // empty' <<< "$RELEASES")
  sha=$(jq -r --arg key "${path}--sha" '.[$key] // empty' <<< "$RELEASES")
  move_major_tag "$tag" "$sha"
done
