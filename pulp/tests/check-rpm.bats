#!/usr/bin/env bats
# rpm verification (presence, published metadata, download), against stand-ins
# for curl and pulp.

SHAS=(
  1111111111111111111111111111111111111111111111111111111111111111
  2222222222222222222222222222222222222222222222222222222222222222
  3333333333333333333333333333333333333333333333333333333333333333
)

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../lib/check-rpm.sh"
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  : > "${STUB_DIR}/calls"

  cat > "${STUB_DIR}/bin/pulp" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"repository show"* ]]; then
  echo '{"latest_version_href": "/pulp/plugins/api/v3/repositories/rpm/rpm/1/versions/5/"}'
fi
STUB

  # curl stand-in: the repository listing, the published repodata and the downloads
  cat > "${STUB_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *content/rpm/packages/*)
    echo "listing" >> "${STUB_DIR}/calls"
    jq -Rn '[inputs | {location_href: ("Packages/p/" + .)}] | {count: length, next: null, results: .}' < "${STUB_DIR}/listed"
    ;;
  */repodata/repomd.xml) echo '<data type="primary"><location href="repodata/1-primary.xml.gz"/></data>' ;;
  */repodata/1-primary.xml.gz) gzip -c "${STUB_DIR}/primary.xml" ;;
  *)
    if [[ " $* " == *" -I "* ]]; then
      echo "head" >> "${STUB_DIR}/calls"
      printf '200 %s' "$url"
    fi
    ;;
esac
STUB
  chmod +x "${STUB_DIR}/bin/pulp" "${STUB_DIR}/bin/curl"

  # manifest, repository listing and published metadata of three delivered packages
  local entries=() i file
  : > "${STUB_DIR}/listed"
  : > "${STUB_DIR}/primary.xml"
  for i in 0 1 2; do
    file="pkg${i}-1.0-1.el9.noarch.rpm"
    entries+=("$(jq -cn --arg f "$file" --arg s "${SHAS[$i]}" \
      '{filename: $f, arch: "noarch", sha256: $s, repository: "rpm-el9-unstable-noarch", base_path: "rpm-plugins/el9/unstable/noarch"}')")
    echo "$file" >> "${STUB_DIR}/listed"
    printf '<package type="rpm"><checksum type="sha256" pkgid="YES">%s</checksum><location href="Packages/p/%s"/></package>\n' \
      "${SHAS[$i]}" "$file" >> "${STUB_DIR}/primary.xml"
  done
  printf '%s\n' "${entries[@]}" | jq -s '{packages: .}' > "${STUB_DIR}/manifest.json"
}

check_rpm() {
  run env PATH="${STUB_DIR}/bin:${PATH}" STUB_DIR="$STUB_DIR" \
    MANIFEST="${STUB_DIR}/manifest.json" MODULE_NAME=plugins DISTRIB=el9 STABILITY=unstable CHECK_MODE=delivery \
    PULP_URL=https://pulp.invalid PULP_CONTENT_URL=https://content.invalid PULP_DOMAIN=plugins \
    PULP_TOKEN=placeholder PULP_TOKEN_ISSUED_AT="$(date +%s)" \
    METADATA_TIMEOUT=1 METADATA_INTERVAL=1 GITHUB_STEP_SUMMARY="${STUB_DIR}/summary" \
    "$@" "$SCRIPT"
}

calls() {
  grep -cx "$1" "${STUB_DIR}/calls" || true
}

@test "delivered packages are found in one listing, resolved and fetched once" {
  check_rpm
  [ "$status" -eq 0 ]
  [ "$(calls listing)" -eq 1 ]
  [ "$(calls head)" -eq 3 ]
  [[ "$output" == *"All 3 package(s) verified"* ]]
}

@test "a package absent from the repository fails the verification" {
  sed -i '/^pkg1-/d' "${STUB_DIR}/listed"
  check_rpm
  [ "$status" -ne 0 ]
  [[ "$output" == *"2/3 present"* ]]
}

@test "a package absent from the published metadata fails the verification" {
  sed -i "/${SHAS[2]}/d" "${STUB_DIR}/primary.xml"
  check_rpm
  [ "$status" -ne 0 ]
  [[ "$output" == *"2/3 resolvable"* ]]
  [[ "$output" == *"pkg2-1.0-1.el9.noarch.rpm"*"metadata=❌"* ]]
}

@test "older builds in the repository are reported, not failed" {
  echo "pkg0-0.9-1.el9.noarch.rpm" >> "${STUB_DIR}/listed"
  check_rpm
  [ "$status" -eq 0 ]
  [[ "$output" == *"holds 4 module packages, 3 delivered by this run"* ]]
}
