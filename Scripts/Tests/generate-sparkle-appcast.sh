#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="${REPOSITORY_ROOT}/Scripts/Tests/Fixtures"
TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/fancurve-generate-appcast-test.XXXXXX")"

cleanup() {
    rm -rf "${TEMPORARY_DIRECTORY}"
}
trap cleanup EXIT

UPDATES_DIRECTORY="${TEMPORARY_DIRECTORY}/updates"
TOOL_DIRECTORY="${TEMPORARY_DIRECTORY}/build/SourcePackages/artifacts/fixture/Sparkle/bin"
MAPPING_PATH="${UPDATES_DIRECTORY}/asset-tags.tsv"
PRIVATE_KEY_PATH="${TEMPORARY_DIRECTORY}/sparkle-private-key"

mkdir -p "${UPDATES_DIRECTORY}" "${TOOL_DIRECTORY}"
cp "${FIXTURE_ROOT}/generate_appcast" "${TOOL_DIRECTORY}/generate_appcast"
chmod +x "${TOOL_DIRECTORY}/generate_appcast"
printf '%s\n' 'fixture-key' > "${PRIVATE_KEY_PATH}"

for i in {1..10}; do
    ASSET_NAME="FanCurve-26.7.${i}.dmg"
    touch "${UPDATES_DIRECTORY}/${ASSET_NAME}"
    printf '26.7.%s\t%s\n' "${i}" "${ASSET_NAME}" >> "${MAPPING_PATH}"
done

make -s -C "${REPOSITORY_ROOT}" generate-sparkle-appcast \
    BUILD_DIR="${TEMPORARY_DIRECTORY}/build" \
    GH_REPOSITORY="agoodkind/macos-fan-curve" \
    SPARKLE_ASSET_TAGS="${MAPPING_PATH}" \
    SPARKLE_GENERATED_APPCAST="${UPDATES_DIRECTORY}/appcast.xml" \
    SPARKLE_PRIVATE_KEY_FILE="${PRIVATE_KEY_PATH}" \
    SPARKLE_UPDATES_DIR="${UPDATES_DIRECTORY}"

ENCLOSURE_COUNT="$(
    grep -c '<enclosure ' "${UPDATES_DIRECTORY}/appcast.xml"
)"
if [[ "${ENCLOSURE_COUNT}" != "10" ]]; then
    printf 'generate-sparkle-appcast test: expected 10 enclosures, found %s\n' \
        "${ENCLOSURE_COUNT}" >&2
    exit 1
fi
if grep -Fq '.delta' "${UPDATES_DIRECTORY}/appcast.xml"; then
    printf 'generate-sparkle-appcast test: appcast contains a delta enclosure\n' >&2
    exit 1
fi
printf 'generate-sparkle-appcast: passed\n'
