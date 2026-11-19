#!/usr/bin/env bats
# Rerun of a deb promotion interrupted after its repository modify, against
# stand-ins for curl and pulp.

SHAS=(
  1111111111111111111111111111111111111111111111111111111111111111
  2222222222222222222222222222222222222222222222222222222222222222
)

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../promote-to-stable/promote-deb.sh"
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  : > "${STUB_DIR}/calls"
  : > "${STUB_DIR}/stable_Packages"

  # testing index and api listing of two packages of the module
  local i
  : > "${STUB_DIR}/testing_Packages"
  : > "${STUB_DIR}/listing"
  for i in 0 1; do
    printf 'Package: pkg%s\nFilename: pool/pkg%s_1.0_all.deb\nSHA256: %s\n\n' "$i" "$i" "${SHAS[$i]}" \
      >> "${STUB_DIR}/testing_Packages"
    jq -cn --arg n "pkg${i}" --arg s "${SHAS[$i]}" --arg h "/content/packages/${i}/" \
      '{pulp_href: $h, package: $n, version: "1.0", architecture: "all", sha256: $s, relative_path: ("pool/" + $n + "_1.0_all.deb")}' \
      >> "${STUB_DIR}/listing"
  done

  cat > "${STUB_DIR}/bin/pulp" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"repository show"* ]]; then
  echo '{"pulp_href": "/repositories/1/", "latest_version_href": "/repositories/1/versions/5/"}'
fi
STUB

  # curl stand-in: answers by url; the suite associations already exist (the
  # interrupted run added them) and only a publication makes stable serve them
  cat > "${STUB_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"
out="" code=0 body=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[$i]}" == "-o" ]] && out="${args[$((i + 1))]}"
  [[ "${args[$i]}" == "-w" ]] && code=1
done
status=200
case "$url" in
  */dists/*/Release) body="Architectures: all" ;;
  */dists/testing-suite/*/Packages) body=$(cat "${STUB_DIR}/testing_Packages") ;;
  */dists/stable-suite/*/Packages) body=$(cat "${STUB_DIR}/stable_Packages") ;;
  */pool/*) body="deb" ;;
  */api/v3/repositories/deb/apt/) body='{"count": 1}' ;;
  */content/deb/release_components/\?*)
    echo "release_components" >> "${STUB_DIR}/calls"
    echo "curl: (22) The requested URL returned error: 403" >&2
    exit 22
    ;;
  */content/deb/package_release_components/)
    body='{"pulp_href": "/content/prc/1/", "results": [{"pulp_href": "/content/prc/1/", "release_component": "/content/release_components/1/"}]}'
    ;;
  */modify/)
    echo "modify" >> "${STUB_DIR}/calls"
    body='{"task": "/tasks/add/"}'
    status=202
    ;;
  */content/deb/packages/\?*) body=$(jq -sc '{next: null, results: .}' "${STUB_DIR}/listing") ;;
  */content/deb/packages/)
    if [[ " $* " == *" -F "* ]]; then
      echo "upload" >> "${STUB_DIR}/calls"
      body='{"task": "/tasks/upload/"}'
      status=202
    else
      body='{"results": [{"pulp_href": "/content/packages/0/"}]}'
    fi
    ;;
  */publications/deb/apt/)
    echo "publish" >> "${STUB_DIR}/calls"
    [[ "${PUBLISH_SERVES:-1}" == 1 ]] && cp "${STUB_DIR}/testing_Packages" "${STUB_DIR}/stable_Packages"
    body='{"task": "/tasks/publish/"}'
    status=202
    ;;
  */tasks/*) body='{"state": "completed"}' ;;
  *)
    echo "unexpected ${url}" >> "${STUB_DIR}/calls"
    exit 22
    ;;
esac
if [[ -n "$out" ]]; then
  printf '%s\n' "$body" > "$out"
  [[ "$code" == 1 ]] && printf '%s' "$status"
elif [[ "$code" == 1 ]]; then
  printf '%s\n%s' "$body" "$status"
else
  printf '%s\n' "$body"
fi
exit 0
STUB
  chmod +x "${STUB_DIR}/bin/pulp" "${STUB_DIR}/bin/curl"

  export PATH="${STUB_DIR}/bin:${PATH}"
  export GITHUB_WORKSPACE="${BATS_TEST_TMPDIR}"
  export PULP_URL="https://pulp.invalid" PULP_CONTENT_URL="https://content.invalid"
  export PULP_TOKEN="token" PULP_DOMAIN="business" PULP_STABLE_DOMAIN="business"
  export MODULE_NAME="mod" DISTRIB="trixie" STABILITY="stable"
  export REPOSITORY_NAME="apt-testing" BASE_PATH="apt-testing" TESTING_SUITE="testing-suite"
  export STABLE_REPOSITORY_NAME="apt-stable" STABLE_BASE_PATH="apt-stable" STABLE_SUITE="stable-suite"
  cd "${BATS_TEST_TMPDIR}"
}

@test "an interrupted promotion is republished when the release component listing is refused" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the interrupted promotion only missed the publication"* ]]
  grep -qx "release_components" "${STUB_DIR}/calls"
  [ "$(grep -cx "publish" "${STUB_DIR}/calls")" -eq 1 ]
  ! grep -q "^unexpected" "${STUB_DIR}/calls"
  [ "$(jq '.packages | length' "${BATS_TEST_TMPDIR}/pulp-delivery-manifest.json")" -eq 2 ]
}

@test "the promotion fails when the republished suite still misses packages" {
  PUBLISH_SERVES=0 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 candidate package(s) are missing from the published stable-suite suite"* ]]
  ! grep -q "^unexpected" "${STUB_DIR}/calls"
}

@test "a 24.x promotion mirrors into the legacy repository without the admin-only listing" {
  STABLE_LEGACY_SUITE=trixie STABLE_LEGACY_REPOSITORY_NAME=apt-standard-24.10-stable run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Release component of apt-standard-24.10-stable trixie/main"* ]]
  [[ "$output" == *"Mirroring 2 package association(s) into apt-standard-24.10-stable trixie/main"* ]]
  # only the stable suite lookup of the recovery still tries the listing
  [ "$(grep -cx "release_components" "${STUB_DIR}/calls")" -eq 1 ]
  # the mirror adds the associations to the legacy repository and publishes it
  [ "$(grep -cx "modify" "${STUB_DIR}/calls")" -eq 1 ]
  [ "$(grep -cx "publish" "${STUB_DIR}/calls")" -eq 2 ]
  ! grep -q "^unexpected" "${STUB_DIR}/calls"
}
