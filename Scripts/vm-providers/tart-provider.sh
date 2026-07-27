#!/usr/bin/env bash

# Tart implementation of the disposable-VM provider contract documented in
# Docs/e2e-vm-provider-contract.md. Scripts/EndToEndVM.swift never names Tart,
# sshpass, or ssh directly; it only invokes the verbs below. A different
# provider script implementing the same verbs runs against a different VM tool
# without any change to the generic runner or the guest workflow.

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly SOURCE_SHARE_TAG="source"
readonly ARTIFACT_SHARE_TAG="artifacts"
readonly SHARED_FILES_ROOT="/Volumes/My Shared Files"
readonly SSH_CONNECT_TIMEOUT_SECONDS=5
readonly SSH_ADDRESS_WAIT_SECONDS=1
readonly STOP_TIMEOUT_SECONDS=30

guest_user() {
    printf '%s' "${E2E_VM_SSH_USER:-admin}"
}

# The password has no fallback: a hardcoded default in this layer is exactly the
# credential-leak shape the generic runner is designed to avoid, so a missing
# password fails loudly here instead of silently trying a stock guest default.
guest_password() {
    if [[ -z "${E2E_VM_SSH_PASSWORD:-}" ]]; then
        echo "tart-provider: E2E_VM_SSH_PASSWORD is required" >&2
        return 1
    fi
    printf '%s' "$E2E_VM_SSH_PASSWORD"
}

instance_address() {
    local instance_name="$1"

    tart ip "$instance_name" --wait "$SSH_ADDRESS_WAIT_SECONDS"
}

ssh_exec() {
    local instance_name="$1"
    local remote_command="$2"
    local address
    local password

    address="$(instance_address "$instance_name")" || return 1
    password="$(guest_password)" || return 1
    SSHPASS="$password" sshpass -e ssh \
        -o "ConnectTimeout=$SSH_CONNECT_TIMEOUT_SECONDS" \
        -o "IdentitiesOnly=yes" \
        -o "PreferredAuthentications=password" \
        -o "StrictHostKeyChecking=no" \
        -o "UserKnownHostsFile=/dev/null" \
        -o "LogLevel=ERROR" \
        "$(guest_user)@$address" \
        "$remote_command"
}

cmd_describe() {
    printf 'tart %s\n' "$(tart --version 2>/dev/null || echo unknown)"
}

cmd_require_image() {
    local image_id="$1"
    local names

    names="$(tart list --source local --quiet)"
    if ! printf '%s\n' "$names" | grep -Fxq -- "$image_id"; then
        echo "tart-provider: base image is missing: $image_id" >&2
        return 1
    fi
}

cmd_clone() {
    local image_id="$1"
    local instance_name="$2"

    tart clone "$image_id" "$instance_name"
}

cmd_start() {
    local instance_name="$1"
    local source_path=""
    local artifact_path=""

    shift
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --source)
                source_path="$2"
                shift 2
                ;;
            --artifacts)
                artifact_path="$2"
                shift 2
                ;;
            *)
                echo "tart-provider: unknown start argument: $1" >&2
                return 1
                ;;
        esac
    done
    if [[ -z "$source_path" || -z "$artifact_path" ]]; then
        echo "tart-provider: start requires --source and --artifacts" >&2
        return 1
    fi

    exec tart run \
        --no-graphics \
        --no-audio \
        --no-clipboard \
        "--dir=$SOURCE_SHARE_TAG:$source_path:ro" \
        "--dir=$ARTIFACT_SHARE_TAG:$artifact_path" \
        "$instance_name"
}

cmd_mount_path() {
    local tag="$2"

    if [[ "$tag" != "$SOURCE_SHARE_TAG" && "$tag" != "$ARTIFACT_SHARE_TAG" ]]; then
        echo "tart-provider: unknown mount tag: $tag" >&2
        return 1
    fi
    printf '%s/%s\n' "$SHARED_FILES_ROOT" "$tag"
}

cmd_exec() {
    local instance_name="$1"
    local separator="$2"
    local remote_command="$3"

    if [[ "$separator" != "--" ]]; then
        echo "tart-provider: exec requires INSTANCE -- COMMAND" >&2
        return 1
    fi
    ssh_exec "$instance_name" "$remote_command"
}

cmd_ready() {
    local instance_name="$1"

    ssh_exec "$instance_name" "/usr/bin/pgrep -f tart-guest-agent"
}

cmd_address() {
    local instance_name="$1"

    instance_address "$instance_name" 2>/dev/null || echo "n/a"
}

cmd_stop() {
    local instance_name="$1"

    tart stop "$instance_name" --timeout "$STOP_TIMEOUT_SECONDS"
}

cmd_delete() {
    local instance_name="$1"

    tart delete "$instance_name"
}

verb="${1:-}"
if [[ -z "$verb" ]]; then
    echo "usage: tart-provider.sh <verb> [arguments...]" >&2
    exit 1
fi
shift

case "$verb" in
    describe)
        cmd_describe
        ;;
    require-image)
        cmd_require_image "$1"
        ;;
    clone)
        cmd_clone "$1" "$2"
        ;;
    start)
        cmd_start "$@"
        ;;
    mount-path)
        cmd_mount_path "$1" "$2"
        ;;
    exec)
        cmd_exec "$1" "$2" "$3"
        ;;
    ready)
        cmd_ready "$1"
        ;;
    address)
        cmd_address "$1"
        ;;
    stop)
        cmd_stop "$1"
        ;;
    delete)
        cmd_delete "$1"
        ;;
    *)
        echo "tart-provider: unknown verb: $verb" >&2
        exit 1
        ;;
esac
