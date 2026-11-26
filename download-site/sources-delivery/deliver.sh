#!/usr/bin/env bash
# Build the source tarball of a module and upload it to the download bucket.
# Inputs (env): MODULE_NAME, MODULE_DIRECTORY, BUCKET_DIRECTORY, MAJOR_VERSION,
# MINOR_VERSION, and optionally BUCKET and DRY_RUN.
set -euo pipefail

MODULE_NAME="${MODULE_NAME:-}"
MODULE_DIRECTORY="${MODULE_DIRECTORY:-}"
BUCKET_DIRECTORY="${BUCKET_DIRECTORY:-}"
MAJOR_VERSION="${MAJOR_VERSION:-}"
MINOR_VERSION="${MINOR_VERSION:-}"
BUCKET="${BUCKET:-centreon-download}"
DRY_RUN="${DRY_RUN:-false}"

fail() {
  echo "::error::$1"
  exit 1
}

for name in MODULE_NAME MODULE_DIRECTORY BUCKET_DIRECTORY MAJOR_VERSION MINOR_VERSION; do
  [[ -n "${!name}" ]] || fail "the ${name,,} input is empty"
done

# these values build a file name and an object key: no path trick, no option
[[ "$MODULE_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid module_name '${MODULE_NAME}'"
[[ "$MAJOR_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._~+-]*$ ]] || fail "invalid major_version '${MAJOR_VERSION}'"
[[ "$MINOR_VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._~+-]*$ ]] || fail "invalid minor_version '${MINOR_VERSION}'"
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || fail "invalid bucket '${BUCKET}'"
if [[ ! "$BUCKET_DIRECTORY" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ || "$BUCKET_DIRECTORY" == *..* ]]; then
  fail "invalid bucket_directory '${BUCKET_DIRECTORY}'"
fi
[[ "$DRY_RUN" == "true" || "$DRY_RUN" == "false" ]] || fail "dry_run must be 'true' or 'false'"
[[ -d "$MODULE_DIRECTORY" ]] || fail "module_directory '${MODULE_DIRECTORY}' is not a directory"

VERSION="${MAJOR_VERSION}.${MINOR_VERSION}"
ARCHIVE_ROOT="${MODULE_NAME}-${VERSION}"
SRC_FILE="${ARCHIVE_ROOT}.tar.gz"
DESTINATION="s3://${BUCKET}/public/${BUCKET_DIRECTORY}/${SRC_FILE}"

# the tarball holds one directory named after the module and its version
if [[ "$(realpath "$MODULE_DIRECTORY")" != "$(realpath -m "$ARCHIVE_ROOT")" ]]; then
  [[ ! -e "$ARCHIVE_ROOT" ]] || fail "'${ARCHIVE_ROOT}' already exists in the workspace"
  mv "$MODULE_DIRECTORY" "$ARCHIVE_ROOT"
fi
# an archived checkout ships its files, not its git metadata
tar czf "$SRC_FILE" --exclude="${ARCHIVE_ROOT}/.git" "$ARCHIVE_ROOT"
echo "[INFO] Built ${SRC_FILE} ($(du -h "$SRC_FILE" | cut -f1))"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "source_file=${SRC_FILE}"
    echo "destination=${DESTINATION}"
  } >> "$GITHUB_OUTPUT"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "::notice::Dry run: ${SRC_FILE} would be uploaded to ${DESTINATION}"
  exit 0
fi

if ! command -v aws > /dev/null 2>&1; then
  echo "[INFO] Installing the aws cli"
  install_dir=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "${install_dir}/awscliv2.zip"
  unzip -q "${install_dir}/awscliv2.zip" -d "$install_dir"
  sudo "${install_dir}/aws/install"
  rm -rf "$install_dir"
fi

aws s3 cp --acl public-read "$SRC_FILE" "$DESTINATION"
echo "[INFO] Uploaded ${SRC_FILE} to ${DESTINATION}"
