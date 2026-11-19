#!/usr/bin/env bats
# Repository layout computed for a delivery or a promotion.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../lib/repository-properties.sh"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  : > "$GITHUB_OUTPUT"
}

# run the script with only the given variables, like a composite action step
properties() {
  run env -i PATH="$PATH" GITHUB_OUTPUT="$GITHUB_OUTPUT" "$@" "$SCRIPT"
}

output_of() {
  grep -E "^$1=" "$GITHUB_OUTPUT" | tail -n 1 | cut -d= -f2-
}

@test "rpm stable release: one repository per architecture" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=stable IS_CLOUD=false VERSION=25.10 RELEASE_TYPE=release
  [ "$status" -eq 0 ]
  [ "$(output_of package_extension)" = "rpm" ]
  [ "$(output_of repository_prefix)" = "rpm-25.10-el9-stable" ]
  [ "$(output_of testing_repository_prefix)" = "rpm-25.10-el9-testing-release" ]
  [ "$(output_of stable_base_path_prefix)" = "rpm/25.10/el9/stable" ]
  [ "$(output_of domain)" = "standard" ]
  [ "$(output_of skip_delivery)" = "false" ]
}

@test "promotion env: delivery type, branch and repository family are optional" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=stable IS_CLOUD=false VERSION=25.10 RELEASE_TYPE=hotfix
  [ "$status" -eq 0 ]
  [ "$(output_of testing_repository_prefix)" = "rpm-25.10-el9-testing-hotfix" ]
}

@test "deb testing hotfix: suite and pool carry the version" {
  properties MODULE_NAME=web DISTRIB=bookworm STABILITY=testing IS_CLOUD=false VERSION=25.10 RELEASE_TYPE=hotfix
  [ "$status" -eq 0 ]
  [ "$(output_of package_extension)" = "deb" ]
  [ "$(output_of repository_name)" = "apt-testing-hotfix" ]
  [ "$(output_of suite)" = "bookworm-25.10-testing-hotfix" ]
  [ "$(output_of stable_suite)" = "bookworm-25.10-stable" ]
  [ "$(output_of stable_repository_name)" = "apt-stable" ]
  [ "$(output_of pool_path)" = "pool/25.10/testing/hotfix/web" ]
}

@test "rpm feature delivery: repository named after the branch ticket" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=unstable IS_CLOUD=true VERSION=26.10 \
    DELIVERY_TYPE=feature GH_HEAD_REF=MON-1234-my-feature
  [ "$status" -eq 0 ]
  [ "$(output_of repository_prefix)" = "rpm-feature-MON-1234-26.10-el9-unstable" ]
  [ "$(output_of base_path_prefix)" = "rpm-feature/MON-1234/26.10/el9/unstable" ]
}

@test "deb feature delivery is skipped" {
  properties MODULE_NAME=web DISTRIB=bookworm STABILITY=unstable IS_CLOUD=false VERSION=25.10 DELIVERY_TYPE=feature
  [ "$status" -eq 0 ]
  [ "$(output_of skip_delivery)" = "true" ]
}

@test "connectors: unversioned, plain codename suite, own domain" {
  properties MODULE_NAME=packs DISTRIB=noble STABILITY=unstable IS_CLOUD=false REPOSITORY_TYPE=connectors
  [ "$status" -eq 0 ]
  [ "$(output_of repository_name)" = "ubuntu-unstable" ]
  [ "$(output_of suite)" = "noble" ]
  [ "$(output_of pool_path)" = "pool/unstable/packs" ]
  [ "$(output_of domain)" = "connectors" ]
}

@test "version is mandatory for versioned families" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=stable IS_CLOUD=false
  [ "$status" -ne 0 ]
  [[ "$output" == *"version input is mandatory"* ]]
}

@test "unknown distribution is rejected" {
  properties MODULE_NAME=web DISTRIB=fedora STABILITY=stable IS_CLOUD=false VERSION=25.10
  [ "$status" -ne 0 ]
  [[ "$output" == *"Distrib fedora cannot be parsed"* ]]
}

@test "unknown repository family is rejected" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=stable IS_CLOUD=false VERSION=25.10 REPOSITORY_TYPE=other
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported repository_name"* ]]
}

@test "missing mandatory input is rejected" {
  properties DISTRIB=el9 STABILITY=stable IS_CLOUD=false VERSION=25.10
  [ "$status" -ne 0 ]
  [[ "$output" == *"mandatory inputs are empty"* ]]
}

@test "every output the actions read is produced" {
  properties MODULE_NAME=web DISTRIB=el9 STABILITY=stable IS_CLOUD=false VERSION=25.10 RELEASE_TYPE=release
  [ "$status" -eq 0 ]
  used=$(grep -ohE 'steps\.pulp-properties\.outputs\.[a-z_]+' "${BATS_TEST_DIRNAME}"/../*/action.yml | sed 's/.*\.//' | sort -u)
  for name in $used; do
    grep -qE "^${name}=" "$GITHUB_OUTPUT" || { echo "missing output: ${name}"; return 1; }
  done
}
