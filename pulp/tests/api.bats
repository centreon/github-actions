#!/usr/bin/env bats
# Outcome of a pulp task as the delivery scripts read it, against a curl
# stand-in that serves a scripted sequence of task states.

setup() {
  export STUB_DIR="${BATS_TEST_TMPDIR}/stub"
  mkdir -p "${STUB_DIR}/bin"
  # each poll consumes the first line of the sequence; the last one repeats
  cat > "${STUB_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
body=$(head -n 1 "${STUB_DIR}/tasks")
if (($(wc -l < "${STUB_DIR}/tasks") > 1)); then
  sed -i 1d "${STUB_DIR}/tasks"
fi
[[ "$body" == "unreachable" ]] && exit 7
echo "$body"
STUB
  chmod +x "${STUB_DIR}/bin/curl"
}

# wait_task <budget env...> : poll a task with the scripted states, no real sleep
wait_task() {
  run env PATH="${STUB_DIR}/bin:${PATH}" STUB_DIR="$STUB_DIR" PULP_URL=https://pulp.invalid PULP_DOMAIN=plugins \
    PULP_TOKEN=placeholder PULP_TOKEN_ISSUED_AT="$(date +%s)" "$@" \
    bash -c 'source "$1"; sleep() { command sleep 0.2; }; wait_task_race /pulp/api/v3/tasks/1/' _ "${BATS_TEST_DIRNAME}/../lib/api.sh"
}

states() {
  printf '%s\n' "$@" > "${STUB_DIR}/tasks"
}

@test "a completed task succeeds" {
  states '{"state": "completed"}'
  wait_task
  [ "$status" -eq 0 ]
}

@test "a task is polled through waiting and running until it completes" {
  states '{"state": "waiting"}' '{"state": "running"}' '{"state": "completed"}'
  wait_task
  [ "$status" -eq 0 ]
}

@test "a failed task fails with its error" {
  states '{"state": "failed", "error": {"description": "bad package"}}'
  wait_task
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad package"* ]]
}

@test "a lost repository-version race is reported as retryable" {
  states '{"state": "failed", "error": {"description": "duplicate key value violates core_repositoryversion"}}'
  wait_task
  [ "$status" -eq 2 ]
}

@test "a task whose worker went missing is reported as retryable" {
  states '{"state": "canceled", "reason": "Worker has gone missing"}'
  wait_task
  [ "$status" -eq 2 ]
}

@test "a failed poll does not fail the task" {
  states unreachable '{"state": "completed"}'
  wait_task
  [ "$status" -eq 0 ]
}

@test "a task that stays queued fails once its waiting budget is spent" {
  states '{"state": "waiting", "pulp_created": "2026-01-01T00:00:00Z", "unblocked_at": "2026-01-01T00:00:01Z"}'
  wait_task PULP_TASK_WAITING_TIMEOUT=1
  [ "$status" -eq 1 ]
  [[ "$output" == *"still waiting for its resources"* ]]
}

@test "a task that keeps running fails once its running budget is spent" {
  states '{"state": "running"}'
  wait_task PULP_TASK_RUNNING_TIMEOUT=1
  [ "$status" -eq 1 ]
  [[ "$output" == *"still running"* ]]
}
