#!/usr/bin/env bats
# Glue of the publication action: its inputs turned into options, and the pnpm lookup.

setup() {
  DIR="${BATS_TEST_TMPDIR}/action"
  mkdir -p "$DIR" "${BATS_TEST_TMPDIR}/bin"
  cp "${BATS_TEST_DIRNAME}/../publication/run.sh" "$DIR/"
  # stands for publish.sh: one argument per line
  printf '#!/bin/sh\nfor a in "$@"; do echo "[$a]"; done\n' > "${DIR}/publish.sh"
  chmod +x "${DIR}/publish.sh"
  PNPM_VERSION_SH="${BATS_TEST_DIRNAME}/../publication/pnpm-version.sh"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
}

run_action() {
  run env -i PATH="$PATH" PDR_ENTRIES=entries.tsv PDR_BRANCH=release/x PDR_COMMIT_MESSAGE="release: x y" \
    PDR_PR_TITLE="release: x" PDR_PR_LABEL=release PDR_OUT_NAME= PDR_PR_BODY_FILE= PDR_AGENT_VERSION= \
    PDR_AGENT_FILE_URL= PDR_AGENT_MD5= PDR_AGENT_SIZE= PDR_SIDECAR=false PDR_DRY_RUN=false "$@" "${DIR}/run.sh"
}

@test "the required inputs become options, the optional ones are left out" {
  run_action
  [ "$status" -eq 0 ]
  [ "$output" = "[--entries]
[entries.tsv]
[--branch]
[release/x]
[--commit-message]
[release: x y]
[--pr-title]
[release: x]
[--pr-label]
[release]" ]
}

@test "an empty label is passed on as empty, to skip the labelling" {
  run_action PDR_PR_LABEL=
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[--pr-label]\n[]'* ]]
}

@test "the optional inputs are passed when set" {
  run_action PDR_OUT_NAME=26.10.3.yaml PDR_PR_BODY_FILE=body.md PDR_SIDECAR=true PDR_DRY_RUN=true
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[--out-name]\n[26.10.3.yaml]'* ]]
  [[ "$output" == *$'[--pr-body-file]\n[body.md]'* ]]
  [[ "$output" == *"[--sidecar]"* ]]
  [[ "$output" == *"[--dry-run]"* ]]
}

@test "anything but true leaves the dry run and the sidecar off" {
  run_action PDR_SIDECAR=yes PDR_DRY_RUN=1
  [ "$status" -eq 0 ]
  [[ "$output" != *"[--sidecar]"* ]]
  [[ "$output" != *"[--dry-run]"* ]]
}

@test "the four agent inputs are passed together" {
  run_action PDR_AGENT_VERSION=26.10.2 PDR_AGENT_FILE_URL=https://example.invalid/a.exe \
    PDR_AGENT_MD5=0123456789abcdef0123456789abcdef PDR_AGENT_SIZE=5000
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[--agent-version]\n[26.10.2]'* ]]
  [[ "$output" == *$'[--agent-file-url]\n[https://example.invalid/a.exe]'* ]]
  [[ "$output" == *$'[--agent-md5]\n[0123456789abcdef0123456789abcdef]'* ]]
  [[ "$output" == *$'[--agent-size]\n[5000]'* ]]
}

@test "agent details without the version are rejected" {
  run_action PDR_AGENT_MD5=0123456789abcdef0123456789abcdef
  [ "$status" -ne 0 ]
  [[ "$output" == *"need agent_version"* ]]
}

@test "a value with spaces or shell characters stays one argument" {
  run_action PDR_PR_TITLE='release: "a" $(id) ; b'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'[--pr-title]\n[release: "a" $(id) ; b]'* ]]
}

gh_answers() {
  printf '#!/bin/sh\necho "$*" >> "%s/gh.calls"\n%s\n' "$BATS_TEST_TMPDIR" "$1" > "${BATS_TEST_TMPDIR}/bin/gh"
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
}

pnpm_version() {
  run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" GITHUB_OUTPUT="$GITHUB_OUTPUT" GH_TOKEN=placeholder \
    WEBAPP_REPO=test-org/site "$@" "$PNPM_VERSION_SH"
}

@test "the pinned pnpm version is read from the base branch of the site repository" {
  gh_answers 'echo "pnpm@11.2.0+sha512.abc123"'
  pnpm_version WEBAPP_BASE=main
  [ "$status" -eq 0 ]
  grep -qx "version=11.2.0" "$GITHUB_OUTPUT"
  grep -q "repos/test-org/site/contents/package.json?ref=main" "${BATS_TEST_TMPDIR}/gh.calls"
}

@test "the base branch defaults to develop" {
  gh_answers 'echo "pnpm@11.2.0"'
  pnpm_version
  [ "$status" -eq 0 ]
  grep -q "package.json?ref=develop" "${BATS_TEST_TMPDIR}/gh.calls"
}

@test "anything but an exact pnpm version is refused" {
  for answer in "" "npm@10.0.0" "pnpm@11" "pnpm@11.2.0-rc.1" "pnpm@latest"; do
    gh_answers "echo \"${answer}\""
    : > "$GITHUB_OUTPUT"
    pnpm_version
    [ "$status" -ne 0 ]
    [[ "$output" == *"no pnpm packageManager"* ]]
    [ ! -s "$GITHUB_OUTPUT" ]
  done
}

@test "an unreadable site repository is reported" {
  gh_answers 'exit 1'
  pnpm_version
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot read package.json of the site repository"* ]]
}

@test "an empty site repository is rejected before any call" {
  gh_answers 'echo "pnpm@11.2.0"'
  pnpm_version WEBAPP_REPO=
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/gh.calls" ]
}
