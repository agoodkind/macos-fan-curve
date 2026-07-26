#!/usr/bin/env bash
set -euo pipefail

readonly RELEASE_LIMIT=10
readonly ASSET_PREFIX="FanCurve-"
readonly ASSET_SUFFIX=".dmg"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
selector_path="${repository_root}/Scripts/select-appcast-releases.jq"
updates_directory="${SPARKLE_UPDATES_DIR:?SPARKLE_UPDATES_DIR is required}"
release_track="${RELEASE_TRACK:?RELEASE_TRACK is required}"
published_release_tag="${RELEASE_TAG:?RELEASE_TAG is required}"
github_repository="${GH_REPOSITORY:?GH_REPOSITORY is required}"
release_data_file="$(mktemp "${TMPDIR:-/tmp}/fancurve-releases.XXXXXX")"
selection_file="$(mktemp "${TMPDIR:-/tmp}/fancurve-selection.XXXXXX")"

cleanup() {
    rm -f "${release_data_file}" "${selection_file}"
}

handle_interrupt() {
    exit 130
}

handle_termination() {
    exit 143
}

trap cleanup EXIT
trap handle_interrupt INT
trap handle_termination TERM

case "${release_track}" in
    prerelease | stable)
        ;;
    *)
        printf 'prepare-appcast-history: RELEASE_TRACK must be prerelease or stable\n' >&2
        exit 1
        ;;
esac

gh api \
    --paginate \
    --slurp \
    "repos/${github_repository}/releases?per_page=100" > "${release_data_file}"

jq --raw-output \
    --arg release_track "${release_track}" \
    --arg asset_prefix "${ASSET_PREFIX}" \
    --arg asset_suffix "${ASSET_SUFFIX}" \
    --argjson release_limit "${RELEASE_LIMIT}" \
    --from-file "${selector_path}" \
    "${release_data_file}" > "${selection_file}"

if [[ ! -s "${selection_file}" ]]; then
    printf 'prepare-appcast-history: no %s releases contain a matching DMG\n' \
        "${release_track}" >&2
    exit 1
fi

if ! awk -F '\t' -v expected="${published_release_tag}" \
    '$1 == expected { found = 1 } END { exit(found ? 0 : 1) }' \
    "${selection_file}"; then
    printf 'prepare-appcast-history: %s is not a selected %s release\n' \
        "${published_release_tag}" "${release_track}" >&2
    exit 1
fi

rm -rf "${updates_directory}"
mkdir -p "${updates_directory}"
mapping_path="${updates_directory}/asset-tags.tsv"

while IFS=$'\t' read -r release_tag asset_name; do
    if [[ -z "${release_tag}" || -z "${asset_name}" ]]; then
        printf 'prepare-appcast-history: selector returned an incomplete release\n' >&2
        exit 1
    fi

    gh release download "${release_tag}" \
        --repo "${github_repository}" \
        --pattern "${asset_name}" \
        --dir "${updates_directory}"
    printf '%s\t%s\n' "${release_tag}" "${asset_name}" >> "${mapping_path}"
done < "${selection_file}"

printf 'prepare-appcast-history: staged %s releases for %s\n' \
    "$(wc -l < "${mapping_path}" | tr -d ' ')" "${release_track}"
