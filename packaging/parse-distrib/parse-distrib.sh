#!/usr/bin/env bash
# Print what the packaging and delivery jobs need to know about a distribution, as
# step outputs. Input (env): DISTRIB.
set -euo pipefail

DISTRIB="${DISTRIB:-}"

if [[ -z "$DISTRIB" ]]; then
  echo "::error::the distrib input is empty"
  exit 1
fi

# rpm and deb packages are named "<name>-<version>" and "<name>_<version>", and carry
# their distribution after the version as ".el9", "+deb12u1" or "-0ubuntu.24.04"
el() {
  PACKAGE_EXTENSION="rpm"
  PACKAGE_VERSION_SEPARATOR="-"
  PACKAGE_DISTRIB_SEPARATOR="."
  PACKAGE_DISTRIB_NAME="el$1"
  DISTRIB_FAMILY="el"
  DISTRIB_FAMILY_MAJOR="el$1"
  DISTRIB_NAME="$2"
  REPO_DISTRIB_NAME="el$1"
}

debian() {
  PACKAGE_EXTENSION="deb"
  PACKAGE_VERSION_SEPARATOR="_"
  PACKAGE_DISTRIB_SEPARATOR="+"
  PACKAGE_DISTRIB_NAME="deb$1u1"
  DISTRIB_FAMILY="debian"
  DISTRIB_FAMILY_MAJOR="debian"
  DISTRIB_NAME="$DISTRIB"
  REPO_DISTRIB_NAME="$DISTRIB"
}

ubuntu() {
  PACKAGE_EXTENSION="deb"
  PACKAGE_VERSION_SEPARATOR="_"
  PACKAGE_DISTRIB_SEPARATOR="-"
  PACKAGE_DISTRIB_NAME="0ubuntu.$1"
  DISTRIB_FAMILY="ubuntu"
  DISTRIB_FAMILY_MAJOR="ubuntu"
  DISTRIB_NAME="$DISTRIB"
  REPO_DISTRIB_NAME="$DISTRIB"
}

case "$DISTRIB" in
  centos7 | el7) el 7 centos7 ;;
  alma8 | el8) el 8 alma8 ;;
  alma9 | el9) el 9 alma9 ;;
  alma10 | el10) el 10 alma10 ;;
  bullseye) debian 11 ;;
  bookworm) debian 12 ;;
  trixie) debian 13 ;;
  jammy) ubuntu 22.04 ;;
  noble) ubuntu 24.04 ;;
  *)
    echo "::error::Distrib ${DISTRIB} cannot be parsed"
    exit 1
    ;;
esac

{
  echo "package_extension=${PACKAGE_EXTENSION}"
  echo "package_version_separator=${PACKAGE_VERSION_SEPARATOR}"
  echo "package_distrib_separator=${PACKAGE_DISTRIB_SEPARATOR}"
  echo "package_distrib_name=${PACKAGE_DISTRIB_NAME}"
  echo "distrib_family=${DISTRIB_FAMILY}"
  echo "distrib_family_major=${DISTRIB_FAMILY_MAJOR}"
  echo "distrib_name=${DISTRIB_NAME}"
  echo "repo_distrib_name=${REPO_DISTRIB_NAME}"
  # older name of repo_distrib_name
  echo "package_distrib=${REPO_DISTRIB_NAME}"
} >> "$GITHUB_OUTPUT"
