#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-actions.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}/tool/run" "${REPO}/tool/lib"
  echo '{"packages": {"tool": {"component": "tool"}}}' > "${REPO}/release-please-config.json"
  action 'uses: actions/cache@27d5ce7f107fe9357f9df03efb73ab90386fccae # v5.0.5' \
    'run: ${{ github.action_path }}/../lib/run.sh'
}

# write tool/run/action.yml with the given step lines
action() {
  {
    printf 'runs:\n  using: composite\n  steps:\n'
    printf '    - %s\n' "$@"
  } > "${REPO}/tool/run/action.yml"
}

@test "a packaged, self-contained, pinned action passes" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "an action outside any declared package fails" {
  mkdir -p "${REPO}/other"
  cp "${REPO}/tool/run/action.yml" "${REPO}/other/action.yml"
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"package 'other' must be declared"* ]]
}

@test "a component that differs from the directory fails" {
  echo '{"packages": {"tool": {"component": "tools"}}}' > "${REPO}/release-please-config.json"
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
}

@test "a local uses fails" {
  action 'uses: ./.github/actions/foo'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolves in the caller's workspace"* ]]
}

@test "a tag-pinned action fails" {
  action 'uses: actions/checkout@v4'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be pinned to a full commit SHA"* ]]
}

@test "a path leaving the package fails" {
  action 'run: ${{ github.action_path }}/../../shared/run.sh'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"leaves the package 'tool'"* ]]
}

@test "a declared package without action fails" {
  echo '{"packages": {"tool": {"component": "tool"}, "ghost": {"component": "ghost"}}}' > "${REPO}/release-please-config.json"
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"package 'ghost' holds no action.yml"* ]]
}
