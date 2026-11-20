#!/usr/bin/env bash
# Install pulp-cli, request a GitHub OIDC token and configure pulp-cli.
# Inputs (env): PULP_URL, AUDIENCE, DOMAIN.
set -euo pipefail

if ! command -v pulp > /dev/null 2>&1; then
  echo "[INFO] Installing pulp-cli"
  pip install --quiet "pulp-cli==0.37.1" "pulp-cli-deb==0.4.3"
fi

# an unset org variable is forwarded as "": fail loudly rather than
# falling back to a default audience, a token minted for the wrong
# audience must never be silently requested against another server
if [[ -z "${AUDIENCE:-}" ]]; then
  echo "::error::audience input is empty (is the PULP_OIDC_AUDIENCE org variable defined?)"
  exit 1
fi

# the job must grant id-token write permission for these to be set
if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
  echo "::error::Missing OIDC token request context, the job needs 'permissions: id-token: write'"
  exit 1
fi

# retry on transient GitHub OIDC token service errors (5xx/timeouts):
# the endpoint occasionally returns 503, and a single blip must not break
# the whole delivery.
PULP_TOKEN=$(
  curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    -G --data-urlencode "audience=${AUDIENCE}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}" | jq -r '.value'
)
if [[ -z "$PULP_TOKEN" || "$PULP_TOKEN" == "null" ]]; then
  echo "::error::Could not obtain a GitHub OIDC token"
  exit 1
fi

# keep the token out of any log and expose it to the next steps.
# the issuance time and audience let the api helpers refresh the token
# mid-delivery: github oidc tokens expire ~5 minutes after issuance,
# which is shorter than a large delivery.
echo "::add-mask::${PULP_TOKEN}"
{
  echo "PULP_TOKEN=${PULP_TOKEN}"
  echo "PULP_TOKEN_ISSUED_AT=$(date +%s)"
  echo "PULP_OIDC_AUDIENCE=${AUDIENCE}"
} >> "$GITHUB_ENV"

# fall back to the default when the caller passes an empty value (unset
# org variable forwarded as "" would otherwise override the default).
PULP_URL="${PULP_URL:-https://pulp-api.int.centreon.com}"
DOMAIN="${DOMAIN:-default}"

# keep the pulp-cli config (which stores the OIDC token) under the per-job
# RUNNER_TEMP rather than the runner's persistent ~/.config, and share the
# location with the later steps, so a self-hosted runner does not retain
# the token in a home reused across jobs.
export XDG_CONFIG_HOME="${RUNNER_TEMP:-/tmp}/pulp-cli-config"
mkdir -p "$XDG_CONFIG_HOME"
echo "XDG_CONFIG_HOME=${XDG_CONFIG_HOME}" >> "$GITHUB_ENV"

# WorkloadIdentityAuthentication reads a Bearer token, no username/password
# pulp-cli splits --header on the first colon and keeps the value
# verbatim, so no space after the colon (rejected as leading whitespace)
pulp config create --overwrite \
  --base-url "$PULP_URL" \
  --api-root "/" \
  --domain "$DOMAIN" \
  --header "Authorization:Bearer ${PULP_TOKEN}" \
  --timeout 0

# fail fast on connectivity issues, scripts cannot distinguish
# a missing resource from an unreachable server otherwise
if ! pulp status > /dev/null; then
  echo "::error::Pulp server ${PULP_URL} is not reachable"
  exit 1
fi
