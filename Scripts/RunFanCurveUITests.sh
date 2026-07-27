#!/usr/bin/env bash

set -euo pipefail

required_variable() {
    local variable_name="$1"
    local variable_value="${!variable_name:-}"

    if [[ -z "$variable_value" ]]; then
        echo "test-ui: $variable_name is required" >&2
        return 1
    fi
}

validate_output_path() {
    local output_path="$1"

    if [[ "$output_path" != /* ]]; then
        echo "test-ui: UI_TEST_RESULT_BUNDLE_PATH must be absolute: $output_path" >&2
        return 1
    fi
    if [[ "$output_path" != *.xcresult ]]; then
        echo "test-ui: UI_TEST_RESULT_BUNDLE_PATH must end in .xcresult: $output_path" >&2
        return 1
    fi
}

validate_derived_data_path() {
    local derived_data_path="$1"
    local workspace_path="$2"
    local workspace_root="${workspace_path%/*}"

    if [[ "$derived_data_path" != /* ]]; then
        echo "test-ui: UI_TEST_DERIVED_DATA_PATH must be absolute: $derived_data_path" >&2
        return 1
    fi
    if [[ "$derived_data_path" != "$workspace_root"/*/UITests ]]; then
        echo "test-ui: refusing unsafe derived data path: $derived_data_path" >&2
        return 1
    fi
}

collect_result_bundle() {
    local logs_directory="$1"
    local result_bundle_path="$2"
    local result_parent="${result_bundle_path%/*}"
    local -a result_bundles

    mkdir -p "$result_parent"
    rm -rf -- "$result_bundle_path"
    shopt -s nullglob
    result_bundles=("$logs_directory"/Test-FanCurveUITests-*.xcresult)
    shopt -u nullglob
    if [[ "${#result_bundles[@]}" -eq 0 ]]; then
        echo \
            "test-ui: no fresh FanCurveUITests result bundle exists in $logs_directory" \
            >&2
        return 1
    fi
    if [[ "${#result_bundles[@]}" -ne 1 ]]; then
        echo \
            "test-ui: expected one FanCurveUITests result bundle in $logs_directory, found ${#result_bundles[@]}" \
            >&2
        return 1
    fi

    cp -R "${result_bundles[0]}" "$result_bundle_path"
    echo "test-ui: result_bundle=$result_bundle_path"
}

run_ui_tests() {
    required_variable SWIFT_MK_BIN
    required_variable FANCURVE_GENERATOR
    required_variable UI_TEST_WORKSPACE
    required_variable UI_TEST_DERIVED_DATA_PATH
    required_variable UI_TEST_SESSION_PATH
    required_variable UI_TEST_RESULT_BUNDLE_PATH
    required_variable UI_TEST_CANONICAL_APP_PATH
    validate_output_path "$UI_TEST_RESULT_BUNDLE_PATH"
    validate_derived_data_path "$UI_TEST_DERIVED_DATA_PATH" "$UI_TEST_WORKSPACE"

    if [[ "$UI_TEST_SESSION_PATH" != /* ]]; then
        echo "test-ui: UI_TEST_SESSION_PATH must be absolute: $UI_TEST_SESSION_PATH" >&2
        return 1
    fi
    if [[ ! -f "$UI_TEST_SESSION_PATH/control.json" ]]; then
        echo \
            "test-ui: session control state is missing: $UI_TEST_SESSION_PATH/control.json" \
            >&2
        return 1
    fi
    if [[ "$UI_TEST_CANONICAL_APP_PATH" != "/Applications/Fan Curve.app" ]]; then
        echo \
            "test-ui: canonical app path must be /Applications/Fan Curve.app" \
            >&2
        return 1
    fi
    if [[ ! -d "$UI_TEST_CANONICAL_APP_PATH" ]]; then
        echo "test-ui: canonical app is missing: $UI_TEST_CANONICAL_APP_PATH" >&2
        return 1
    fi

    Scripts/ValidateFanCurveUITestAgentSession.swift \
        "$UI_TEST_CANONICAL_APP_PATH" \
        "$UI_TEST_SESSION_PATH"

    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        "$SWIFT_MK_BIN" verify-signing artifacts "$UI_TEST_CANONICAL_APP_PATH"

    rm -rf -- "$UI_TEST_RESULT_BUNDLE_PATH"
    rm -rf -- "$UI_TEST_DERIVED_DATA_PATH"
    local test_status=0
    if "$SWIFT_MK_BIN" toolchain test \
        --generator "$FANCURVE_GENERATOR" \
        --workspace "$UI_TEST_WORKSPACE" \
        --scheme FanCurveUITests \
        --configuration Debug \
        --destination "platform=macOS,arch=arm64" \
        --derived-data-path "$UI_TEST_DERIVED_DATA_PATH" \
        "FANCURVE_TEST_CONTROL_PATH=$UI_TEST_SESSION_PATH" \
        "BUNDLE_ID_PREFIX=$BUNDLE_ID_PREFIX" \
        "HELPER_BUNDLE_ID=$HELPER_BUNDLE_ID" \
        "APP_BUNDLE_ID=$APP_BUNDLE_ID" \
        "AGENT_BUNDLE_ID=$AGENT_BUNDLE_ID" \
        "SHARED_SUITE_ID=$SHARED_SUITE_ID" \
        "HELPER_DISPLAY_NAME=$HELPER_DISPLAY_NAME" \
        "APP_DISPLAY_NAME=$APP_DISPLAY_NAME" \
        "AGENT_DISPLAY_NAME=$AGENT_DISPLAY_NAME" \
        "AGENT_EXECUTABLE_NAME=$AGENT_EXECUTABLE_NAME" \
        "SPARKLE_FEED_URL=$SPARKLE_FEED_URL" \
        "SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_ED_KEY"
    then
        echo "test-ui: UI scenarios passed"
    else
        test_status=$?
        echo \
            "test-ui: UI scenarios failed with status $test_status; collecting result bundle" \
            >&2
    fi

    collect_result_bundle \
        "$UI_TEST_DERIVED_DATA_PATH/Logs/Test" \
        "$UI_TEST_RESULT_BUNDLE_PATH"
    if [[ "$test_status" -ne 0 ]]; then
        return "$test_status"
    fi
}

if [[ "${1:-}" == "collect-result-bundle" ]]; then
    if [[ "$#" -ne 3 ]]; then
        echo \
            "usage: RunFanCurveUITests.sh collect-result-bundle LOGS_DIRECTORY RESULT_BUNDLE" \
            >&2
        exit 1
    fi
    validate_output_path "$3"
    collect_result_bundle "$2" "$3"
    exit $?
fi

run_ui_tests
