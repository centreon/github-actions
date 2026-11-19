#!/usr/bin/env bats

SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../update-major-tags.sh"
  export GITHUB_REPOSITORY=centreon/github-actions
  export GH_CALLS="${BATS_TEST_TMPDIR}/calls"
  export RELEASE_SHA="$SHA"
  : > "$GH_CALLS"
  # gh stand-in: logs its arguments; the tag lookup succeeds when TAG_EXISTS=1
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
case "$2" in
  repos/*/git/ref/tags/*) [[ "${TAG_EXISTS:-0}" == 1 ]] ;;
  repos/*/commits/tags/missing/*) exit 1 ;;
  repos/*/commits/tags/*) echo "$RELEASE_SHA" ;;
esac
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

releases() {
  jq -cn --arg tag "$1" --arg sha "$SHA" \
    '{paths_released: "[\"pulp\"]", "pulp--tag_name": $tag, "pulp--sha": $sha}'
}

@test "first release of a major creates its floating tag" {
  RELEASES=$(releases pulp/v1.0.0) run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF -- "-X POST repos/centreon/github-actions/git/refs -f ref=refs/tags/pulp/v1 -f sha=${SHA}" "$GH_CALLS"
}

@test "later release moves the floating tag" {
  RELEASES=$(releases pulp/v1.4.2) TAG_EXISTS=1 run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF -- "-X PATCH repos/centreon/github-actions/git/refs/tags/pulp/v1 -f sha=${SHA} -F force=true" "$GH_CALLS"
}

@test "new major gets its own floating tag" {
  RELEASES=$(releases pulp/v2.0.0) run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qF "ref=refs/tags/pulp/v2 " "$GH_CALLS"
  ! grep -qF "tags/pulp/v1" "$GH_CALLS"
}

@test "nothing released, nothing moved" {
  RELEASES='{"releases_created": "false"}' run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -s "$GH_CALLS" ]
}

@test "unexpected tag format fails without touching tags" {
  RELEASES=$(releases pulp-v1.0.0) run "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -s "$GH_CALLS" ]
}

@test "rollback: an explicit release tag moves its major tag back" {
  TAG_EXISTS=1 run "$SCRIPT" pulp/v1.4.1
  [ "$status" -eq 0 ]
  grep -qF -- "-X PATCH repos/centreon/github-actions/git/refs/tags/pulp/v1 -f sha=${SHA} -F force=true" "$GH_CALLS"
}

@test "rollback: an unknown release tag fails without touching tags" {
  run "$SCRIPT" missing/v1.0.0
  [ "$status" -ne 0 ]
  ! grep -qE -- "-X (PATCH|POST)" "$GH_CALLS"
}

@test "rollback: anything but a release tag is refused before any api call" {
  for tag in pulp/v1 v1.0.0 "pulp/v1.0.0/../../x" "../pulp/v1.0.0" "Pulp/v1.0.0"; do
    run "$SCRIPT" "$tag"
    [ "$status" -ne 0 ] || { echo "accepted: ${tag}"; return 1; }
  done
  [ ! -s "$GH_CALLS" ]
}
