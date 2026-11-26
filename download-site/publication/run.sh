#!/usr/bin/env bash
# Turn the inputs of the action into the options of publish.sh.
# Inputs (env): PDR_ENTRIES, PDR_BRANCH, PDR_COMMIT_MESSAGE, PDR_PR_TITLE, and
# optionally PDR_OUT_NAME, PDR_PR_BODY_FILE, PDR_PR_LABEL, PDR_AGENT_VERSION,
# PDR_AGENT_FILE_URL, PDR_AGENT_MD5, PDR_AGENT_SIZE, PDR_SIDECAR, PDR_DRY_RUN.
set -euo pipefail

ARGS=(
  --entries "${PDR_ENTRIES:-}"
  --branch "${PDR_BRANCH:-}"
  --commit-message "${PDR_COMMIT_MESSAGE:-}"
  --pr-title "${PDR_PR_TITLE:-}"
  --pr-label "${PDR_PR_LABEL-release}"
)
if [[ -n "${PDR_OUT_NAME:-}" ]]; then
  ARGS+=(--out-name "$PDR_OUT_NAME")
fi
if [[ -n "${PDR_PR_BODY_FILE:-}" ]]; then
  ARGS+=(--pr-body-file "$PDR_PR_BODY_FILE")
fi
# all four or none: publish.sh reports which one is missing
if [[ -n "${PDR_AGENT_VERSION:-}${PDR_AGENT_FILE_URL:-}${PDR_AGENT_MD5:-}${PDR_AGENT_SIZE:-}" ]]; then
  [[ -n "${PDR_AGENT_VERSION:-}" ]] \
    || { echo "::error::agent_file_url, agent_md5 and agent_size need agent_version"; exit 1; }
  ARGS+=(--agent-version "$PDR_AGENT_VERSION")
  [[ -z "${PDR_AGENT_FILE_URL:-}" ]] || ARGS+=(--agent-file-url "$PDR_AGENT_FILE_URL")
  [[ -z "${PDR_AGENT_MD5:-}" ]] || ARGS+=(--agent-md5 "$PDR_AGENT_MD5")
  [[ -z "${PDR_AGENT_SIZE:-}" ]] || ARGS+=(--agent-size "$PDR_AGENT_SIZE")
fi
if [[ "${PDR_SIDECAR:-false}" == "true" ]]; then
  ARGS+=(--sidecar)
fi
if [[ "${PDR_DRY_RUN:-false}" == "true" ]]; then
  ARGS+=(--dry-run)
fi

exec "$(dirname "$0")/publish.sh" "${ARGS[@]}"
