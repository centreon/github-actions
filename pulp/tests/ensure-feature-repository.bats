#!/usr/bin/env bats
# Feature repository provisioning, against a curl stand-in for the pulp api
# and the delivery-tooling dispatch.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../package-delivery/ensure-feature-repository.sh"
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  : > "${STUB_DIR}/calls"
  # the repositories exist when REPOSITORIES_EXIST=1, or once a dispatch was sent
  cat > "${STUB_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"
case " $* " in
  *"/dispatches "*)
    echo "dispatch" >> "${STUB_DIR}/calls"
    exit 0
    ;;
esac
count=0
if [[ "${REPOSITORIES_EXIST:-0}" == 1 ]] || grep -qx dispatch "${STUB_DIR}/calls"; then
  count=1
fi
printf '{"count": %s}\n200' "$count"
STUB
  chmod +x "${STUB_DIR}/bin/curl"
}

ensure() {
  run env PATH="${STUB_DIR}/bin:${PATH}" STUB_DIR="$STUB_DIR" PULP_URL=https://pulp.invalid PULP_DOMAIN=standard \
    PULP_TOKEN=placeholder PULP_TOKEN_ISSUED_AT="$(date +%s)" VERSION=25.10 GH_HEAD_REF=MON-1234-feature \
    REPOSITORY_PREFIX=rpm-feature-MON-1234-25.10-el9-unstable "$@" \
    bash -c 'sleep() { :; }; export -f sleep; "$1"' _ "$SCRIPT"
}

@test "existing feature repositories need no token" {
  ensure REPOSITORIES_EXIST=1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exist"* ]]
  [ ! -s "${STUB_DIR}/calls" ]
}

@test "missing feature repositories are requested with the token, then awaited" {
  ensure CENTREON_TECHNIQUE_PAT=placeholder
  [ "$status" -eq 0 ]
  [ "$(grep -cx dispatch "${STUB_DIR}/calls")" -eq 1 ]
  [[ "$output" == *"are ready"* ]]
}

@test "missing feature repositories without a token fail with the reason" {
  ensure
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not exist"*"centreon_technique_pat"* ]]
  [ ! -s "${STUB_DIR}/calls" ]
}

@test "a branch without ticket cannot have a feature repository" {
  ensure GH_HEAD_REF=my-feature REPOSITORIES_EXIST=1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot extract the feature ticket"* ]]
}
