#!/usr/bin/env bash
# Verify that the delivered/promoted DEB packages are (1) physically present as
# content units in their target pulp repository and (2) resolvable through the
# published apt metadata (and actually fetchable from the content url).
#
# Metadata resolution mirrors promote-deb.sh: the structured publication serves
# packages under the canonical pool layout, so the published Filename is resolved
# from the suite's Packages index by sha256. Architecture "all" packages are
# listed under every binary-<arch>, so they are looked up across the suite's
# architectures. Each index is read once into a sha256 -> Filename map.
#
# The expected list is the manifest emitted by the delivery/promote step. The
# script never exits early — see check-common.sh.
set -uo pipefail

# shellcheck source=pulp/lib/check-common.sh
source "$(dirname "$0")/check-common.sh"

load_expected "DEB"

# --- load expected packages into parallel arrays ---------------------------
mapfile -t E_FILENAME   < <(echo "$PACKAGES_JSON" | jq -r '.[].filename')
mapfile -t E_ARCH       < <(echo "$PACKAGES_JSON" | jq -r '.[].arch')
mapfile -t E_SHA256     < <(echo "$PACKAGES_JSON" | jq -r '.[].sha256')
mapfile -t E_REPOSITORY < <(echo "$PACKAGES_JSON" | jq -r '.[].repository')
mapfile -t E_BASEPATH   < <(echo "$PACKAGES_JSON" | jq -r '.[].base_path')
mapfile -t E_SUITE      < <(echo "$PACKAGES_JSON" | jq -r '.[].suite')

# --- physical presence: content units in the repository's latest version ----
declare -A VERSION_BY_REPO   # repo -> latest_version_href, empty when missing
for repo in $(printf '%s\n' "${E_REPOSITORY[@]}" | sort -u); do
  VERSION_BY_REPO[$repo]=$(latest_version_href deb "$repo")
  [[ -n "${VERSION_BY_REPO[$repo]}" ]] || echo "[WARN] Repository $repo does not exist or has no version"
done

# batch lookup: a delivery labels the packages it uploads with its run id, so
# one filtered listing per repository answers for all of them. Listing the
# whole repository version instead is not an option: the shared repositories
# hold 10k+ packages and that listing hits the gateway timeout.
declare -A BATCH_PRESENT   # "repo|sha256" -> 1
if [[ "${CHECK_MODE:-delivery}" == "delivery" && -n "${GITHUB_RUN_ID:-}" ]]; then
  for repo in "${!VERSION_BY_REPO[@]}"; do
    version_href=${VERSION_BY_REPO[$repo]}
    [[ -n "$version_href" ]] || continue
    url="$PULP_URL/$PULP_DOMAIN/api/v3/content/deb/packages/?$(
      printf 'repository_version=%s&pulp_label_select=%s&fields=sha256&limit=1000' \
        "$(jq -rn --arg v "$version_href" '$v | @uri')" \
        "$(jq -rn --arg v "github_run_id=$GITHUB_RUN_ID" '$v | @uri')"
    )"
    pages=0
    found=0
    while [[ -n "$url" ]] && ((pages < 20)); do
      refresh_pulp_token
      page=$(curl -fsSL --retry 3 --retry-delay 5 -H "Authorization: Bearer $PULP_TOKEN" "$url") || {
        echo "[WARN] presence listing failed for $repo ($url), falling back to one lookup per package" >&2
        break
      }
      while IFS= read -r sha; do
        BATCH_PRESENT["$repo|$sha"]=1
        found=$((found + 1))
      done < <(jq -r '.results[].sha256' <<< "$page")
      pages=$((pages + 1))
      url=$(jq -r '.next // empty' <<< "$page")
    done
    echo "[INFO] Repository $repo holds $found package(s) delivered by this run in its latest version"
  done
fi

# one lookup per package the listing did not return, CHECK_MAX_PARALLEL at a
# time, by sha256 within the repository version (content that already existed
# keeps the labels of the run that uploaded it, and a promotion uploads
# nothing). --retry covers transient 5xx, which would otherwise read as
# "absent".
declare -A PRESENT_IDX
PRESENCE_DIR=$(mktemp -d)
lookups=0
for i in "${!E_FILENAME[@]}"; do
  PRESENT_IDX[$i]=false
  version_href=${VERSION_BY_REPO[${E_REPOSITORY[$i]}]}
  [[ -n "$version_href" ]] || continue
  if [[ -n "${BATCH_PRESENT["${E_REPOSITORY[$i]}|${E_SHA256[$i]}"]:-}" ]]; then
    PRESENT_IDX[$i]=true
    continue
  fi
  lookups=$((lookups + 1))
  url="$PULP_URL/$PULP_DOMAIN/api/v3/content/deb/packages/?$(
    printf 'repository_version=%s&sha256=%s&fields=pulp_href&limit=1' \
      "$(jq -rn --arg v "$version_href" '$v | @uri')" "${E_SHA256[$i]}"
  )"
  # token refreshed in this shell: a refresh inside the job would be lost
  refresh_pulp_token
  (
    count=$(curl -fsSL --retry 3 --retry-delay 5 \
              -H "Authorization: Bearer $PULP_TOKEN" "$url" | jq -r '.count // 0') || {
      echo "[WARN] presence lookup failed for ${E_FILENAME[$i]} in ${E_REPOSITORY[$i]} ($url)" >&2
      exit 0
    }
    [[ "${count:-0}" -gt 0 ]] && touch "$PRESENCE_DIR/$i"
  ) &
  wait_for_slot
done
wait
for i in "${!E_FILENAME[@]}"; do
  [[ -e "$PRESENCE_DIR/$i" ]] && PRESENT_IDX[$i]=true
done
rm -rf "$PRESENCE_DIR"
echo "[INFO] Presence checked for ${#E_FILENAME[@]} package(s), $lookups through a per-package lookup"

# --- metadata resolvability + fetchability, with a bounded retry window -----
declare -A META_IDX      # idx -> true|false
declare -A RESOLVED_IDX  # idx -> published Filename
for i in "${!E_FILENAME[@]}"; do META_IDX[$i]=false; done

# one resolution round: read each suite's Packages indexes once into a
# sha256 -> Filename map, then resolve each pending package from it
resolve_pending() {
  local -A indexed=()      # key: base_path|suite|arch -> set once read
  local -A filename_by=()  # key: base_path|suite|arch|sha256 -> Filename
  local -A arches_cache=() # key: base_path|suite -> space separated arches
  local all_resolved=true i base_path suite arch search_arches sk ck a filename sha fname
  for i in "${!E_FILENAME[@]}"; do
    [[ "${META_IDX[$i]}" == "true" ]] && continue
    base_path=${E_BASEPATH[$i]}; suite=${E_SUITE[$i]}; arch=${E_ARCH[$i]}

    # architectures to search: the package arch, plus every arch of the suite
    # for "all" packages (which are duplicated across each binary-<arch>)
    search_arches="$arch"
    if [[ "$arch" == "all" ]]; then
      sk="$base_path|$suite"
      if [[ -z "${arches_cache[$sk]+set}" ]]; then
        arches_cache[$sk]=$(content_curl -fsSL "$PULP_CONTENT_URL/$base_path/dists/$suite/Release" 2>/dev/null \
          | awk -F': ' '/^Architectures:/ { print $2; exit }')
      fi
      search_arches="${arches_cache[$sk]:-amd64 arm64 all}"
    fi

    filename=""
    for a in $search_arches; do
      ck="$base_path|$suite|$a"
      if [[ -z "${indexed[$ck]+set}" ]]; then
        indexed[$ck]=1
        while IFS=$'\t' read -r sha fname; do
          filename_by["$ck|$sha"]=$fname
        done < <(content_curl -fsSL "$PULP_CONTENT_URL/$base_path/dists/$suite/main/binary-$a/Packages" 2>/dev/null |
          awk 'BEGIN { RS = ""; FS = "\n" } {
            sha = ""; fname = ""
            for (i = 1; i <= NF; i++) {
              if ($i ~ /^SHA256: /) sha = substr($i, 9)
              else if ($i ~ /^Filename: /) fname = substr($i, 11)
            }
            if (sha != "" && fname != "") print sha "\t" fname
          }')
      fi
      filename=${filename_by["$ck|${E_SHA256[$i]}"]:-}
      [[ -n "$filename" ]] && break
    done

    if [[ -n "$filename" ]]; then
      META_IDX[$i]=true
      RESOLVED_IDX[$i]=$filename
    else
      all_resolved=false
    fi
  done
  [[ "$all_resolved" == "true" ]]
}

wait_for_metadata
check_fetchable_and_record
render_summary
