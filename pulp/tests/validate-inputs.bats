#!/usr/bin/env bats
# Stabilities a delivery accepts: stable only when the caller asks for it.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../package-delivery/validate-inputs.sh"
}

validate() {
  run env -i PATH="$PATH" "$@" "$SCRIPT"
}

@test "testing and unstable deliveries are accepted" {
  validate STABILITY=testing DELIVERY_TYPE=standard ALLOW_STABLE=false
  [ "$status" -eq 0 ]
  validate STABILITY=unstable DELIVERY_TYPE=standard ALLOW_STABLE=false
  [ "$status" -eq 0 ]
}

@test "a feature delivery accepts any stability" {
  validate STABILITY=canary DELIVERY_TYPE=feature ALLOW_STABLE=false
  [ "$status" -eq 0 ]
}

@test "a stable delivery is refused by default" {
  validate STABILITY=stable DELIVERY_TYPE=standard ALLOW_STABLE=false
  [ "$status" -ne 0 ]
  [[ "$output" == *"stability must be one of: testing, unstable"* ]]
}

@test "a stable delivery is refused when allow_stable is not passed" {
  validate STABILITY=stable
  [ "$status" -ne 0 ]
}

@test "a stable delivery is accepted with allow_stable" {
  validate STABILITY=stable DELIVERY_TYPE=standard ALLOW_STABLE=true
  [ "$status" -eq 0 ]
}

@test "allow_stable does not accept an unknown stability" {
  validate STABILITY=canary DELIVERY_TYPE=standard ALLOW_STABLE=true
  [ "$status" -ne 0 ]
}

@test "allow_stable is refused on a feature delivery" {
  validate STABILITY=stable DELIVERY_TYPE=feature ALLOW_STABLE=true
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be combined with a feature delivery"* ]]
}
