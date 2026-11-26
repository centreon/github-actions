#!/usr/bin/env bats
# Edition of the agent block of the site catalog.

MD5="0123456789abcdef0123456789abcdef"

setup() {
  EDITOR_PY="${BATS_TEST_DIRNAME}/../publication/catalog-agent-entry.py"
  CATALOG="${BATS_TEST_TMPDIR}/catalog.yaml"
  cat > "$CATALOG" << 'CATALOG'
versions:
  - id: "26.10"
products:
  centreon-monitoring-agent:
    group: "agent"
agent:
  targets:
    - id: windows
      label: "Windows"
      downloads:
        - version: "26.10.1"
          file_url: "https://example.invalid/agent-26.10.1.exe"
          md5: "11111111111111111111111111111111"
          size: 1001
        - version: "25.10.8"
          file_url: "https://example.invalid/agent-25.10.8.exe"
          md5: "22222222222222222222222222222222"
          size: 1002
      all_versions:
        - version: "26.10.1"
          file_url: "https://example.invalid/agent-26.10.1.exe"
          md5: "11111111111111111111111111111111"
          size: 1001
        - version: "25.10.8"
          file_url: "https://example.invalid/agent-25.10.8.exe"
          md5: "22222222222222222222222222222222"
          size: 1002
    - id: linux
      label: "Linux"
footer:
  note: "kept as is"
CATALOG
  cp "$CATALOG" "${CATALOG}.orig"
}

edit() {
  run python3 "$EDITOR_PY" --catalog "$CATALOG" --file-url "https://example.invalid/agent-new.exe" --md5 "$MD5" --size 5000 "$@"
}

# lines of one list of the windows target
list() {
  awk -v name="      $1:" '$0 == name {on = 1; next} on && /^      [a-z_]+:$/ {on = 0} on && /^    - id:/ {on = 0} on' "$CATALOG"
}

@test "a new build replaces the featured entry of its train and joins the history" {
  edit --version 26.10.2
  [ "$status" -eq 0 ]
  [[ "$output" == *"all_versions: inserted, downloads: replaced 26.10.1"* ]]
  [[ "$output" == *"featured_count=2"* ]]
  run list downloads
  [ "$(grep -c -- '- version:' <<< "$output")" -eq 2 ]
  [[ "$output" == *'- version: "26.10.2"'* ]]
  [[ "$output" != *'- version: "26.10.1"'* ]]
  [[ "$output" == *'- version: "25.10.8"'* ]]
  run list all_versions
  [ "$(grep -c -- '- version:' <<< "$output")" -eq 3 ]
  [ "$(grep -- '- version:' <<< "$output" | head -1 | tr -d ' ')" = '-version:"26.10.2"' ]
  [[ "$output" == *'- version: "26.10.1"'* ]]
}

@test "only the two lists of the windows target change" {
  edit --version 26.10.2
  [ "$status" -eq 0 ]
  run diff <(grep -v -e "26.10.1" -e "26.10.2" -e "agent-new" -e "$MD5" -e "11111111111111111111111111111111" -e "size: 1001" -e "size: 5000" "${CATALOG}.orig") \
    <(grep -v -e "26.10.1" -e "26.10.2" -e "agent-new" -e "$MD5" -e "11111111111111111111111111111111" -e "size: 1001" -e "size: 5000" "$CATALOG")
  [ "$status" -eq 0 ]
  grep -q 'note: "kept as is"' "$CATALOG"
  grep -q '    - id: linux' "$CATALOG"
}

@test "running again with the same build changes nothing" {
  edit --version 26.10.2
  cp "$CATALOG" "${CATALOG}.first"
  edit --version 26.10.2
  [ "$status" -eq 0 ]
  [[ "$output" == *"all_versions: unchanged, downloads: unchanged"* ]]
  cmp "$CATALOG" "${CATALOG}.first"
}

@test "republishing a version with another file replaces it in place" {
  edit --version 26.10.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"all_versions: replaced 26.10.1, downloads: replaced 26.10.1"* ]]
  run list all_versions
  [ "$(grep -c -- '- version:' <<< "$output")" -eq 2 ]
  [[ "$output" == *"md5: \"${MD5}\""* ]]
}

@test "a build of a new train is featured in addition and flagged" {
  edit --version 27.04.0
  [ "$status" -eq 0 ]
  [[ "$output" == *"downloads: inserted"* ]]
  [[ "$output" == *"::warning::"*"3 featured entries"* ]]
  [[ "$output" == *"featured_count=3"* ]]
  [[ "$output" == *"featured_added=true"* ]]
}

@test "a build of a featured train raises no warning, whatever the number of trains" {
  edit --version 27.04.0
  edit --version 27.04.1
  [ "$status" -eq 0 ]
  [[ "$output" == *"downloads: replaced 27.04.0"* ]]
  [[ "$output" != *"::warning::"* ]]
  [[ "$output" == *"featured_count=3"* ]]
  [[ "$output" == *"featured_added=false"* ]]
}

@test "malformed values are rejected and the file is left alone" {
  edit --version 26.10
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must be MAJOR.MINOR.PATCH"* ]]
  run python3 "$EDITOR_PY" --catalog "$CATALOG" --version 26.10.2 --file-url u --md5 NOPE --size 5
  [ "$status" -ne 0 ]
  [[ "$output" == *"md5 must be 32 lowercase hex chars"* ]]
  run python3 "$EDITOR_PY" --catalog "$CATALOG" --version 26.10.2 --file-url u --md5 "$MD5" --size 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"size must be a positive integer"* ]]
  cmp "$CATALOG" "${CATALOG}.orig"
}

@test "a catalog without the expected block is refused and left alone" {
  sed -i 's/^    - id: windows$/    - id: win/' "$CATALOG"
  cp "$CATALOG" "${CATALOG}.before"
  edit --version 26.10.2
  [ "$status" -ne 0 ]
  [[ "$output" == *"no \`- id: windows\` target"* ]]
  cmp "$CATALOG" "${CATALOG}.before"

  cp "${CATALOG}.orig" "$CATALOG"
  sed -i '/^agent:$/d' "$CATALOG"
  edit --version 26.10.2
  [ "$status" -ne 0 ]
  [[ "$output" == *"no top-level \`agent:\` key"* ]]
}

@test "an entry carrying a field the editor does not render is not replaced" {
  sed -i '0,/          size: 1001/s//          size: 1001\n          signature: "abc"/' "$CATALOG"
  cp "$CATALOG" "${CATALOG}.before"
  edit --version 26.10.2
  [ "$status" -ne 0 ]
  [[ "$output" == *"carries \`signature\`"* ]]
  cmp "$CATALOG" "${CATALOG}.before"
}

@test "a comment inside the replaced entry does not orphan its fields" {
  sed -i '0,/          file_url: "https:\/\/example.invalid\/agent-26.10.1.exe"/s//          file_url: "https:\/\/example.invalid\/agent-26.10.1.exe"\n          # checked by hand/' "$CATALOG"
  edit --version 26.10.2
  [ "$status" -eq 0 ]
  run list downloads
  [ "$(grep -c 'md5:' <<< "$output")" -eq 2 ]
  [[ "$output" != *"11111111111111111111111111111111"* ]]
}
