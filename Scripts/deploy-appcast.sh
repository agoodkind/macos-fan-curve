#!/usr/bin/env bash
set -euo pipefail

readonly GH_REPOSITORY="${GH_REPOSITORY:?GH_REPOSITORY is required}"
readonly RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
readonly RELEASE_TRACK="${RELEASE_TRACK:?RELEASE_TRACK is required}"
readonly DRY_RUN="${DRY_RUN:?DRY_RUN is required}"
readonly SPARKLE_PRIVATE_KEY_VALUE="${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
readonly CLOUDFLARE_API_TOKEN_VALUE="${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required}"
readonly CLOUDFLARE_ACCOUNT_ID_VALUE="${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required}"
unset SPARKLE_PRIVATE_KEY CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly UPDATES_DIRECTORY="${REPOSITORY_ROOT}/build/sparkle-updates"
readonly PUBLIC_DIRECTORY="${REPOSITORY_ROOT}/deploy/appcast-worker/public"
readonly WORKER_DIRECTORY="${REPOSITORY_ROOT}/deploy/appcast-worker"
KEY_PATH=""
STAGING_DIRECTORY=""

cleanup() {
    if [[ -n "${KEY_PATH}" ]]; then
        rm -f "${KEY_PATH}"
    fi
    if [[ -n "${STAGING_DIRECTORY}" ]]; then
        rm -rf "${STAGING_DIRECTORY}"
    fi
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

stage_appcast_assets() {
    local current_relative_path
    local sibling_feed_url
    local sibling_relative_path

    case "${RELEASE_TRACK}" in
        prerelease)
            current_relative_path="prerelease/appcast.xml"
            sibling_relative_path="appcast.xml"
            sibling_feed_url="https://goodkind.io/fancurve/appcast.xml"
            ;;
        stable)
            current_relative_path="appcast.xml"
            sibling_relative_path="prerelease/appcast.xml"
            sibling_feed_url="https://goodkind.io/fancurve/prerelease/appcast.xml"
            ;;
        *)
            printf 'deploy-appcast: RELEASE_TRACK must be prerelease or stable\n' >&2
            return 1
            ;;
    esac

    STAGING_DIRECTORY="$(mktemp -d "${RUNNER_TEMP}/fancurve-appcast.XXXXXX")"
    mkdir -p \
        "${STAGING_DIRECTORY}/$(dirname "${current_relative_path}")" \
        "${STAGING_DIRECTORY}/$(dirname "${sibling_relative_path}")"
    cp "${UPDATES_DIRECTORY}/appcast.xml" \
        "${STAGING_DIRECTORY}/${current_relative_path}"
    curl \
        --fail \
        --location \
        --show-error \
        --silent \
        --output "${STAGING_DIRECTORY}/${sibling_relative_path}" \
        "${sibling_feed_url}"
    if [[ ! -s "${STAGING_DIRECTORY}/${sibling_relative_path}" ]]; then
        printf 'deploy-appcast: preserved sibling appcast is empty\n' >&2
        return 1
    fi

    mkdir -p \
        "${PUBLIC_DIRECTORY}/$(dirname "${current_relative_path}")" \
        "${PUBLIC_DIRECTORY}/$(dirname "${sibling_relative_path}")"
    cp "${STAGING_DIRECTORY}/${current_relative_path}" \
        "${PUBLIC_DIRECTORY}/${current_relative_path}"
    cp "${STAGING_DIRECTORY}/${sibling_relative_path}" \
        "${PUBLIC_DIRECTORY}/${sibling_relative_path}"
}

trap cleanup EXIT
trap handle_interrupt INT
trap handle_termination TERM

cd "${REPOSITORY_ROOT}"
case "${DRY_RUN}" in
    false | true)
        ;;
    *)
        printf 'deploy-appcast: DRY_RUN must be true or false\n' >&2
        exit 1
        ;;
esac

printf 'deploy-appcast: installing dependencies\n'
make install-dependencies

printf 'deploy-appcast: downloading %s release history\n' "${RELEASE_TRACK}"
SPARKLE_UPDATES_DIR="${UPDATES_DIRECTORY}" \
    Scripts/prepare-appcast-history.sh

KEY_PATH="$(mktemp "${RUNNER_TEMP}/fancurve-sparkle-key.XXXXXX")"
chmod 600 "${KEY_PATH}"
printf '%s' "${SPARKLE_PRIVATE_KEY_VALUE}" > "${KEY_PATH}"
printf 'deploy-appcast: generating signed appcast\n'
SPARKLE_PRIVATE_KEY_FILE="${KEY_PATH}" make generate-sparkle-appcast

printf 'deploy-appcast: staging appcast assets\n'
stage_appcast_assets

printf 'deploy-appcast: deploying worker\n'
if [[ "${DRY_RUN}" == "true" ]]; then
    (
        cd "${WORKER_DIRECTORY}"
        CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN_VALUE}" \
            CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID_VALUE}" \
            npx wrangler deploy --dry-run --config wrangler.toml
    )
else
    (
        cd "${WORKER_DIRECTORY}"
        CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN_VALUE}" \
            CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID_VALUE}" \
            npx wrangler deploy --config wrangler.toml
    )
fi
