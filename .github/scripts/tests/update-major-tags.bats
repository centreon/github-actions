#!/usr/bin/env bats

SHA=0123456789abcdef0123456789abcdef01234567

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../update-major-tags.sh"
  export GITHUB_REPOSITORY=centreon/github-actions
  export GH_CALLS="${BATS_TEST_TMPDIR}/calls"
  : > "$GH_CALLS"
  # gh stand-in: logs its arguments; the tag lookup succeeds when TAG_EXISTS=1
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
if [[ "$2" == repos/*/git/ref/tags/* ]]; then
  [[ "${TAG_EXISTS:-0}" == 1 ]]
fi
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
