#!/usr/bin/env bats
# Presence check of the deb verification, against stand-ins for curl and pulp.

SHAS=(
  1111111111111111111111111111111111111111111111111111111111111111
  2222222222222222222222222222222222222222222222222222222222222222
  3333333333333333333333333333333333333333333333333333333333333333
)

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../lib/check-deb.sh"
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  : > "${STUB_DIR}/calls"
  : > "${STUB_DIR}/batch_shas"
  : > "${STUB_DIR}/lookup_shas"

  # pulp stand-in: every repository exists and has a latest version
  cat > "${STUB_DIR}/bin/pulp" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"repository show"* ]]; then
  echo '{"latest_version_href": "/pulp/plugins/api/v3/repositories/deb/apt/1/versions/5/"}'
fi
STUB

  # curl stand-in: answers by url, and logs the api lookups it serves
  cat > "${STUB_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *pulp_label_select=*)
    echo "batch" >> "${STUB_DIR}/calls"
    [[ "${BATCH_FAILS:-0}" == 1 ]] && exit 22
    jq -Rn '{count: 0, next: null, results: [inputs | {sha256: .}]}' < "${STUB_DIR}/batch_shas"
    ;;
  *content/deb/packages/*sha256=*)
    echo "lookup" >> "${STUB_DIR}/calls"
    sha=${url##*sha256=}
    sha=${sha%%&*}
    if grep -qx "$sha" "${STUB_DIR}/lookup_shas"; then echo '{"count": 1}'; else echo '{"count": 0}'; fi
    ;;
  */Release) echo "Architectures: amd64" ;;
  */Packages) cat "${STUB_DIR}/Packages" ;;
  *)
    if [[ " $* " == *" -I "* ]]; then
      echo "head" >> "${STUB_DIR}/calls"
      [[ -n "${UNFETCHABLE:-}" && "$url" == *"${UNFETCHABLE}"* ]] && exit 22
      printf '200 %s' "$url"
    fi
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/bin/pulp" "${STUB_DIR}/bin/curl"

  # manifest and published index of three delivered packages
  local entries=() i
  : > "${STUB_DIR}/Packages"
  for i in 0 1 2; do
    entries+=("$(jq -cn --arg f "pkg${i}_1.0_all.deb" --arg s "${SHAS[$i]}" \
      '{filename: $f, arch: "all", sha256: $s, repository: "apt-unstable", base_path: "apt-plugins-unstable", suite: "bookworm"}')")
    printf 'Package: pkg%s\nFilename: pool/main/p/pkg%s/pkg%s_1.0_all.deb\nSHA256: %s\n\n' "$i" "$i" "$i" "${SHAS[$i]}" >> "${STUB_DIR}/Packages"
  done
  printf '%s\n' "${entries[@]}" | jq -s '{packages: .}' > "${STUB_DIR}/manifest.json"
}

check_deb() {
  run env PATH="${STUB_DIR}/bin:${PATH}" STUB_DIR="$STUB_DIR" \
    MANIFEST="${STUB_DIR}/manifest.json" MODULE_NAME=plugins DISTRIB=bookworm STABILITY=unstable \
    PULP_URL=https://pulp.invalid PULP_CONTENT_URL=https://content.invalid PULP_DOMAIN=plugins \
    PULP_TOKEN=placeholder PULP_TOKEN_ISSUED_AT="$(date +%s)" \
    METADATA_TIMEOUT=1 METADATA_INTERVAL=1 GITHUB_STEP_SUMMARY="${STUB_DIR}/summary" \
    "$@" "$SCRIPT"
}

calls() {
  grep -cx "$1" "${STUB_DIR}/calls" || true
}

@test "delivery: one listing answers for every package of the run" {
  printf '%s\n' "${SHAS[@]}" > "${STUB_DIR}/batch_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42
  [ "$status" -eq 0 ]
  [ "$(calls batch)" -eq 1 ]
  [ "$(calls lookup)" -eq 0 ]
  [[ "$output" == *"All 3 package(s) verified"* ]]
}

@test "delivery: a package the listing misses gets its own lookup" {
  printf '%s\n' "${SHAS[0]}" "${SHAS[1]}" > "${STUB_DIR}/batch_shas"
  echo "${SHAS[2]}" > "${STUB_DIR}/lookup_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42
  [ "$status" -eq 0 ]
  [ "$(calls lookup)" -eq 1 ]
}

@test "delivery: a failed listing falls back to one lookup per package" {
  printf '%s\n' "${SHAS[@]}" > "${STUB_DIR}/lookup_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42 BATCH_FAILS=1
  [ "$status" -eq 0 ]
  [ "$(calls lookup)" -eq 3 ]
  [[ "$output" == *"falling back to one lookup per package"* ]]
}

@test "promotion: no listing, one lookup per package" {
  printf '%s\n' "${SHAS[@]}" > "${STUB_DIR}/lookup_shas"
  check_deb CHECK_MODE=promote GITHUB_RUN_ID=42
  [ "$status" -eq 0 ]
  [ "$(calls batch)" -eq 0 ]
  [ "$(calls lookup)" -eq 3 ]
}

@test "a package absent from the repository fails the verification" {
  printf '%s\n' "${SHAS[0]}" "${SHAS[1]}" > "${STUB_DIR}/batch_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42
  [ "$status" -ne 0 ]
  [[ "$output" == *"2/3 present"* ]]
}

@test "every package is fetched once when the content url answers" {
  printf '%s\n' "${SHAS[@]}" > "${STUB_DIR}/batch_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42
  [ "$status" -eq 0 ]
  [ "$(calls head)" -eq 3 ]
}

@test "a package that cannot be fetched is retried, then fails the verification" {
  printf '%s\n' "${SHAS[@]}" > "${STUB_DIR}/batch_shas"
  check_deb CHECK_MODE=delivery GITHUB_RUN_ID=42 UNFETCHABLE=pkg1_1.0
  [ "$status" -ne 0 ]
  [ "$(calls head)" -eq 5 ]
  [[ "$output" == *"pkg1_1.0_all.deb"*"fetchable=❌"* ]]
  [[ "$output" == *"pkg0_1.0_all.deb"*"fetchable=✅"* ]]
}
