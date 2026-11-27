#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-actions.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${REPO}/tool/run" "${REPO}/tool/lib"
  echo '{"packages": {"tool": {"component": "tool"}}}' > "${REPO}/release-please-config.json"
  echo "# tool" > "${REPO}/tool/README.md"
  printf '#!/bin/sh\n' > "${REPO}/tool/lib/run.sh"
  chmod +x "${REPO}/tool/lib/run.sh"
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

@test "an action of the same package through the self-repository syntax passes" {
  mkdir -p "${REPO}/tool/setup"
  cp "${REPO}/tool/run/action.yml" "${REPO}/tool/setup/action.yml"
  action 'uses: $/tool/setup'
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "a self-repository reference to another package fails" {
  action 'uses: $/other/setup'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"leaves the package 'tool'"* ]]
}

@test "a self-repository reference to a missing action fails" {
  action 'uses: $/tool/missing'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not an action of this repository"* ]]
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

@test "a script that does not exist fails" {
  action 'run: ${{ github.action_path }}/missing.sh'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"script 'missing.sh' does not exist"* ]]
}

@test "a script called through the GITHUB_ACTION_PATH variable is checked too" {
  action 'run: "${GITHUB_ACTION_PATH}/../lib/run.sh"'
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  action 'run: "${GITHUB_ACTION_PATH}/missing.sh"'
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"script 'missing.sh' does not exist"* ]]
}

@test "a script that is not executable fails" {
  chmod -x "${REPO}/tool/lib/run.sh"
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not executable"* ]]
}

@test "a package without README fails" {
  rm "${REPO}/tool/README.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"package 'tool' has no README.md"* ]]
}
