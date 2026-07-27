#!/usr/bin/env bash

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

readonly CANONICAL_APP_PATH="/Applications/Fan Curve.app"
readonly AGENT_LABEL="io.goodkind.fancurveagent"
readonly HELPER_LABEL="io.goodkind.smcfanhelper"
readonly SHARED_SUITE_ID="io.goodkind.fancurve.shared"
readonly TUIST_VERSION="4.195.14"
readonly TUIST_TEAM_ID="U6LC622NKF"
readonly EXPECTED_RELEASE_TEAM_ID="H3BMXM4W7H"

declare -a child_pids=()
interrupted=0
workflow_started=0
workflow_mode=""
guest_repo=""
test_control_session=""

required_variable() {
    local variable_name="$1"
    local variable_value="${!variable_name:-}"

    if [[ -z "$variable_value" ]]; then
        echo "e2e-guest: $variable_name is required" >&2
        return 1
    fi
}

validate_mode() {
    local mode="$1"

    if [[ "$mode" != "debug" && "$mode" != "release-smoke" ]]; then
        echo "e2e-guest: unsupported mode: $mode" >&2
        return 1
    fi
}

source_mount_is_read_only() {
    local probe_path="$FANCURVE_E2E_SOURCE_MOUNT/.e2e-read-only-probe-$$"

    if /usr/bin/touch "$probe_path" 2>/dev/null; then
        /bin/rm -f -- "$probe_path"
        return 1
    fi
    return 0
}

validate_environment() {
    local mode="$1"

    validate_mode "$mode"
    required_variable FANCURVE_E2E_SOURCE_MOUNT
    required_variable FANCURVE_E2E_ARTIFACT_MOUNT
    required_variable FANCURVE_E2E_GUEST_WORKSPACE
    required_variable FANCURVE_E2E_RUN_ID
    if [[ "$mode" == "release-smoke" ]]; then
        required_variable FANCURVE_E2E_RELEASE_APP_SOURCE
        required_variable FANCURVE_E2E_RELEASE_XCTESTRUN_PATH
    fi

    if [[ "$FANCURVE_E2E_SOURCE_MOUNT" != /* ]]; then
        echo \
            "e2e-guest: source mount must be absolute: $FANCURVE_E2E_SOURCE_MOUNT" \
            >&2
        return 1
    fi
    if [[ "$FANCURVE_E2E_ARTIFACT_MOUNT" != /* ]]; then
        echo \
            "e2e-guest: artifact mount must be absolute: $FANCURVE_E2E_ARTIFACT_MOUNT" \
            >&2
        return 1
    fi
    if [[ "$FANCURVE_E2E_GUEST_WORKSPACE" != /* ]]; then
        echo \
            "e2e-guest: guest workspace must be absolute: $FANCURVE_E2E_GUEST_WORKSPACE" \
            >&2
        return 1
    fi
    if [[ ! -d "$FANCURVE_E2E_SOURCE_MOUNT" ]]; then
        echo \
            "e2e-guest: source mount is missing: $FANCURVE_E2E_SOURCE_MOUNT" \
            >&2
        return 1
    fi
    if ! source_mount_is_read_only; then
        echo \
            "e2e-guest: source mount must be read-only: $FANCURVE_E2E_SOURCE_MOUNT" \
            >&2
        return 1
    fi
    if [[ ! -d "$FANCURVE_E2E_ARTIFACT_MOUNT" ]]; then
        echo \
            "e2e-guest: artifact mount is missing: $FANCURVE_E2E_ARTIFACT_MOUNT" \
            >&2
        return 1
    fi
    if [[ ! -w "$FANCURVE_E2E_ARTIFACT_MOUNT" ]]; then
        echo \
            "e2e-guest: artifact mount must be writable: $FANCURVE_E2E_ARTIFACT_MOUNT" \
            >&2
        return 1
    fi
    if [[ "$FANCURVE_E2E_SOURCE_MOUNT" == "$FANCURVE_E2E_ARTIFACT_MOUNT" ]]; then
        echo "e2e-guest: source and artifact mounts must be distinct" >&2
        return 1
    fi
    if [[ "$FANCURVE_E2E_GUEST_WORKSPACE" == "$FANCURVE_E2E_SOURCE_MOUNT" ]]; then
        echo "e2e-guest: guest workspace must not be the source mount" >&2
        return 1
    fi
    if [[ "$FANCURVE_E2E_GUEST_WORKSPACE" == "$FANCURVE_E2E_ARTIFACT_MOUNT" ]]; then
        echo "e2e-guest: guest workspace must not be the artifact mount" >&2
        return 1
    fi
    if [[ "$mode" == "release-smoke" ]]; then
        if [[ "$FANCURVE_E2E_RELEASE_APP_SOURCE" != /* ]]; then
            echo \
                "e2e-guest: Release app source must be absolute: $FANCURVE_E2E_RELEASE_APP_SOURCE" \
                >&2
            return 1
        fi
        if [[ ! -d "$FANCURVE_E2E_RELEASE_APP_SOURCE" ]]; then
            echo \
                "e2e-guest: Release app source is missing: $FANCURVE_E2E_RELEASE_APP_SOURCE" \
                >&2
            return 1
        fi
        if [[ "$FANCURVE_E2E_RELEASE_XCTESTRUN_PATH" != /* ]]; then
            echo \
                "e2e-guest: Release xctestrun path must be absolute: $FANCURVE_E2E_RELEASE_XCTESTRUN_PATH" \
                >&2
            return 1
        fi
        if [[ ! -f "$FANCURVE_E2E_RELEASE_XCTESTRUN_PATH" ]]; then
            echo \
                "e2e-guest: Release xctestrun is missing: $FANCURVE_E2E_RELEASE_XCTESTRUN_PATH" \
                >&2
            return 1
        fi
    fi
}

kill_children() {
    local pid

    for pid in "${child_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

handle_interrupt() {
    local signal_name="$1"

    interrupted=1
    echo \
        "e2e-guest: signal=$signal_name action=terminate-children" \
        >&2
    kill_children
}

run_tracked() {
    local operation="$1"
    shift
    local pid
    local pid_index
    local status

    echo "e2e-guest: operation=$operation status=started"
    "$@" &
    pid=$!
    pid_index="${#child_pids[@]}"
    child_pids+=("$pid")
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    unset "child_pids[$pid_index]"
    if [[ "$interrupted" -eq 1 ]]; then
        return 130
    fi
    if [[ "$status" -ne 0 ]]; then
        echo \
            "e2e-guest: operation=$operation status=failed exit=$status" \
            >&2
        return "$status"
    fi
    echo "e2e-guest: operation=$operation status=completed"
}

copy_source() {
    local destination_root="$FANCURVE_E2E_GUEST_WORKSPACE"
    local destination_repo="$destination_root/macos-fan-curve"

    mkdir -p "$destination_root"
    if [[ -e "$destination_repo" ]]; then
        if [[ "$destination_repo" != "$destination_root/macos-fan-curve" ]]; then
            echo \
                "e2e-guest: refusing unsafe guest source destination: $destination_repo" \
                >&2
            return 1
        fi
        rm -rf -- "$destination_repo"
    fi
    mkdir -p "$destination_repo"
    run_tracked source-copy \
        /usr/bin/rsync \
        -a \
        --exclude .git \
        --exclude .build \
        --exclude .make \
        --exclude build \
        --exclude Products \
        --exclude FanCurveApp.xcodeproj \
        --exclude FanCurveApp.xcworkspace \
        "$FANCURVE_E2E_SOURCE_MOUNT/" \
        "$destination_repo/"
    chmod u+rwx "$destination_repo"
    guest_repo="$destination_repo"
    echo \
        "e2e-guest: source_copy=completed source=$FANCURVE_E2E_SOURCE_MOUNT destination=$guest_repo"
}

initialize_guest_git() {
    (
        cd "$guest_repo"
        /usr/bin/git init
        /usr/bin/git -c user.name="Fan Curve E2E Runner" \
            -c user.email="noreply@openai.com" \
            add --all
        /usr/bin/git -c user.name="Fan Curve E2E Runner" \
            -c user.email="noreply@openai.com" \
            commit --no-gpg-sign -m "Stage end-to-end source snapshot"
    )
}

verify_release_source() {
    local expected_manifest="$FANCURVE_E2E_ARTIFACT_MOUNT/host-release/source-files.txt"
    local source_commit="$FANCURVE_E2E_ARTIFACT_MOUNT/host-release/source-commit.txt"
    local actual_manifest="$FANCURVE_E2E_GUEST_WORKSPACE/source-files-guest.txt"
    local commit_value

    if [[ ! -s "$expected_manifest" || ! -s "$source_commit" ]]; then
        echo \
            "e2e-guest: signed host source evidence is missing" \
            >&2
        return 1
    fi
    (
        cd "$guest_repo"
        /usr/bin/git ls-files --stage >"$actual_manifest"
    )
    if ! /usr/bin/cmp -s "$expected_manifest" "$actual_manifest"; then
        echo \
            "e2e-guest: guest source does not match the signed host commit" \
            >&2
        return 1
    fi
    commit_value="$(<"$source_commit")"
    if [[ ! "$commit_value" =~ ^[0-9a-f]{40}$ ]]; then
        echo \
            "e2e-guest: signed host commit identifier is invalid: $commit_value" \
            >&2
        return 1
    fi
    echo \
        "e2e-guest: source_commit=$commit_value signature=host-verified files=matched"
}

verify_release_signature() {
    local artifact_path="$1"
    local evidence_path="$2"
    local team_pattern

    "$guest_repo/Scripts/CaptureCodeSigningEvidence.swift" \
        "$artifact_path" >"$evidence_path"
    printf -v team_pattern '"teamIdentifier" : "%s"' "$EXPECTED_RELEASE_TEAM_ID"
    if ! /usr/bin/grep -Fq "$team_pattern" "$evidence_path"; then
        echo \
            "e2e-guest: Developer ID team verification failed: $artifact_path" \
            >&2
        return 1
    fi
    if ! /usr/bin/grep -Fq \
        "Developer ID Application" \
        "$evidence_path"
    then
        echo \
            "e2e-guest: Developer ID authority verification failed: $artifact_path" \
            >&2
        return 1
    fi
}

prepare_tuist() {
    local tool_directory="$FANCURVE_E2E_GUEST_WORKSPACE/Tooling"
    local archive_path="$tool_directory/tuist.zip"
    local tuist_path="$tool_directory/tuist"
    local signing_evidence="$FANCURVE_E2E_ARTIFACT_MOUNT/codesign-tuist.json"
    local download_url

    if command -v tuist >/dev/null; then
        echo \
            "e2e-guest: tool=tuist source=guest-image path=$(command -v tuist)"
        return
    fi
    download_url="https://github.com/tuist/tuist/releases/download/$TUIST_VERSION/tuist.zip"
    mkdir -p "$tool_directory"
    run_tracked tuist-download \
        /usr/bin/curl \
        --fail \
        --location \
        --silent \
        --show-error \
        "$download_url" \
        --output "$archive_path"
    run_tracked tuist-unpack \
        /usr/bin/ditto \
        -x \
        -k \
        "$archive_path" \
        "$tool_directory"
    if [[ ! -x "$tuist_path" ]]; then
        echo "e2e-guest: downloaded Tuist executable is missing" >&2
        return 1
    fi
    "$guest_repo/Scripts/CaptureCodeSigningEvidence.swift" \
        "$tuist_path" >"$signing_evidence"
    if ! /usr/bin/grep -q "$TUIST_TEAM_ID" "$signing_evidence"; then
        echo \
            "e2e-guest: Tuist signing team verification failed: $signing_evidence" \
            >&2
        return 1
    fi
    export PATH="$tool_directory:$PATH"
    run_tracked tuist-version "$tuist_path" version
    echo \
        "e2e-guest: tool=tuist source=pinned-release version=$TUIST_VERSION path=$tuist_path"
}

run_make() {
    local operation="$1"
    shift

    (
        cd "$guest_repo"
        run_tracked "$operation" /usr/bin/make "$@"
    )
}

record_environment() {
    local output="$FANCURVE_E2E_ARTIFACT_MOUNT/guest-environment.txt"

    {
        echo "run_id=$FANCURVE_E2E_RUN_ID"
        echo "mode=$workflow_mode"
        echo "user=$USER"
        echo "source_mount=$FANCURVE_E2E_SOURCE_MOUNT"
        echo "artifact_mount=$FANCURVE_E2E_ARTIFACT_MOUNT"
        echo "guest_repository=$guest_repo"
        echo "path=$PATH"
        if command -v tuist; then
            tuist version
        else
            echo "tuist=not-required"
        fi
        /usr/bin/sw_vers
        /usr/bin/uname -a
        /usr/bin/xcodebuild -version
        /usr/bin/git --version
        /usr/bin/make --version | /usr/bin/head -n 1
    } >"$output" 2>&1
}

authorize_developer_tools() {
    run_tracked developer-tools-security \
        /usr/bin/sudo -n /usr/sbin/DevToolsSecurity -enable
    run_tracked developer-group \
        /usr/bin/sudo -n /usr/sbin/dseditgroup \
        -o edit \
        -a "$USER" \
        -t user \
        _developer
    echo \
        "e2e-guest: ui_authorization=developer-tools-security account=$USER"
}

run_debug_workflow() {
    local result_bundle="$FANCURVE_E2E_ARTIFACT_MOUNT/FanCurveUITests-Debug.xcresult"
    local control_executable="$guest_repo/build/Build/Products/Debug/FanCurveTestControl"

    test_control_session="$FANCURVE_E2E_GUEST_WORKSPACE/TestControlSession"
    run_make test-control-build \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE="Manual" \
        test-control-build \
        FANCURVE_TEST_CONTROL_PATH="$test_control_session"
    run_tracked test-control-initialize \
        "$control_executable" \
        initialize \
        --session "$test_control_session"
    if [[ ! -f "$test_control_session/control.json" ]]; then
        echo \
            "e2e-guest: TestControl session is invalid: $test_control_session" \
            >&2
        return 1
    fi
    echo \
        "e2e-guest: test_control=valid path=$test_control_session phase=before-app-build"
    run_make debug-install-launch \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE="Manual" \
        run \
        FANCURVE_TEST_CONTROL_PATH="$test_control_session"
    run_make debug-ui-scenarios \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE="Manual" \
        test-ui \
        UI_TEST_SESSION_PATH="$test_control_session" \
        UI_TEST_RESULT_BUNDLE_PATH="$result_bundle"
}

run_release_workflow() {
    local staged_agent="$FANCURVE_E2E_RELEASE_APP_SOURCE/Contents/MacOS/FanCurveAgent"
    local staged_helper="$FANCURVE_E2E_RELEASE_APP_SOURCE/Contents/MacOS/io.goodkind.smcfanhelper"
    local installed_agent="$CANONICAL_APP_PATH/Contents/MacOS/FanCurveAgent"
    local installed_helper="$CANONICAL_APP_PATH/Contents/MacOS/io.goodkind.smcfanhelper"
    local result_bundle="$FANCURVE_E2E_ARTIFACT_MOUNT/FanCurveServiceSmokeTests-Release.xcresult"

    verify_release_source
    verify_release_signature \
        "$FANCURVE_E2E_RELEASE_APP_SOURCE" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-staged-codesign-app.json"
    verify_release_signature \
        "$staged_agent" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-staged-codesign-agent.json"
    verify_release_signature \
        "$staged_helper" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-staged-codesign-helper.json"
    /usr/bin/defaults write "$SHARED_SUITE_ID" curveActive -bool false
    /usr/bin/defaults write "$SHARED_SUITE_ID" boostEnabled -bool false
    run_make release-install \
        install-e2e-release-app \
        E2E_RELEASE_APP_SOURCE="$FANCURVE_E2E_RELEASE_APP_SOURCE"
    verify_release_signature \
        "$CANONICAL_APP_PATH" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-installed-codesign-app.json"
    verify_release_signature \
        "$installed_agent" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-installed-codesign-agent.json"
    verify_release_signature \
        "$installed_helper" \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/guest-installed-codesign-helper.json"
    run_make release-service-smoke \
        test-service-smoke-prebuilt \
        E2E_RELEASE_XCTESTRUN_PATH="$FANCURVE_E2E_RELEASE_XCTESTRUN_PATH" \
        E2E_RELEASE_RESULT_BUNDLE_PATH="$result_bundle"
}

best_effort_capture() {
    local operation="$1"
    local output="$2"
    shift 2
    local status

    if "$@" >"$output" 2>&1; then
        echo \
            "e2e-guest: artifact=$operation status=collected path=$output"
    else
        status=$?
        echo \
            "e2e-guest: artifact=$operation status=failed exit=$status path=$output" \
            >&2
    fi
}

copy_release_result_bundle() {
    local logs_directory="$guest_repo/build/ServiceSmoke/Logs/Test"
    local destination="$FANCURVE_E2E_ARTIFACT_MOUNT/FanCurveServiceSmokeTests-Release.xcresult"
    local -a result_bundles

    shopt -s nullglob
    result_bundles=("$logs_directory"/Test-FanCurveServiceSmokeTests-*.xcresult)
    shopt -u nullglob
    rm -rf -- "$destination"
    if [[ "${#result_bundles[@]}" -ne 1 ]]; then
        echo \
            "e2e-guest: expected one fresh Release smoke result bundle, found ${#result_bundles[@]}" \
            >&2
        return 1
    fi
    cp -R "${result_bundles[0]}" "$destination"
    echo \
        "e2e-guest: artifact=release-xcresult status=collected path=$destination"
}

extract_screenshots() {
    local result_bundle="$1"
    local output_directory="$2"

    rm -rf -- "$output_directory"
    mkdir -p "$output_directory"
    if /usr/bin/xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$output_directory" \
        >"$output_directory/export.log" 2>&1
    then
        echo \
            "e2e-guest: artifact=screenshots status=collected path=$output_directory"
    else
        echo \
            "e2e-guest: artifact=screenshots status=failed path=$output_directory" \
            >&2
    fi
}

collect_test_control_evidence() {
    local control_executable="$guest_repo/build/Build/Products/Debug/FanCurveTestControl"
    local output="$FANCURVE_E2E_ARTIFACT_MOUNT/test-control"

    if [[ -z "$test_control_session" || ! -f "$test_control_session/control.json" ]]; then
        echo \
            "e2e-guest: artifact=test-control status=unavailable reason=session-missing" \
            >&2
        return
    fi
    rm -rf -- "$output"
    if "$control_executable" export-evidence \
        --session "$test_control_session" \
        --output "$output"
    then
        echo \
            "e2e-guest: artifact=test-control status=collected path=$output"
    else
        echo \
            "e2e-guest: artifact=test-control status=failed path=$output" \
            >&2
    fi
}

collect_artifacts() {
    local app_agent="$CANONICAL_APP_PATH/Contents/MacOS/FanCurveAgent"
    local helper="$CANONICAL_APP_PATH/Contents/MacOS/io.goodkind.smcfanhelper"
    local user_id
    local debug_result
    local release_result

    mkdir -p "$FANCURVE_E2E_ARTIFACT_MOUNT"
    user_id="$(/usr/bin/id -u)"
    best_effort_capture app-codesign \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/codesign-app.json" \
        "$guest_repo/Scripts/CaptureCodeSigningEvidence.swift" \
        "$CANONICAL_APP_PATH"
    best_effort_capture agent-codesign \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/codesign-agent.json" \
        "$guest_repo/Scripts/CaptureCodeSigningEvidence.swift" \
        "$app_agent"
    best_effort_capture helper-codesign \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/codesign-helper.json" \
        "$guest_repo/Scripts/CaptureCodeSigningEvidence.swift" \
        "$helper"
    best_effort_capture agent-launchctl \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/launchctl-agent.txt" \
        /bin/launchctl print "gui/$user_id/$AGENT_LABEL"
    best_effort_capture helper-launchctl \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/launchctl-helper.txt" \
        /usr/bin/sudo -n /bin/launchctl print "system/$HELPER_LABEL"
    best_effort_capture service-management \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/service-management.txt" \
        /usr/bin/sudo -n /usr/bin/sfltool dumpbtm
    best_effort_capture processes \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/processes.txt" \
        /bin/ps -axo pid,ppid,user,state,command
    best_effort_capture unified-log-text \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/unified.log" \
        /usr/bin/log show \
        --last 1h \
        --style compact \
        --predicate 'subsystem == "io.goodkind.fan" OR process CONTAINS "FanCurve"'
    best_effort_capture unified-logarchive \
        "$FANCURVE_E2E_ARTIFACT_MOUNT/unified-logarchive.log" \
        /usr/bin/sudo -n /usr/bin/log collect \
        --last 1h \
        --output "$FANCURVE_E2E_ARTIFACT_MOUNT/unified.logarchive"

    debug_result="$FANCURVE_E2E_ARTIFACT_MOUNT/FanCurveUITests-Debug.xcresult"
    if [[ -d "$debug_result" ]]; then
        extract_screenshots \
            "$debug_result" \
            "$FANCURVE_E2E_ARTIFACT_MOUNT/screenshots-debug"
    fi
    release_result="$FANCURVE_E2E_ARTIFACT_MOUNT/FanCurveServiceSmokeTests-Release.xcresult"
    if [[ "$workflow_mode" == "release-smoke" && ! -d "$release_result" ]]; then
        copy_release_result_bundle || true
    fi
    if [[ -d "$release_result" ]]; then
        extract_screenshots \
            "$release_result" \
            "$FANCURVE_E2E_ARTIFACT_MOUNT/screenshots-release"
    fi
    if [[ "$workflow_mode" == "debug" ]]; then
        collect_test_control_evidence
    fi
}

cleanup_workspace() {
    local expected_prefix="/Users/$USER/fan-curve-e2e/"

    if [[ "$FANCURVE_E2E_GUEST_WORKSPACE" != "$expected_prefix"* ]]; then
        echo \
            "e2e-guest: preserving unvalidated workspace: $FANCURVE_E2E_GUEST_WORKSPACE" \
            >&2
        return
    fi
    if [[ "${FANCURVE_E2E_GUEST_WORKSPACE#"$expected_prefix"}" != "$FANCURVE_E2E_RUN_ID" ]]; then
        echo \
            "e2e-guest: preserving mismatched workspace: $FANCURVE_E2E_GUEST_WORKSPACE" \
            >&2
        return
    fi
    rm -rf -- "$FANCURVE_E2E_GUEST_WORKSPACE"
    echo \
        "e2e-guest: cleanup=workspace status=completed path=$FANCURVE_E2E_GUEST_WORKSPACE"
}

handle_exit() {
    local status="$?"

    if [[ "$workflow_started" -eq 1 ]]; then
        collect_artifacts
        cleanup_workspace
    fi
    if [[ "$interrupted" -eq 1 ]]; then
        exit 130
    fi
    exit "$status"
}

run_workflow() {
    local mode="$1"

    validate_environment "$mode"
    workflow_started=1
    workflow_mode="$mode"
    copy_source
    initialize_guest_git
    authorize_developer_tools

    if [[ "$mode" == "debug" ]]; then
        prepare_tuist
        run_make analysis-tools install-analysis-tools
        record_environment
        run_debug_workflow
    else
        record_environment
        run_release_workflow
    fi
}

trap 'handle_interrupt INT' INT
trap 'handle_interrupt TERM' TERM
trap handle_exit EXIT

case "${1:-}" in
    validate-environment)
        if [[ "$#" -ne 2 ]]; then
            echo \
                "usage: e2e-guest.sh validate-environment debug|release-smoke" \
                >&2
            exit 1
        fi
        validate_environment "$2"
        ;;
    copy-source)
        if [[ "$#" -ne 2 ]]; then
            echo \
                "usage: e2e-guest.sh copy-source debug|release-smoke" \
                >&2
            exit 1
        fi
        validate_environment "$2"
        copy_source
        ;;
    run)
        if [[ "$#" -ne 2 ]]; then
            echo "usage: e2e-guest.sh run debug|release-smoke" >&2
            exit 1
        fi
        run_workflow "$2"
        ;;
    *)
        echo \
            "usage: e2e-guest.sh <validate-environment|copy-source|run> debug|release-smoke" \
            >&2
        exit 1
        ;;
esac
