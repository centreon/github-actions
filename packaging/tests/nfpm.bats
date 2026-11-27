#!/usr/bin/env bats

# package.sh runs in a small repository, with a stand-in of nfpm that records what it is
# given: the variables a configuration reads, the configuration and the signing key.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../nfpm/package.sh"
  ROOT="${BATS_TEST_TMPDIR}/repository"
  BIN="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export RUNNER_TEMP="${BATS_TEST_TMPDIR}/runner-temp"
  mkdir -p "${ROOT}/packaging/scripts" "$BIN" "$CALLS" "$RUNNER_TEMP"

  cat > "${BIN}/nfpm" << STUB
#!/usr/bin/env bash
set -euo pipefail
while ((\$# > 0)); do
  case \$1 in
    --config) config=\$2; shift 2 ;;
    --packager) packager=\$2; shift 2 ;;
    *) shift ;;
  esac
done
out="${CALLS}/\${config%.yaml}"
mkdir "\$out"
for name in VERSION RELEASE ARCH DIST MAJOR_VERSION NEXT_MAJOR_VERSION APACHE_USER RPM_SIGNING_KEY_ID \
  NFPM_RPM_PASSPHRASE PHP_MIN_VERSION; do
  printf '%s=%s\n' "\$name" "\${!name-unset}"
done > "\${out}/env"
echo "\$RPM_SIGNING_KEY_FILE" > "\${out}/key-path"
cat "\$RPM_SIGNING_KEY_FILE" > "\${out}/key"
cp "\$config" "\${out}/config"
touch "\${config%.yaml}.\${packager}"
STUB
  chmod +x "${BIN}/nfpm"

  cat > "${ROOT}/packaging/web.yaml" << 'CONFIG'
name: "centreon-web"
license: "Apache-2.0"
version: "${VERSION}"
commit: "@COMMIT_HASH@"
owner: "@APACHE_USER@:@APACHE_GROUP@"
contents:
  - src: ./files
    dst: /usr/share/centreon
rpm:
  summary: web
  signature:
    key_file: ${RPM_SIGNING_KEY_FILE}
    key_id: ${RPM_SIGNING_KEY_ID}
CONFIG
  echo "apache license" > "${ROOT}/copyright.Apache-2.0"
  echo "repository license" > "${ROOT}/LICENSE.md"
  echo 'php @PHP_MIN_VERSION@' > "${ROOT}/packaging/scripts/postinstall.sh"
}

# runs package.sh for a distribution, with the given NAME=value variables
package() {
  local distrib=$1 extension separator name
  shift
  case "$distrib" in
    el9) extension=rpm separator=. name=el9 ;;
    bookworm) extension=deb separator=+ name=deb12u1 ;;
    noble) extension=deb separator=- name=0ubuntu.24.04 ;;
  esac
  cd "$ROOT"
  run env PATH="${BIN}:${PATH}" NFPM_FILE_PATTERN="packaging/*.yaml" COMMIT_HASH=abc123 DISTRIB="$distrib" \
    PACKAGE_EXTENSION="$extension" PACKAGE_DISTRIB_SEPARATOR="$separator" PACKAGE_DISTRIB_NAME="$name" \
    INPUT_VERSION=1.2.3 INPUT_RELEASE=7 INPUT_ARCH=all RPM_GPG_KEY=the-key RPM_GPG_SIGNING_KEY_ID=key-id \
    RPM_GPG_SIGNING_PASSPHRASE=secret "$@" "$SCRIPT"
}

# a variable nfpm was given for a configuration
given() {
  sed -n "s/^$2=//p" "${CALLS}/$1/env"
}

# "! command" does not fail a bats test unless it is its last line: assert it
refute() {
  if "$@"; then
    echo "unexpectedly succeeded: $*"
    return 1
  fi
}

@test "an rpm carries the distribution in DIST and lands in the working directory" {
  package el9
  [ "$status" -eq 0 ]
  [ "$(given web VERSION)" = "1.2.3" ]
  [ "$(given web RELEASE)" = "7" ]
  [ "$(given web DIST)" = ".el9" ]
  [ "$(given web ARCH)" = "all" ]
  [ "$(given web APACHE_USER)" = "apache" ]
  [ -f "${ROOT}/web.rpm" ]
  [ ! -e "${ROOT}/packaging/web.rpm" ]
}

@test "a deb carries the distribution in its release" {
  package bookworm
  [ "$status" -eq 0 ]
  [ "$(given web RELEASE)" = "7+deb12u1" ]
  [ "$(given web DIST)" = "" ]
  [ "$(given web APACHE_USER)" = "www-data" ]
  [ -f "${ROOT}/web.deb" ]
  rm -r "${CALLS}/web"
  package noble
  [ "$(given web RELEASE)" = "7-0ubuntu.24.04" ]
}

@test "deb_release replaces the release of a deb only" {
  package bookworm DEB_RELEASE=1
  [ "$(given web RELEASE)" = "1+deb12u1" ]
  rm -r "${CALLS}/web"
  package el9 DEB_RELEASE=1
  [ "$(given web RELEASE)" = "7" ]
}

@test "deb_release_suffix replaces the suffix of a deb only" {
  package bookworm DEB_RELEASE_SUFFIX="~bookworm"
  [ "$(given web RELEASE)" = "7~bookworm" ]
  rm -r "${CALLS}/web"
  package el9 DEB_RELEASE_SUFFIX="~bookworm"
  [ "$(given web RELEASE)" = "7" ]
  [ "$(given web DIST)" = ".el9" ]
}

@test "the version is made of the major and minor versions when it is not given" {
  package el9 INPUT_VERSION= INPUT_MAJOR_VERSION=26.10 INPUT_MINOR_VERSION=4
  [ "$status" -eq 0 ]
  [ "$(given web VERSION)" = "26.10.4" ]
  [ "$(given web MAJOR_VERSION)" = "26.10" ]
}

@test "neither version nor major version fails" {
  package el9 INPUT_VERSION=
  [ "$status" -ne 0 ]
  [[ "$output" == *"give either version or major_version"* ]]
  [ ! -d "${CALLS}/web" ]
}

@test "without a major version the next one is not set" {
  package el9
  [ "$(given web MAJOR_VERSION)" = "unset" ]
  [ "$(given web NEXT_MAJOR_VERSION)" = "unset" ]
}

@test "the next major version is the next month since 26.10" {
  package el9 INPUT_MAJOR_VERSION=26.10
  [ "$(given web NEXT_MAJOR_VERSION)" = "26.11" ]
  rm -r "${CALLS}/web"
  package el9 INPUT_MAJOR_VERSION=26.12
  [ "$(given web NEXT_MAJOR_VERSION)" = "27.01" ]
  rm -r "${CALLS}/web"
  package el9 INPUT_MAJOR_VERSION=27.08
  [ "$(given web NEXT_MAJOR_VERSION)" = "27.9" ]
}

@test "the next major version is six months later before 26.10" {
  package el9 INPUT_MAJOR_VERSION=24.04
  [ "$(given web NEXT_MAJOR_VERSION)" = "24.10" ]
  rm -r "${CALLS}/web"
  package el9 INPUT_MAJOR_VERSION=24.10
  [ "$(given web NEXT_MAJOR_VERSION)" = "25.04" ]
  rm -r "${CALLS}/web"
  package el9 INPUT_MAJOR_VERSION=25.10
  [ "$(given web NEXT_MAJOR_VERSION)" = "26.04" ]
}

@test "a malformed major version fails" {
  package el9 INPUT_MAJOR_VERSION=next
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not YY.MM"* ]]
  [ ! -d "${CALLS}/web" ]
}

@test "the variables of the job reach the configurations" {
  package el9 PHP_MIN_VERSION=8.4
  [ "$(given web PHP_MIN_VERSION)" = "8.4" ]
}

@test "the commit hash and the web server user are written in the configuration" {
  package el9
  grep -q '^commit: "abc123"$' "${CALLS}/web/config"
  grep -q '^owner: "apache:apache"$' "${CALLS}/web/config"
}

@test "placeholders are replaced in the configuration, not in the other files" {
  echo 'lua: "@luaver@ @PHP_MIN_VERSION@"' >> "${ROOT}/packaging/web.yaml"
  package el9 PLACEHOLDERS=$'luaver=5.4\n\n  PHP_MIN_VERSION=8.4  '
  [ "$status" -eq 0 ]
  grep -q '^lua: "5.4 8.4"$' "${CALLS}/web/config"
  [ "$(cat "${ROOT}/packaging/scripts/postinstall.sh")" = 'php @PHP_MIN_VERSION@' ]
}

@test "a placeholder value is written as is, whatever its characters" {
  echo 'path: "@INSTALL_PATH@"' >> "${ROOT}/packaging/web.yaml"
  package el9 PLACEHOLDERS='INSTALL_PATH=/usr/share/a&b\c=d'
  [ "$status" -eq 0 ]
  grep -qF 'path: "/usr/share/a&b\c=d"' "${CALLS}/web/config"
}

@test "a malformed placeholder line fails before anything is built" {
  package el9 PLACEHOLDERS="not a pair"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a NAME=value line"* ]]
  [ ! -d "${CALLS}/web" ]
}

@test "a placeholder left in the configuration fails before nfpm runs" {
  echo 'left: "@NOT_REPLACED@"' >> "${ROOT}/packaging/web.yaml"
  package el9
  [ "$status" -ne 0 ]
  [[ "$output" == *"unsubstituted placeholder"* ]]
  [ ! -d "${CALLS}/web" ]
}

@test "the signing key is given to nfpm from outside the workspace and removed" {
  package el9
  [ "$status" -eq 0 ]
  [ "$(cat "${CALLS}/web/key")" = "the-key" ]
  [ "$(given web RPM_SIGNING_KEY_ID)" = "key-id" ]
  [ "$(given web NFPM_RPM_PASSPHRASE)" = "secret" ]
  [[ "$(cat "${CALLS}/web/key-path")" == "${RUNNER_TEMP}/"* ]]
  [ ! -e "$(cat "${CALLS}/web/key-path")" ]
  refute grep -rq "the-key" "$ROOT"
  grep -q "signature:" "${CALLS}/web/config"
}

@test "the signing key is removed when the build fails" {
  printf '#!/bin/sh\necho "$RPM_SIGNING_KEY_FILE" > "%s/key-path"\nexit 3\n' "$CALLS" > "${BIN}/nfpm"
  package el9
  [ "$status" -eq 3 ]
  [ ! -e "$(cat "${CALLS}/key-path")" ]
}

@test "without a key identifier the signature is removed from the configuration" {
  package el9 RPM_GPG_KEY= RPM_GPG_SIGNING_KEY_ID=
  [ "$status" -eq 0 ]
  refute grep -q "signature:\|RPM_SIGNING_KEY" "${CALLS}/web/config"
  grep -q "^  summary: web$" "${CALLS}/web/config"
}

@test "deb_copyright adds the license matching the package to a deb" {
  package bookworm DEB_COPYRIGHT=true
  [ "$status" -eq 0 ]
  [ "$(cat "${ROOT}/packaging/copyright")" = "apache license" ]
  # the entry closes the contents list, before the next key
  run grep -n -A3 "dst: /usr/share/centreon" "${CALLS}/web/config"
  [[ "$output" == *"- src: ./copyright"*"dst: /usr/share/doc/centreon-web/copyright"*"packager: deb"* ]]
  grep -q "^rpm:$" "${CALLS}/web/config"
}

@test "deb_copyright falls back to the license of the repository" {
  rm "${ROOT}/copyright.Apache-2.0"
  package bookworm DEB_COPYRIGHT=true
  [ "$(cat "${ROOT}/packaging/copyright")" = "repository license" ]
}

@test "deb_copyright opens a contents list when the configuration has none" {
  printf 'name: plain\ncommit: "@COMMIT_HASH@"\n' > "${ROOT}/packaging/web.yaml"
  package bookworm DEB_COPYRIGHT=true
  [ "$status" -eq 0 ]
  [ "$(tail -n 4 "${CALLS}/web/config" | head -n 2)" = $'contents:\n  - src: ./copyright' ]
  grep -q "dst: /usr/share/doc/plain/copyright" "${CALLS}/web/config"
}

@test "no copyright is added to an rpm, nor to a deb by default" {
  package el9 DEB_COPYRIGHT=true
  refute grep -q "copyright" "${CALLS}/web/config"
  rm -r "${CALLS}/web"
  package bookworm
  refute grep -q "copyright" "${CALLS}/web/config"
  [ ! -e "${ROOT}/packaging/copyright" ]
}

@test "every configuration of every pattern is built" {
  mkdir "${ROOT}/other"
  printf 'name: one\ncommit: "@COMMIT_HASH@"\n' > "${ROOT}/packaging/one.yaml"
  printf 'name: two\ncommit: "@COMMIT_HASH@"\n' > "${ROOT}/other/two.yaml"
  package el9 NFPM_FILE_PATTERN="packaging/*.yaml other/two.yaml"
  [ "$status" -eq 0 ]
  [ -f "${ROOT}/web.rpm" ] && [ -f "${ROOT}/one.rpm" ] && [ -f "${ROOT}/two.rpm" ]
  grep -q '^commit: "abc123"$' "${CALLS}/two/config"
}

@test "a configuration of the working directory itself is built in place" {
  printf 'name: top\ncommit: "@COMMIT_HASH@"\n' > "${ROOT}/top.yaml"
  package el9 NFPM_FILE_PATTERN="top.yaml"
  [ "$status" -eq 0 ]
  [ -f "${ROOT}/top.rpm" ]
}

@test "a pattern matching nothing fails" {
  package el9 NFPM_FILE_PATTERN="nowhere/*.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no nfpm configuration matches"* ]]
}

@test "an empty commit hash or pattern fails" {
  package el9 COMMIT_HASH=
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit_hash input is empty"* ]]
  package el9 NFPM_FILE_PATTERN=
  [ "$status" -ne 0 ]
  [ ! -d "${CALLS}/web" ]
}

