#!/usr/bin/env bats
# Values of parse-distrib for every distribution, as the local copies of the product
# repositories gave them.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../parse-distrib/parse-distrib.sh"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
}

# runs the script with exactly the environment of the action step
parse() {
  : > "$GITHUB_OUTPUT"
  run env -i PATH="$PATH" GITHUB_OUTPUT="$GITHUB_OUTPUT" DISTRIB="$1" "$SCRIPT"
}

output_of() {
  sed -n "s/^$1=//p" "$GITHUB_OUTPUT"
}

# expect <distrib> <extension> <version sep> <distrib sep> <package distrib name> <family> <family major> <name> <repo name>
expect() {
  parse "$1"
  [ "$status" -eq 0 ]
  [ "$(output_of package_extension)" = "$2" ]
  [ "$(output_of package_version_separator)" = "$3" ]
  [ "$(output_of package_distrib_separator)" = "$4" ]
  [ "$(output_of package_distrib_name)" = "$5" ]
  [ "$(output_of distrib_family)" = "$6" ]
  [ "$(output_of distrib_family_major)" = "$7" ]
  [ "$(output_of distrib_name)" = "$8" ]
  [ "$(output_of repo_distrib_name)" = "$9" ]
  [ "$(output_of package_distrib)" = "$9" ]
}

@test "el distributions, under their el or alma name" {
  expect el8 rpm - . el8 el el8 alma8 el8
  expect alma8 rpm - . el8 el el8 alma8 el8
  expect el9 rpm - . el9 el el9 alma9 el9
  expect alma9 rpm - . el9 el el9 alma9 el9
  expect el10 rpm - . el10 el el10 alma10 el10
  expect alma10 rpm - . el10 el el10 alma10 el10
}

@test "el7 keeps its centos name" {
  expect el7 rpm - . el7 el el7 centos7 el7
  expect centos7 rpm - . el7 el el7 centos7 el7
}

@test "debian distributions" {
  expect bullseye deb _ + deb11u1 debian debian bullseye bullseye
  expect bookworm deb _ + deb12u1 debian debian bookworm bookworm
  expect trixie deb _ + deb13u1 debian debian trixie trixie
}

@test "ubuntu distributions" {
  expect jammy deb _ - 0ubuntu.22.04 ubuntu ubuntu jammy jammy
  expect noble deb _ - 0ubuntu.24.04 ubuntu ubuntu noble noble
}

@test "every output is set, once, for every distribution" {
  for distrib in centos7 el7 alma8 el8 alma9 el9 alma10 el10 bullseye bookworm trixie jammy noble; do
    parse "$distrib"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$GITHUB_OUTPUT")" -eq 9 ]
    [ "$(cut -d= -f1 "$GITHUB_OUTPUT" | sort -u | wc -l)" -eq 9 ]
    [ "$(grep -c '=$' "$GITHUB_OUTPUT")" -eq 0 ]
  done
}

@test "the outputs are the ones the action declares" {
  parse el9
  declared=$(sed -n '/^outputs:/,/^runs:/p' "${BATS_TEST_DIRNAME}/../parse-distrib/action.yml" | sed -n 's/^  \([a-z_]*\):$/\1/p' | sort)
  written=$(cut -d= -f1 "$GITHUB_OUTPUT" | sort)
  [ -n "$declared" ]
  [ "$declared" = "$written" ]
}

@test "an unknown distribution is rejected and writes nothing" {
  for distrib in focal sid el el11 EL9 "el9 " bookworm-backports; do
    parse "$distrib"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot be parsed"* ]]
    [ ! -s "$GITHUB_OUTPUT" ]
  done
}

@test "an empty distribution is rejected" {
  parse ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"distrib input is empty"* ]]
  [ ! -s "$GITHUB_OUTPUT" ]
}

@test "a distribution holding shell characters is rejected, not run" {
  parse 'el9; touch '"${BATS_TEST_TMPDIR}"'/ran'
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
  parse '$(touch '"${BATS_TEST_TMPDIR}"'/ran)'
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/ran" ]
}

# the pulp package keeps its own table, since a package never reads another one:
# this is what tells when one of the two is changed without the other
@test "the pulp package gives the same values for the outputs it has" {
  pulp_table="${BATS_TEST_DIRNAME}/../../pulp/lib/parse-distrib.sh"
  [ -f "$pulp_table" ]
  for distrib in centos7 el7 alma8 el8 alma9 el9 alma10 el10 bullseye bookworm trixie jammy noble; do
    parse "$distrib"
    [ "$status" -eq 0 ]
    pulp_output="${BATS_TEST_TMPDIR}/pulp-output"
    : > "$pulp_output"
    env -i PATH="$PATH" DISTRIB="$distrib" GITHUB_OUTPUT="$pulp_output" bash -c "source '$pulp_table'"
    for name in package_extension package_distrib_separator package_distrib_name distrib_family; do
      [ "$(sed -n "s/^${name}=//p" "$pulp_output")" = "$(output_of "$name")" ]
    done
  done
  run env -i PATH="$PATH" DISTRIB=focal GITHUB_OUTPUT="$pulp_output" bash -c "source '$pulp_table'"
  [ "$status" -ne 0 ]
}
