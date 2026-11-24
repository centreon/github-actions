#!/usr/bin/env bats
# Guards of the pulp-cli setup that must fail before any token is requested.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../setup-cli/setup.sh"
  # a pulp binary on the PATH skips the installation
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/bin/sh\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/pulp"
  chmod +x "${BATS_TEST_TMPDIR}/bin/pulp"
  export GITHUB_ENV="${BATS_TEST_TMPDIR}/env"
}

setup_cli() {
  run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" GITHUB_ENV="$GITHUB_ENV" "$@" "$SCRIPT"
}

@test "empty audience is rejected" {
  setup_cli AUDIENCE= ACTIONS_ID_TOKEN_REQUEST_URL=https://example.invalid ACTIONS_ID_TOKEN_REQUEST_TOKEN=placeholder
  [ "$status" -ne 0 ]
  [[ "$output" == *"audience input is empty"* ]]
}

@test "missing id-token permission is reported" {
  setup_cli AUDIENCE=pulp
  [ "$status" -ne 0 ]
  [[ "$output" == *"permissions: id-token: write"* ]]
  [ ! -s "$GITHUB_ENV" ]
}
