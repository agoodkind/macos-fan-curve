#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_PATH="${REPOSITORY_ROOT}/Scripts/Tests/Fixtures/releases.json"
SELECTOR_PATH="${REPOSITORY_ROOT}/Scripts/select-appcast-releases.jq"

expected_prerelease=$(
    printf '%s\n' \
        $'26.7.26-pre.202607261200+aaaaaaa\tFanCurve-26.7.26-pre.202607261200-aaaaaaa.dmg' \
        $'26.7.25-pre.202607252300+bbbbbbb\tFanCurve-26.7.25-pre.202607252300-bbbbbbb.dmg'
)
actual_prerelease=$(
    jq --raw-output \
        --arg release_track prerelease \
        --arg asset_prefix "FanCurve-" \
        --arg asset_suffix ".dmg" \
        --argjson release_limit 2 \
        --from-file "${SELECTOR_PATH}" \
        "${FIXTURE_PATH}"
)
if [[ "${actual_prerelease}" != "${expected_prerelease}" ]]; then
    printf 'select-appcast-releases: unexpected pre-release selection\n%s\n' \
        "${actual_prerelease}" >&2
    exit 1
fi

expected_stable=$(
    printf '%s\n' \
        $'26.7.26\tFanCurve-26.7.26.dmg' \
        $'26.7.25-r1\tFanCurve-26.7.25-r1.dmg' \
        $'26.7.24\tFanCurve-26.7.24.dmg'
)
actual_stable=$(
    jq --raw-output \
        --arg release_track stable \
        --arg asset_prefix "FanCurve-" \
        --arg asset_suffix ".dmg" \
        --argjson release_limit 3 \
        --from-file "${SELECTOR_PATH}" \
        "${FIXTURE_PATH}"
)
if [[ "${actual_stable}" != "${expected_stable}" ]]; then
    printf 'select-appcast-releases: unexpected stable selection\n%s\n' \
        "${actual_stable}" >&2
    exit 1
fi

printf 'select-appcast-releases: passed\n'
