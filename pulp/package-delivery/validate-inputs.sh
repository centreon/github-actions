#!/usr/bin/env bash
set -euo pipefail

STABILITY="${STABILITY:-}"
DELIVERY_TYPE="${DELIVERY_TYPE:-standard}"
ALLOW_STABLE="${ALLOW_STABLE:-false}"

if [[ "$ALLOW_STABLE" == "true" && "$DELIVERY_TYPE" == "feature" ]]; then
  echo "::error::allow_stable cannot be combined with a feature delivery"
  exit 1
fi

# stable is normally only fed by a promotion: a direct delivery is an explicit choice
if [[ "$STABILITY" == "stable" && "$ALLOW_STABLE" == "true" ]]; then
  exit 0
fi

if [[ "$DELIVERY_TYPE" != "feature" && "$STABILITY" != "testing" && "$STABILITY" != "unstable" ]]; then
  echo "::error::stability must be one of: testing, unstable (got '$STABILITY')"
  exit 1
fi
