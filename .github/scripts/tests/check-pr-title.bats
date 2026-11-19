#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../check-pr-title.sh"
}

@test "conventional titles are accepted" {
  for title in "feat(pulp): add an input" "fix: handle 503" "feat(pulp)!: rename an input" \
    "chore(main): release pulp 1.2.0" "fix(deps): bump actions/cache"; do
    run "$SCRIPT" "$title"
    [ "$status" -eq 0 ] || { echo "rejected: ${title}"; return 1; }
  done
}

@test "other titles are rejected" {
  for title in "Update action.yml" "feat add an input" "feature(pulp): x" "fix(pulp):missing space" ""; do
    run "$SCRIPT" "$title"
    [ "$status" -ne 0 ] || { echo "accepted: ${title}"; return 1; }
  done
}
