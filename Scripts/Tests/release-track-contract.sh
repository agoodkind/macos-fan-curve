#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
    printf 'release-track-contract: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file_path
    local expected_text

    file_path=$1
    expected_text=$2
    if ! grep -Fq -- "${expected_text}" "${REPOSITORY_ROOT}/${file_path}"; then
        fail "${file_path} does not contain: ${expected_text}"
    fi
}

assert_not_contains() {
    local file_path
    local unexpected_text

    file_path=$1
    unexpected_text=$2
    if grep -Fq -- "${unexpected_text}" "${REPOSITORY_ROOT}/${file_path}"; then
        fail "${file_path} still contains: ${unexpected_text}"
    fi
}

assert_contains ".github/workflows/release.yml" "release-track:"
assert_contains ".github/workflows/release.yml" "candidate-tag:"
assert_contains ".github/workflows/release.yml" 'candidate-asset-pattern: "FanCurve-*.dmg"'
assert_contains ".github/workflows/release.yml" "source-sha:"
assert_contains ".github/workflows/release.yml" "allow-source-sha:"
assert_contains ".github/workflows/release.yml" "post-publish-timeout-minutes: 15"
assert_contains ".github/workflows/release.yml" "post-publish-node-version: \"22\""
assert_contains ".github/workflows/release.yml" "Scripts/deploy-appcast.sh"
assert_contains ".github/workflows/release.yml" \
    'POST_PUBLISH_SECRET_1: ${{ secrets.SPARKLE_PRIVATE_ED_KEY }}'
assert_contains ".github/workflows/release.yml" \
    'POST_PUBLISH_SECRET_2: ${{ secrets.CLOUDFLARE_API_TOKEN }}'
assert_contains ".github/workflows/release.yml" \
    'POST_PUBLISH_SECRET_3: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}'
assert_not_contains ".github/workflows/release.yml" "pull_request:"
assert_not_contains ".github/workflows/release.yml" "appcast:"

assert_contains ".github/workflows/appcast.yml" "workflow_dispatch:"
assert_contains ".github/workflows/appcast.yml" "release_tag:"
assert_contains ".github/workflows/appcast.yml" "release_track:"
assert_contains ".github/workflows/appcast.yml" "timeout-minutes: 15"
assert_contains ".github/workflows/appcast.yml" "Scripts/deploy-appcast.sh"
assert_not_contains ".github/workflows/appcast.yml" "workflow_call:"
assert_not_contains ".github/workflows/appcast.yml" "git tag --points-at"
assert_not_contains ".github/workflows/appcast.yml" "public_path="
# shellcheck disable=SC2016 # The assertion matches literal Make syntax.
assert_not_contains "Makefile" 'build_version="$$(basename'

assert_contains "Makefile" "ARTIFACT_VERSION ?= Release"
assert_contains "Makefile" "RELEASE_DMG_NAME ="
assert_contains "Makefile" "SPARKLE_APPCAST_FEED_PATH ="
assert_contains "Templates/Plists/App-Info.plist.template" "@@SPARKLE_FEED_URL@@"

assert_contains "Sources/Services/AppUpdater.swift" "#if DEBUG"
assert_contains "Sources/App/FanCurveApp.swift" "if appUpdater.isConfigured"
assert_contains "Sources/Views/AboutContentView.swift" "if appUpdater.isConfigured"

printf 'release-track-contract: passed\n'
