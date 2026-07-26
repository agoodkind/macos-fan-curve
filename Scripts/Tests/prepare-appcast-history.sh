#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="${REPOSITORY_ROOT}/Scripts/Tests/Fixtures"
TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/fancurve-history-test.XXXXXX")"

cleanup() {
    rm -rf "${TEMPORARY_DIRECTORY}"
}
trap cleanup EXIT

mkdir -p "${TEMPORARY_DIRECTORY}/bin"
cp "${FIXTURE_ROOT}/gh" "${TEMPORARY_DIRECTORY}/bin/gh"
chmod +x "${TEMPORARY_DIRECTORY}/bin/gh"

export FAKE_RELEASES_PATH="${FIXTURE_ROOT}/releases.json"
export GH_REPOSITORY="agoodkind/macos-fan-curve"
export RELEASE_TAG="26.7.26-pre.202607261200+aaaaaaa"
export RELEASE_TRACK="prerelease"
export SPARKLE_UPDATES_DIR="${TEMPORARY_DIRECTORY}/updates"
export PATH="${TEMPORARY_DIRECTORY}/bin:${PATH}"

"${REPOSITORY_ROOT}/Scripts/prepare-appcast-history.sh"

expected_asset="FanCurve-26.7.26-pre.202607261200-aaaaaaa.dmg"
if [[ ! -f "${SPARKLE_UPDATES_DIR}/${expected_asset}" ]]; then
    printf 'prepare-appcast-history test: newest pre-release asset is missing\n' >&2
    exit 1
fi
if [[ "$(find "${SPARKLE_UPDATES_DIR}" -name '*.dmg' | wc -l | tr -d ' ')" != "2" ]]; then
    printf 'prepare-appcast-history test: expected two pre-release assets\n' >&2
    exit 1
fi
if ! grep -Fq $'26.7.25-pre.202607252300+bbbbbbb\tFanCurve-26.7.25-pre.202607252300-bbbbbbb.dmg' \
    "${SPARKLE_UPDATES_DIR}/asset-tags.tsv"; then
    printf 'prepare-appcast-history test: historical mapping is missing\n' >&2
    exit 1
fi

export RELEASE_TAG="26.7.26"
if "${REPOSITORY_ROOT}/Scripts/prepare-appcast-history.sh" >/dev/null 2>&1; then
    printf 'prepare-appcast-history test: accepted a stable tag for pre-release\n' >&2
    exit 1
fi

printf 'prepare-appcast-history: passed\n'
