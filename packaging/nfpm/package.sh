#!/usr/bin/env bash
# Build the packages of every nfpm configuration matching a pattern, in the current
# directory. Inputs (env): see the step of action.yml.
set -euo pipefail

error() {
  echo "::error::$*" >&2
  exit 1
}

# sed replacement text: the three characters sed reads in it are escaped
escape() {
  local value=${1//\\/\\\\}
  value=${value//\//\\/}
  printf '%s' "${value//&/\\&}"
}

# "NAME=value" lines of an input, as "NAME<tab>value"; blank lines are skipped
pairs() {
  local line
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || error "'${line}' is not a NAME=value line"
    printf '%s\t%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
  done <<< "$1"
}

# replaces @NAME@ in the given files
substitute() {
  local name=$1 value
  value=$(escape "$2")
  shift 2
  sed -i "s/@${name}@/${value}/g" "$@"
}

[[ -n "${NFPM_FILE_PATTERN:-}" ]] || error "the nfpm_file_pattern input is empty"
[[ -n "${COMMIT_HASH:-}" ]] || error "the commit_hash input is empty"
[[ "$PACKAGE_EXTENSION" == "rpm" || "$PACKAGE_EXTENSION" == "deb" ]] || error "unknown package extension '${PACKAGE_EXTENSION}'"

# ---- version, release and distribution, read by the nfpm configurations ----------------
if [[ -n "${INPUT_VERSION:-}" ]]; then
  export VERSION="$INPUT_VERSION"
elif [[ -n "${INPUT_MAJOR_VERSION:-}" ]]; then
  export VERSION="${INPUT_MAJOR_VERSION}.${INPUT_MINOR_VERSION:-}"
else
  error "give either version or major_version and minor_version"
fi
export RELEASE="${INPUT_RELEASE:-}"
export ARCH="${INPUT_ARCH:-}"

DISTRIB_SUFFIX="${PACKAGE_DISTRIB_SEPARATOR}${PACKAGE_DISTRIB_NAME}"
if [[ "$PACKAGE_EXTENSION" == "rpm" ]]; then
  export DIST="$DISTRIB_SUFFIX"
  export APACHE_USER="apache"
  export APACHE_GROUP="apache"
else
  export DIST=""
  RELEASE="${DEB_RELEASE:-$RELEASE}${DEB_RELEASE_SUFFIX:-$DISTRIB_SUFFIX}"
  export APACHE_USER="www-data"
  export APACHE_GROUP="www-data"
fi

# the major version after this one, for the dependencies bounded by it: versions were
# biannual (24.04, 24.10, ...) before 26.10 and are monthly since
if [[ -n "${INPUT_MAJOR_VERSION:-}" ]]; then
  export MAJOR_VERSION="$INPUT_MAJOR_VERSION"
  [[ "$MAJOR_VERSION" =~ ^([0-9]+)\.([0-9]+) ]] || error "major_version '${MAJOR_VERSION}' is not YY.MM"
  major_left=${BASH_REMATCH[1]}
  major_right=${BASH_REMATCH[2]}
  if ((10#$major_left * 100 + 10#$major_right < 2610)); then
    if [[ "$major_right" == "04" ]]; then
      export NEXT_MAJOR_VERSION="${major_left}.10"
    else
      export NEXT_MAJOR_VERSION="$((major_left + 1)).04"
    fi
  elif [[ "$major_right" == "12" ]]; then
    export NEXT_MAJOR_VERSION="$((major_left + 1)).01"
  else
    export NEXT_MAJOR_VERSION="${major_left}.$((10#$major_right + 1))"
  fi
fi

# ---- signing key, kept out of the workspace and removed on exit ------------------------
KEY_DIRECTORY=$(mktemp -d "${RUNNER_TEMP:-/tmp}/nfpm-key.XXXXXX")
trap 'rm -rf "${KEY_DIRECTORY:?}"' EXIT
export RPM_SIGNING_KEY_FILE="${KEY_DIRECTORY}/key.gpg"
(umask 077 && printf '%s' "${RPM_GPG_KEY:-}" > "$RPM_SIGNING_KEY_FILE")
export RPM_SIGNING_KEY_ID="${RPM_GPG_SIGNING_KEY_ID:-}"
export NFPM_RPM_PASSPHRASE="${RPM_GPG_SIGNING_PASSPHRASE:-}"

PLACEHOLDERS=$(pairs "${PLACEHOLDERS:-}")

# adds the license of the package to a deb, as /usr/share/doc/<package>/copyright
add_copyright() {
  local config=$1 license source="" candidate package
  license=$(sed -n 's/^license: *//p' "$config" | head -1 | sed 's/"//g' | xargs)
  if [[ -f "${ROOT}/copyright.${license}" ]]; then
    source="${ROOT}/copyright.${license}"
  else
    for candidate in "${ROOT}/LICENSE.md" "${ROOT}/LICENSE"; do
      [[ -f "$candidate" ]] && source="$candidate" && break
    done
  fi
  [[ -n "$source" ]] || return 0
  cp "$source" ./copyright
  package=$(sed -n 's/^name: *//p' "$config" | head -1 | sed 's/"//g' | xargs)
  # the entry closes the "contents:" list, or opens one when the configuration has none
  awk -v pkg="$package" '
    function entry() {
      print "  - src: ./copyright"
      print "    dst: /usr/share/doc/" pkg "/copyright"
      print "    packager: deb"
    }
    BEGIN { in_contents = 0; injected = 0 }
    /^contents:/ { in_contents = 1 }
    in_contents && /^[a-z]/ && !/^contents:/ && !injected { entry(); injected = 1; in_contents = 0 }
    { print }
    END { if (!injected) { if (!in_contents) { print "contents:" } entry() } }
  ' "$config" > "${config}.tmp"
  mv "${config}.tmp" "$config"
}

ROOT=$PWD
# the pattern is a list of globs, split and expanded on purpose
# shellcheck disable=SC2206
FILES=($NFPM_FILE_PATTERN)
[[ -e "${FILES[0]}" ]] || error "no nfpm configuration matches '${NFPM_FILE_PATTERN}'"

for file in "${FILES[@]}"; do
  directory=$(dirname "$file")
  config=$(basename "$file")

  cd "$directory"

  # without a key the packages are built unsigned
  if [[ -z "$RPM_SIGNING_KEY_ID" ]]; then
    sed -i -e "/signature:/d" -e "/RPM_SIGNING_KEY_FILE/d" -e "/RPM_SIGNING_KEY_ID/d" "$config"
  fi

  substitute APACHE_USER "$APACHE_USER" "$config"
  substitute APACHE_GROUP "$APACHE_GROUP" "$config"
  substitute COMMIT_HASH "$COMMIT_HASH" "$config"
  while IFS=$'\t' read -r name value; do
    [[ -n "$name" ]] && substitute "$name" "$value" "$config"
  done <<< "$PLACEHOLDERS"

  if [[ "$PACKAGE_EXTENSION" == "deb" && "${DEB_COPYRIGHT:-false}" == "true" ]]; then
    add_copyright "$config"
  fi

  if grep -nE '@[A-Z][A-Z0-9_]*@' "$config"; then
    echo "::error file=${file}::unsubstituted placeholder(s) in the rendered nfpm configuration"
    exit 1
  fi

  nfpm package --config "$config" --packager "$PACKAGE_EXTENSION"

  cd "$ROOT"
  if [[ "$(cd "$directory" && pwd -P)" != "$(pwd -P)" ]]; then
    mv "${directory}"/*."${PACKAGE_EXTENSION}" ./
  fi
done

ls -lh ./*."${PACKAGE_EXTENSION}"
