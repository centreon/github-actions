#!/usr/bin/env bats
# Publication to the download site: entry checks, release files, agent catalog,
# sidecars, and what reaches the site repository.

load site-fixture

setup() {
  site_fixture
  ENTRIES="${BATS_TEST_TMPDIR}/entries.tsv"
  entry centreon-web 26.10 stable "" 26.10.3 centreon-web-26.10.3.tar.gz 2026-11-26 "$MD5_A" 68000000 > "$ENTRIES"
  ARGS=(--entries "$ENTRIES" --out-name 26.10.3.yaml --branch release/test --commit-message "release: test" --pr-title "release: test")
  WEB_FILE=src/data/releases/packages/26.10/26.10.3.yaml
}

# ---- arguments and entries, before anything is cloned ----------------------

@test "a missing or malformed site repository is rejected" {
  TEST_REPO="" publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"WEBAPP_REPO must name the target repository"* ]]
  TEST_REPO="https://example.invalid/x" publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [ ! -e "${CALLS}/gh" ]
}

@test "required options are reported" {
  publish --entries "$ENTRIES" --out-name a.yaml --commit-message m --pr-title t
  [ "$status" -ne 0 ]
  [[ "$output" == *"--branch is required"* ]]
  publish --branch b --commit-message m --pr-title t
  [ "$status" -ne 0 ]
  [[ "$output" == *"--entries is required"* ]]
}

@test "an output name outside the release directory is rejected" {
  publish --entries "$ENTRIES" --out-name ../evil.yaml --branch b --commit-message m --pr-title t
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a bare filename"* ]]
  entry centreon-web 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 10 "" ../../catalog.yaml > "$ENTRIES"
  publish --entries "$ENTRIES" --branch b --commit-message m --pr-title t
  [ "$status" -ne 0 ]
  [[ "$output" == *"out_name must be a bare filename"* ]]
}

@test "malformed entries are rejected with their line" {
  entry centreon-web 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 > "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"line 1: expected 9 to 11 tab-separated columns"* ]]

  entry centreon-web 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 NOTANMD5 10 > "$ENTRIES"
  publish "${ARGS[@]}"
  [[ "$output" == *"md5 must be 32 lowercase hex chars"* ]]

  entry centreon-web 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 0 > "$ENTRIES"
  publish "${ARGS[@]}"
  [[ "$output" == *"refusing to publish an empty artifact"* ]]

  entry centreon-web 26.10 stable "" 26.10.3 f.tar.gz 26/11/2026 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}"
  [[ "$output" == *"date must be YYYY-MM-DD"* ]]

  entry centreon-web 26.10 nightly "" 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}"
  [[ "$output" == *"state must be stable, rc or beta"* ]]
}

@test "a value that could break out of its yaml scalar is rejected" {
  entry centreon-web 26.10 stable "" 26.10.3 'f".tar.gz' 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"file must not contain a quote or a backslash"* ]]
  entry centreon-web 26.10 stable 'el9\' 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}"
  [[ "$output" == *"os must not contain a quote or a backslash"* ]]
}

@test "entries of two trains are rejected" {
  entry centreon-gorgone 25.10 stable "" 25.10.9 g.tar.gz 2026-11-26 "$MD5_B" 10 >> "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"all entries must share one train"* ]]
}

@test "an empty entries file is rejected" {
  printf '# only a comment\n\n' > "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no entries found"* ]]
}

# ---- catalog checks ---------------------------------------------------------

@test "a train or a product the catalog does not declare is rejected" {
  entry centreon-web 27.04 stable "" 27.04.0 f.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"train '27.04' is not declared"* ]]

  entry centreon-nope 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"product 'centreon-nope' is not declared"* ]]
}

@test "a product group without a known directory is rejected" {
  entry centreon-unknown-group 26.10 stable "" 26.10.3 f.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"unhandled product group 'elsewhere'"* ]]
}

@test "each product goes to the directory of its group" {
  entry centreon-vm 26.10 stable alma9 26.10-20261100.alma9 vm.ova 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrote src/data/releases/appliances/26.10/26.10.3.yaml"* ]]

  entry centreon-widget 26.10 stable "" 26.10.3 w.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [[ "$output" == *"wrote src/data/releases/widgets/26.10/26.10.3.yaml"* ]]
}

@test "one output name cannot hold products of two groups" {
  entry centreon-widget 26.10 stable "" 26.10.3 w.tar.gz 2026-11-26 "$MD5_B" 10 >> "$ENTRIES"
  publish "${ARGS[@]}" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not share a product group"* ]]
}

# ---- dry run ----------------------------------------------------------------

@test "a dry run validates and pushes nothing" {
  publish "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"wrote ${WEB_FILE} (1 entry(ies))"* ]]
  [[ "$output" == *"Catalogue valide"* ]]
  [[ "$output" == *"dry run complete, nothing pushed"* ]]
  refute site_has_branch release/test
  [ ! -e "${CALLS}/gh" ]
  [ ! -e "${CALLS}/aws" ]
}

@test "a dry run needs no token" {
  TEST_TOKEN="" publish "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
}

@test "a failing validation stops before any push" {
  NODE_FAIL=1 publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pnpm validate failed - nothing was pushed"* ]]
  refute site_has_branch release/test
  [ ! -e "${CALLS}/gh" ]
}

@test "a pnpm older than the site needs is refused" {
  PNPM_VERSION=10.4.1 publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pnpm 10 is older than the required 11"* ]]
  refute site_has_branch release/test
}

@test "the validator installs from the lockfile without scripts nor token" {
  publish "${ARGS[@]}" --dry-run
  [ "$status" -eq 0 ]
  grep -q -- "install --frozen-lockfile --ignore-scripts" "${CALLS}/pnpm"
  grep -q -- "--config.minimumReleaseAge=2880" "${CALLS}/pnpm"
}

# ---- what is published --------------------------------------------------------

@test "the entries are pushed on the branch and a pull request is opened" {
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  site_has_branch release/test
  run site_file release/test "$WEB_FILE"
  [[ "$output" == *'- product: "centreon-web"'* ]]
  [[ "$output" == *'  file: "centreon-web-26.10.3.tar.gz"'* ]]
  [[ "$output" == *"  md5: \"${MD5_A}\""* ]]
  [[ "$output" == *"  size: 68000000"* ]]
  [[ "$output" == *"  enabled: true"* ]]
  grep -q "pr create --repo ${SITE_REPO} --base develop --head release/test --title release: test" "${CALLS}/gh"
  grep -q "pr edit https://github.com/${SITE_REPO}/pull/7 --add-label release" "${CALLS}/gh"
}

@test "the commit only touches the written files and carries the token's identity" {
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  run "$REAL_GIT" --git-dir "$BARE" diff --name-only develop release/test
  [ "$output" = "$WEB_FILE" ]
  run "$REAL_GIT" --git-dir "$BARE" log -1 --format='%an <%ae> %s' release/test
  [ "$output" = "test-bot <4242+test-bot@users.noreply.github.com> release: test" ]
}

@test "a token that cannot read its user commits as the actions bot" {
  GH_NO_USER=1 publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  run "$REAL_GIT" --git-dir "$BARE" log -1 --format='%an' release/test
  [ "$output" = "github-actions[bot]" ]
}

@test "the token is never printed" {
  TEST_TOKEN="very-secret-placeholder" publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"very-secret-placeholder"* ]]
  [[ "$output" != *"$(printf 'x-access-token:%s' very-secret-placeholder | base64 -w0)"* ]]
}

@test "publishing without a token fails before the push" {
  TEST_TOKEN="" publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GH_TOKEN is required"* ]]
  refute site_has_branch release/test
}

@test "an empty label skips the labelling and a refused label does not fail" {
  publish "${ARGS[@]}" --pr-label ""
  [ "$status" -eq 0 ]
  refute grep -q "pr edit" "${CALLS}/gh"

  GH_LABEL_EXIT=1 publish "${ARGS[@]}" --branch release/other
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not apply label 'release'"* ]]
}

@test "a release spanning several files writes each of them" {
  entry centreon-web 26.10 stable "" 26.10.3 centreon-web-26.10.3.tar.gz 2026-11-26 "$MD5_A" 10 "" 26.10.3.yaml > "$ENTRIES"
  entry centreon-gorgone 26.10 stable "" 26.10.1 centreon-gorgone-26.10.1.tar.gz 2026-11-26 "$MD5_B" 20 "" 26.10.1.yaml >> "$ENTRIES"
  entry centreon-widget 26.10 stable "" 26.10.3 centreon-widget-26.10.3.tar.gz 2026-11-26 "$MD5_B" 30 "" 26.10.3.yaml >> "$ENTRIES"
  publish --entries "$ENTRIES" --branch release/test --commit-message m --pr-title t
  [ "$status" -eq 0 ]
  run "$REAL_GIT" --git-dir "$BARE" diff --name-only develop release/test
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"src/data/releases/packages/26.10/26.10.1.yaml"* ]]
  [[ "$output" == *"src/data/releases/packages/26.10/26.10.3.yaml"* ]]
  [[ "$output" == *"src/data/releases/widgets/26.10/26.10.3.yaml"* ]]
}

@test "an existing file keeps its other entries and replaces the same one" {
  entry centreon-web 26.10 stable "" 26.10.2 centreon-web-26.10.2.tar.gz 2026-11-26 "$MD5_A" 10 > "$ENTRIES"
  entry centreon-gorgone 26.10 stable "" 26.10.2 centreon-gorgone-26.10.2.tar.gz 2026-11-26 "$MD5_B" 999 >> "$ENTRIES"
  publish --entries "$ENTRIES" --out-name 26.10.2.yaml --branch release/test --commit-message m --pr-title t
  [ "$status" -eq 0 ]
  [[ "$output" == *"merging into an existing 26.10.2.yaml (0 entry(ies) kept)"* ]]
  run site_file release/test src/data/releases/packages/26.10/26.10.2.yaml
  [ "$(grep -c '^- product:' <<< "$output")" -eq 2 ]
  # the gorgone row of the seed is replaced, not duplicated
  [[ "$output" == *"  size: 999"* ]]
  [[ "$output" != *"  size: 300"* ]]
  # sorted by product
  [ "$(grep '^- product:' <<< "$output" | head -1)" = '- product: "centreon-gorgone"' ]
}

@test "an existing entry of another version is kept" {
  entry centreon-gorgone 26.10 stable "" 26.10.3 centreon-gorgone-26.10.3.tar.gz 2026-11-26 "$MD5_B" 10 > "$ENTRIES"
  publish --entries "$ENTRIES" --out-name 26.10.2.yaml --branch release/test --commit-message m --pr-title t
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1 entry(ies) kept)"* ]]
  run site_file release/test src/data/releases/packages/26.10/26.10.2.yaml
  [ "$(grep -c '^- product:' <<< "$output")" -eq 2 ]
  [[ "$output" == *"  size: 300"* ]]
}

@test "two entries with the same identity are rejected" {
  entry centreon-web 26.10 stable "" 26.10.3 other-name.tar.gz 2026-11-26 "$MD5_B" 20 >> "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"two entries render to the same key"* ]]
  refute site_has_branch release/test
}

@test "a second run completes the branch and the pull request of the first" {
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  echo "https://github.com/${SITE_REPO}/pull/7" > "${CALLS}/existing-pr"
  : > "${CALLS}/gh"

  entry centreon-gorgone 26.10 stable "" 26.10.3 centreon-gorgone-26.10.3.tar.gz 2026-11-26 "$MD5_B" 20 > "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reusing existing branch release/test"* ]]
  [[ "$output" == *"updated existing https://github.com/${SITE_REPO}/pull/7"* ]]
  refute grep -q "pr create" "${CALLS}/gh"
  run site_file release/test "$WEB_FILE"
  [ "$(grep -c '^- product:' <<< "$output")" -eq 2 ]
  run "$REAL_GIT" --git-dir "$BARE" rev-list --count develop..release/test
  [ "$output" -eq 2 ]
}

@test "running again with the same entries changes nothing" {
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  : > "${CALLS}/gh"
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no change to commit"* ]]
  refute grep -q "pr create" "${CALLS}/gh"
  run "$REAL_GIT" --git-dir "$BARE" rev-list --count develop..release/test
  [ "$output" -eq 1 ]
}

@test "a file rewritten by the site's own code after validation is not pushed" {
  TAMPER="$WEB_FILE" publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"was committed with content the run did not validate"* ]]
  refute site_has_branch release/test
  refute grep -q "pr create" "${CALLS}/gh"
}

@test "a file the site's own code adds is not pushed" {
  TAMPER="src/data/extra.yaml" publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  run "$REAL_GIT" --git-dir "$BARE" diff --name-only develop release/test
  [ "$output" = "$WEB_FILE" ]
}

@test "a file the site's own code stages is not pushed" {
  STAGE="src/data/extra.yaml" publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"the commit touches files this run did not write"* ]]
  refute site_has_branch release/test
}

@test "a git hook of the site repository does not run" {
  # a clone never carries hooks; this one would come from the validator's side effects
  cat > "${BIN}/node" << STUB
#!/bin/sh
mkdir -p ../site-repository/.git/hooks
printf '#!/bin/sh\ntouch "${CALLS}/hook-ran"\n' > ../site-repository/.git/hooks/pre-commit
chmod +x ../site-repository/.git/hooks/pre-commit
echo "✔ Catalogue valide (1 entrée)"
STUB
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ ! -e "${CALLS}/hook-ran" ]
}

@test "a url rewrite in the git configuration blocks the push" {
  "$REAL_GIT" config --global url.https://example.invalid/.insteadOf https://other.invalid/
  publish "${ARGS[@]}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"transport configuration this run did not set"* ]]
  refute site_has_branch release/test
}

# ---- monitoring agent ---------------------------------------------------------

@test "the agent options feature the build in the catalog, in the same commit" {
  entry centreon-monitoring-agent 26.10 stable "" 26.10.2 agent-26.10.2.exe 2026-11-26 "$MD5_A" 5000 > "$ENTRIES"
  publish --entries "$ENTRIES" --out-name 26.10.2.yaml --branch release/cma --commit-message m --pr-title t \
    --agent-version 26.10.2 --agent-file-url https://example.invalid/agent-26.10.2.exe --agent-md5 "$MD5_A" --agent-size 5000
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated src/data/catalog.yaml"* ]]
  run "$REAL_GIT" --git-dir "$BARE" diff --name-only develop release/cma
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"src/data/catalog.yaml"* ]]
  [[ "$output" == *"src/data/releases/agent/26.10/26.10.2.yaml"* ]]
  run site_file release/cma src/data/catalog.yaml
  [[ "$output" == *'file_url: "https://example.invalid/agent-26.10.2.exe"'* ]]
  # the other train stays featured, the rest of the file is untouched
  [[ "$output" == *'- version: "25.10.8"'* ]]
  [[ "$output" == *'note: "kept as is"'* ]]
}

@test "without agent options the catalog is left alone" {
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent catalog | not edited"* ]]
  run "$REAL_GIT" --git-dir "$BARE" diff --name-only develop release/test
  [[ "$output" != *"catalog.yaml"* ]]
}

@test "an agent version without its file details is rejected" {
  publish "${ARGS[@]}" --agent-version 26.10.2 --agent-md5 "$MD5_A"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--agent-version needs --agent-file-url, --agent-md5 and --agent-size"* ]]
  refute site_has_branch release/test
}

@test "a third featured agent train is flagged for the reviewer" {
  entry centreon-monitoring-agent 26.10 stable "" 26.10.2 a.exe 2026-11-26 "$MD5_A" 5000 > "$ENTRIES"
  publish --entries "$ENTRIES" --out-name x.yaml --branch release/cma --commit-message m --pr-title t --dry-run \
    --agent-version 27.04.0 --agent-file-url https://example.invalid/a.exe --agent-md5 "$MD5_A" --agent-size 5000
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 featured entries, one more than before: review before merging"* ]]
}

@test "an agent build of a featured train is not flagged" {
  entry centreon-monitoring-agent 26.10 stable "" 26.10.2 a.exe 2026-11-26 "$MD5_A" 5000 > "$ENTRIES"
  publish --entries "$ENTRIES" --out-name x.yaml --branch release/cma --commit-message m --pr-title t --dry-run \
    --agent-version 26.10.2 --agent-file-url https://example.invalid/a.exe --agent-md5 "$MD5_A" --agent-size 5000
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent catalog | catalog.yaml 26.10.2: all_versions: inserted, downloads: replaced 26.10.1 |"* ]]
  [[ "$output" != *"review before merging"* ]]
}

# ---- sidecars -------------------------------------------------------------------

@test "no sidecar is uploaded unless asked, even with an s3 uri" {
  entry centreon-vm 26.10 stable alma9 26.10-1.alma9 vm.ova 2026-11-26 "$MD5_A" 10 s3://some-bucket/vm/vm.ova > "$ENTRIES"
  publish "${ARGS[@]}"
  [ "$status" -eq 0 ]
  [ ! -e "${CALLS}/aws" ]
}

@test "a sidecar is uploaded next to each artifact that has an s3 uri" {
  entry centreon-vm 26.10 stable alma9 26.10-1.alma9 vm-alma9.ova 2026-11-26 "$MD5_A" 10 s3://some-bucket/vm/vm-alma9.ova > "$ENTRIES"
  entry centreon-vm 26.10 stable debian12 26.10-1.debian12 vm-debian12.ova 2026-11-26 "$MD5_B" 20 >> "$ENTRIES"
  publish "${ARGS[@]}" --sidecar
  [ "$status" -eq 0 ]
  [ "$(wc -l < "${CALLS}/aws")" -eq 1 ]
  grep -q "s3://some-bucket/vm/vm-alma9.ova.yaml --no-progress" "${CALLS}/aws"
  [[ "$output" == *"no s3_uri for vm-debian12.ova, sidecar skipped"* ]]
  run cat "${CALLS}/sidecar-vm-alma9.ova.yaml"
  [[ "$output" == *'product: "centreon-vm"'* ]]
  [[ "$output" == *'os: "alma9"'* ]]
  [[ "$output" == *"md5: \"${MD5_A}\""* ]]
  [[ "$output" == *"size: 10"* ]]
}

@test "a dry run shows the sidecar and uploads nothing" {
  entry centreon-vm 26.10 stable alma9 26.10-1.alma9 vm.ova 2026-11-26 "$MD5_A" 10 s3://some-bucket/vm/vm.ova > "$ENTRIES"
  publish "${ARGS[@]}" --sidecar --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would upload sidecar to s3://some-bucket/vm/vm.ova.yaml"* ]]
  [ ! -e "${CALLS}/aws" ]
}

@test "a failed sidecar upload stops before the push" {
  entry centreon-vm 26.10 stable alma9 26.10-1.alma9 vm.ova 2026-11-26 "$MD5_A" 10 s3://some-bucket/vm/vm.ova > "$ENTRIES"
  AWS_EXIT=1 publish "${ARGS[@]}" --sidecar
  [ "$status" -ne 0 ]
  refute site_has_branch release/test
}

@test "an s3 uri that is not one is rejected" {
  entry centreon-vm 26.10 stable alma9 26.10-1.alma9 vm.ova 2026-11-26 "$MD5_A" 10 "https://example.invalid/vm.ova" > "$ENTRIES"
  publish "${ARGS[@]}" --sidecar
  [ "$status" -ne 0 ]
  [[ "$output" == *"s3_uri must be an s3://bucket/key uri"* ]]
}
