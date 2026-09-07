#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPOSITORY_ROOT
readonly FIXTURE_COMMAND="${REPOSITORY_ROOT}/Scripts/Tests/Fixtures/deploy-appcast-command"
readonly FIXTURE_HISTORY="${REPOSITORY_ROOT}/Scripts/Tests/Fixtures/prepare-appcast-history"
TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/fancurve-deploy-appcast-test.XXXXXX")"
readonly TEMPORARY_DIRECTORY

cleanup() {
    rm -rf "${TEMPORARY_DIRECTORY}"
}

handle_interrupt() {
    cleanup
    trap - EXIT
    exit 130
}

handle_termination() {
    cleanup
    trap - EXIT
    exit 143
}

trap cleanup EXIT
trap handle_interrupt INT
trap handle_termination TERM

run_case() {
    local release_track="$1"
    local dry_run="$2"
    local current_relative_path="$3"
    local sibling_relative_path="$4"
    local expected_sibling_url="$5"
    local expected_deploy_command="$6"
    local case_directory
    local test_repository
    local fake_bin
    local fake_log
    local key_path
    local fixture_value

    case_directory="${TEMPORARY_DIRECTORY}/${release_track}-${dry_run}"
    test_repository="${case_directory}/repository"
    fake_bin="${case_directory}/bin"
    fake_log="${case_directory}/commands.log"
    fixture_value="notasecret"
    mkdir -p \
        "${test_repository}/Scripts" \
        "${test_repository}/deploy/appcast-worker/public" \
        "${fake_bin}" \
        "${case_directory}/runner"
    test_repository="$(cd "${test_repository}" && pwd -P)"
    cp "${REPOSITORY_ROOT}/Scripts/deploy-appcast.sh" \
        "${test_repository}/Scripts/deploy-appcast.sh"
    cp "${FIXTURE_HISTORY}" \
        "${test_repository}/Scripts/prepare-appcast-history.sh"

    for command_name in curl make npx; do
        ln -s "${FIXTURE_COMMAND}" "${fake_bin}/${command_name}"
    done

    chmod +x \
        "${test_repository}/Scripts/deploy-appcast.sh" \
        "${test_repository}/Scripts/prepare-appcast-history.sh"

    PATH="${fake_bin}:${PATH}" \
    FAKE_LOG="${fake_log}" \
    FAKE_REPOSITORY_ROOT="${test_repository}" \
    RUNNER_TEMP="${case_directory}/runner" \
    GH_REPOSITORY="agoodkind/macos-fan-curve" \
    RELEASE_TAG="26.9.4" \
    RELEASE_TRACK="${release_track}" \
    SPARKLE_PRIVATE_KEY="${fixture_value}" \
    CLOUDFLARE_API_TOKEN="test-api-token" \
    CLOUDFLARE_ACCOUNT_ID="test-account" \
    POST_PUBLISH_SECRET_1="${fixture_value}" \
    POST_PUBLISH_SECRET_2="test-api-token" \
    POST_PUBLISH_SECRET_3="test-account" \
    DRY_RUN="${dry_run}" \
        "${test_repository}/Scripts/deploy-appcast.sh"

    if [[ "$(<"${test_repository}/deploy/appcast-worker/public/${current_relative_path}")" \
        != "generated current" ]]; then
        printf 'deploy-appcast test: %s current appcast was not staged\n' \
            "${release_track}" >&2
        exit 1
    fi
    if [[ "$(<"${test_repository}/deploy/appcast-worker/public/${sibling_relative_path}")" \
        != "preserved sibling" ]]; then
        printf 'deploy-appcast test: %s sibling appcast was not preserved\n' \
            "${release_track}" >&2
        exit 1
    fi
    if ! grep -Fq "${expected_deploy_command}" "${fake_log}"; then
        printf 'deploy-appcast test: expected worker command did not execute\n' >&2
        exit 1
    fi
    if ! grep -Fq "${expected_sibling_url}" "${fake_log}"; then
        printf 'deploy-appcast test: %s preserved the wrong sibling feed\n' \
            "${release_track}" >&2
        exit 1
    fi
    key_path="$(awk '$1 == "key" { print $2 }' "${fake_log}")"
    if [[ -e "${key_path}" ]]; then
        printf 'deploy-appcast test: Sparkle key was not removed\n' >&2
        exit 1
    fi
}

run_case stable true appcast.xml prerelease/appcast.xml \
    'https://goodkind.io/fancurve/prerelease/appcast.xml' \
    'npx wrangler deploy --dry-run --config wrangler.toml'
run_case stable false appcast.xml prerelease/appcast.xml \
    'https://goodkind.io/fancurve/prerelease/appcast.xml' \
    'npx wrangler deploy --config wrangler.toml'
run_case prerelease true prerelease/appcast.xml appcast.xml \
    'https://goodkind.io/fancurve/appcast.xml' \
    'npx wrangler deploy --dry-run --config wrangler.toml'
run_case prerelease false prerelease/appcast.xml appcast.xml \
    'https://goodkind.io/fancurve/appcast.xml' \
    'npx wrangler deploy --config wrangler.toml'

printf 'deploy-appcast: passed\n'
