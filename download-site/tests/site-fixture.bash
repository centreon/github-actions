# Shared setup of the publication tests: a local stand-in of the site repository,
# the real git redirected to it, and stand-ins for gh, pnpm, node, ldconfig and aws.

SITE_REPO="test-org/site"
SITE_URL="https://github.com/${SITE_REPO}.git"
MD5_A="0123456789abcdef0123456789abcdef"
MD5_B="fedcba9876543210fedcba9876543210"

site_fixture() {
  PUBLISH="${BATS_TEST_DIRNAME}/../publication/publish.sh"
  BIN="${BATS_TEST_TMPDIR}/bin"
  BARE="${BATS_TEST_TMPDIR}/site.git"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$BIN" "$CALLS" "$HOME"
  REAL_GIT="$(command -v git)"

  # the real git, with the site url served by the local repository. "config --list"
  # is passed through untouched: the script inspects it for unexpected url rewrites.
  cat > "${BIN}/git" << STUB
#!/bin/sh
case " \$* " in
  *" config --list "*) exec "${REAL_GIT}" "\$@" ;;
esac
exec "${REAL_GIT}" -c "url.file://${BARE}.insteadOf=${SITE_URL}" "\$@"
STUB

  cat > "${BIN}/gh" << STUB
#!/bin/sh
echo "\$*" >> "${CALLS}/gh"
case "\$1 \$2" in
  "api user") [ -n "\${GH_NO_USER:-}" ] && exit 1; echo "test-bot 4242" ;;
  "pr list") [ -f "${CALLS}/existing-pr" ] && cat "${CALLS}/existing-pr"; exit 0 ;;
  "pr create") echo "https://github.com/${SITE_REPO}/pull/7" ;;
  "pr edit") exit "\${GH_LABEL_EXIT:-0}" ;;
esac
STUB

  cat > "${BIN}/pnpm" << STUB
#!/bin/sh
echo "\$*" >> "${CALLS}/pnpm"
[ "\$1" = "--version" ] && { echo "\${PNPM_VERSION:-11.2.0}"; exit 0; }
exit "\${PNPM_EXIT:-0}"
STUB

  # the site's validator; TAMPER names a file of the real clone it rewrites and STAGE one
  # it adds to the index, as hostile code of the target repository could
  cat > "${BIN}/node" << STUB
#!/bin/sh
echo "\$*" >> "${CALLS}/node"
[ -n "\${NODE_FAIL:-}" ] && { echo "✖ invalid catalog"; exit 1; }
[ -n "\${TAMPER:-}" ] && echo "tampered" >> "../site-repository/\${TAMPER}"
if [ -n "\${STAGE:-}" ]; then
  echo "staged" > "../site-repository/\${STAGE}"
  "${REAL_GIT}" -C ../site-repository add "\${STAGE}"
fi
echo "✔ Catalogue valide (3 entrées)"
STUB

  printf '#!/bin/sh\necho "libatomic.so.1 (libc6,x86-64) => /lib/libatomic.so.1"\n' > "${BIN}/ldconfig"

  cat > "${BIN}/aws" << STUB
#!/bin/sh
echo "\$*" >> "${CALLS}/aws"
[ "\$1 \$2" = "s3 cp" ] && cp "\$3" "${CALLS}/sidecar-\$(basename "\$4")"
exit "\${AWS_EXIT:-0}"
STUB
  chmod +x "${BIN}"/*

  # the site repository, with the parts of its layout the script reads
  local seed="${BATS_TEST_TMPDIR}/seed"
  mkdir -p "${seed}/src/data/releases/packages/26.10" "${seed}/scripts"
  cat > "${seed}/src/data/catalog.yaml" << 'CATALOG'
versions:
  - id: "26.10"
    label: "26.10"
  - id: "25.10"
    label: "25.10"
products:
  centreon-web:
    group: "packages"
  centreon-gorgone:
    group: packages
  centreon-vm:
    group: "appliances"
  centreon-widget:
    group: "custom"
  centreon-monitoring-agent:
    group: "agent"
  centreon-unknown-group:
    group: "elsewhere"
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
  cat > "${seed}/src/data/releases/packages/26.10/26.10.2.yaml" << 'EXISTING'
- product: "centreon-gorgone"
  train: "26.10"
  state: "stable"
  os: ""
  version: "26.10.2"
  file: "centreon-gorgone-26.10.2.tar.gz"
  date: "2026-10-01"
  md5: "33333333333333333333333333333333"
  size: 300
  enabled: true
EXISTING
  echo '{"packageManager": "pnpm@11.2.0"}' > "${seed}/package.json"
  echo "// validator" > "${seed}/scripts/validate.mjs"
  "$REAL_GIT" init --quiet --initial-branch develop "$seed"
  "$REAL_GIT" -C "$seed" -c user.name=seed -c user.email=seed@example.invalid add -A
  "$REAL_GIT" -C "$seed" -c user.name=seed -c user.email=seed@example.invalid commit --quiet -m "seed"
  "$REAL_GIT" clone --quiet --bare "$seed" "$BARE"
}

# one entry line: product train state os version file date md5 size [s3_uri] [out_name]
entry() {
  local IFS=$'\t'
  printf '%s\n' "$*"
}

# runs publish.sh with the environment of the action step, never the test's own
publish() {
  run env -i PATH="${BIN}:${PATH}" HOME="$HOME" GIT_CONFIG_NOSYSTEM=1 \
    GH_TOKEN="${TEST_TOKEN-placeholder-token}" WEBAPP_REPO="${TEST_REPO-$SITE_REPO}" WEBAPP_BASE=develop \
    NODE_FAIL="${NODE_FAIL:-}" TAMPER="${TAMPER:-}" STAGE="${STAGE:-}" PNPM_VERSION="${PNPM_VERSION:-}" PNPM_EXIT="${PNPM_EXIT:-}" \
    AWS_EXIT="${AWS_EXIT:-}" GH_NO_USER="${GH_NO_USER:-}" GH_LABEL_EXIT="${GH_LABEL_EXIT:-}" \
    "$PUBLISH" "$@"
}

# content of a file on a branch of the site repository
site_file() {
  "$REAL_GIT" --git-dir "$BARE" show "$1:$2"
}

site_has_branch() {
  "$REAL_GIT" --git-dir "$BARE" rev-parse --quiet --verify "refs/heads/$1" > /dev/null
}

# "! command" does not fail a bats test unless it is its last line: assert it
refute() {
  if "$@"; then
    echo "unexpectedly succeeded: $*"
    return 1
  fi
}
