#!/usr/bin/env bats
# Source tarball and upload destination of the sources delivery, with a stand-in aws.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../delivery/deliver.sh"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${WORK}/gorgone/docs"
  echo "content" > "${WORK}/gorgone/README.md"
  echo "doc" > "${WORK}/gorgone/docs/index.md"
  # records its arguments, one call per line
  cat > "${BATS_TEST_TMPDIR}/bin/aws" << STUB
#!/bin/sh
echo "\$*" >> "${BATS_TEST_TMPDIR}/aws.calls"
STUB
  chmod +x "${BATS_TEST_TMPDIR}/bin/aws"
  export GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/output"
  cd "$WORK"
}

# runs the script with exactly the environment of the action step
deliver() {
  run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" GITHUB_OUTPUT="$GITHUB_OUTPUT" \
    MODULE_NAME=centreon-gorgone MODULE_DIRECTORY=gorgone BUCKET_DIRECTORY=centreon-gorgone \
    MAJOR_VERSION=26.10 MINOR_VERSION=3 BUCKET=centreon-download DRY_RUN=false "$@" "$SCRIPT"
}

@test "the tarball is named after the module and holds one versioned directory" {
  deliver
  [ "$status" -eq 0 ]
  [ -f centreon-gorgone-26.10.3.tar.gz ]
  run tar tzf centreon-gorgone-26.10.3.tar.gz
  [[ "$output" == *"centreon-gorgone-26.10.3/README.md"* ]]
  [[ "$output" == *"centreon-gorgone-26.10.3/docs/index.md"* ]]
  [[ "$output" != *$'\ngorgone/'* ]]
}

@test "the tarball is uploaded publicly under public/<bucket_directory>" {
  deliver
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${BATS_TEST_TMPDIR}/aws.calls")" -eq 1 ]
  run cat "${BATS_TEST_TMPDIR}/aws.calls"
  [ "$output" = "s3 cp --acl public-read centreon-gorgone-26.10.3.tar.gz s3://centreon-download/public/centreon-gorgone/centreon-gorgone-26.10.3.tar.gz" ]
}

@test "the outputs give the file and its destination" {
  deliver
  [ "$status" -eq 0 ]
  grep -qx "source_file=centreon-gorgone-26.10.3.tar.gz" "$GITHUB_OUTPUT"
  grep -qx "destination=s3://centreon-download/public/centreon-gorgone/centreon-gorgone-26.10.3.tar.gz" "$GITHUB_OUTPUT"
}

@test "another bucket can be targeted" {
  deliver BUCKET=some-test-bucket
  [ "$status" -eq 0 ]
  grep -q "s3://some-test-bucket/public/centreon-gorgone/" "${BATS_TEST_TMPDIR}/aws.calls"
}

@test "a dry run builds the tarball and uploads nothing" {
  deliver DRY_RUN=true
  [ "$status" -eq 0 ]
  [ -f centreon-gorgone-26.10.3.tar.gz ]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.calls" ]
  [[ "$output" == *"would be uploaded to s3://centreon-download/public/centreon-gorgone/centreon-gorgone-26.10.3.tar.gz"* ]]
}

@test "a failed upload fails the delivery" {
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/aws"
  deliver
  [ "$status" -ne 0 ]
}

@test "an empty required input is rejected before anything is built" {
  deliver MINOR_VERSION=
  [ "$status" -ne 0 ]
  [[ "$output" == *"minor_version input is empty"* ]]
  [ ! -e centreon-gorgone-26.10..tar.gz ]
  [ -d gorgone ]
}

@test "a missing module directory is rejected" {
  deliver MODULE_DIRECTORY=absent
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a directory"* ]]
}

@test "a bucket directory leaving its prefix is rejected" {
  deliver BUCKET_DIRECTORY=../private
  [ "$status" -ne 0 ]
  deliver BUCKET_DIRECTORY=centreon/../../private
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.calls" ]
}

@test "a module name with a path or an option is rejected" {
  deliver MODULE_NAME=../evil
  [ "$status" -ne 0 ]
  deliver MODULE_NAME=--checkpoint-action
  [ "$status" -ne 0 ]
  [ -d gorgone ]
}

@test "an unknown dry_run value is rejected rather than read as false" {
  deliver DRY_RUN=yes
  [ "$status" -ne 0 ]
  [ ! -e "${BATS_TEST_TMPDIR}/aws.calls" ]
}

@test "optional inputs have defaults" {
  run env -i PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" MODULE_NAME=centreon-gorgone MODULE_DIRECTORY=gorgone \
    BUCKET_DIRECTORY=centreon-gorgone MAJOR_VERSION=26.10 MINOR_VERSION=3 "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "s3://centreon-download/public/centreon-gorgone/" "${BATS_TEST_TMPDIR}/aws.calls"
}

@test "a nested module directory is archived under the versioned name" {
  mkdir -p nested/module && echo x > nested/module/file
  deliver MODULE_NAME=centreon-web MODULE_DIRECTORY=nested/module BUCKET_DIRECTORY=centreon
  [ "$status" -eq 0 ]
  run tar tzf centreon-web-26.10.3.tar.gz
  [[ "$output" == *"centreon-web-26.10.3/file"* ]]
  grep -q "s3://centreon-download/public/centreon/centreon-web-26.10.3.tar.gz" "${BATS_TEST_TMPDIR}/aws.calls"
}
