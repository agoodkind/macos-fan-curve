#!/usr/bin/env bash
#
# Run one named probe of the Sparkle binary-artifact download, so a resolve that
# stalls can be attributed to a single layer. Each probe belongs on its own runner,
# because a cold SwiftPM cache is the precondition for the stall.
#
#   curl                plain HTTPS reach, no SwiftPM
#   default             isolated resolve of Sparkle alone
#   nocreds             the same, with keychain and netrc lookups disabled
#   swiftpm             the command tuist shells out to, run directly
#   swiftpm-nokeychain  the same, with the credential lookup removed
#   swiftpm-nohelper    the same, with the credential helper cleared
#   tuist               `tuist install`, what `make install-dependencies` reaches
#   tuist-nohelper      the same, with the credential helper cleared
#
# A killed process leaves no evidence, so the watchdog records open file
# descriptors, stack samples, and the partial download before it kills one.

set -euo pipefail

readonly SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"
readonly PROBE_NAME="${PROBE_NAME:?PROBE_NAME is required}"
# A healthy resolve takes about twenty seconds, so a probe reaching this cap is
# stalled rather than slow.
readonly PROBE_TIMEOUT_SECONDS="${PROBE_TIMEOUT_SECONDS:-180}"
readonly CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-60}"
readonly SAMPLE_DURATION_SECONDS=5
readonly WATCHDOG_POLL_SECONDS=2
readonly KILL_GRACE_SECONDS=10

readonly ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
diagnostics_dir="${DIAGNOSTICS_DIR:-${repository_root}/sparkle-download-diagnostics}"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/sparkle-probe.XXXXXX")"
child_pids=()
interrupted=0

log() {
    printf '[%s] %s\n' "$(date -u '+%H:%M:%S')" "$*"
}

kill_children() {
    local pid
    for pid in "${child_pids[@]:-}"; do
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
}

cleanup() {
    kill_children
    rm -rf "${work_root}"
}

handle_interrupt() {
    interrupted=1
    kill_children
    exit 130
}

handle_termination() {
    interrupted=1
    kill_children
    exit 143
}

trap cleanup EXIT
trap handle_interrupt INT
trap handle_termination TERM

record_environment() {
    local report="${diagnostics_dir}/environment.txt"
    {
        printf '## probe\n%s\n' "${PROBE_NAME}"
        printf '\n## host\n'
        sw_vers
        uname -m
        printf '\n## toolchain\n'
        xcodebuild -version 2>&1 || true
        swift --version 2>&1 || true
        if command -v tuist >/dev/null 2>&1; then
            printf 'tuist '
            tuist version 2>&1 || true
        else
            printf 'tuist absent\n'
        fi
        printf '\n## credential sources\n'
        # Attributes do not decrypt the item, so this cannot hang the way reading
        # the secret does.
        if security find-internet-password -s github.com >/dev/null 2>&1; then
            printf 'keychain github.com entry: present\n'
            security find-internet-password -s github.com 2>&1 || true
        else
            printf 'keychain github.com entry: absent\n'
        fi
        printf '\nkeychain search list:\n'
        security list-keychains 2>&1 || true
        if [[ -f "${HOME}/.netrc" ]]; then
            printf 'netrc: present, %s bytes\n' "$(wc -c < "${HOME}/.netrc" | tr -d ' ')"
        else
            printf 'netrc: absent\n'
        fi
        printf '\n## swiftpm cache before the probe\n'
        du -sk "${HOME}/Library/Caches/org.swift.swiftpm" 2>&1 || printf 'absent\n'
    } > "${report}" 2>&1
    log "environment recorded in ${report}"
}

# Record the credential state under a label, so a probe can show it before and after
# its resolve.
record_credential_state() {
    local label="$1"
    {
        printf '\n## credential state: %s\n' "${label}"
        if security find-internet-password -s github.com >/dev/null 2>&1; then
            printf 'keychain github.com entry: present\n'
            security find-internet-password -s github.com 2>&1 | grep -E '"acct"|"srvr"|"cdat"' || true
        else
            printf 'keychain github.com entry: absent\n'
        fi
        printf 'credential.helper: '
        git config --get-all credential.helper 2>&1 || printf 'unset\n'
    } >> "${diagnostics_dir}/credential-state.txt" 2>&1
}

write_probe_package() {
    local package_dir="$1"
    mkdir -p "${package_dir}/Sources/Probe"
    cat > "${package_dir}/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Probe",
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "${SPARKLE_VERSION}")
  ],
  targets: [.target(name: "Probe")]
)
EOF
    printf 'public let probe = 1\n' > "${package_dir}/Sources/Probe/Probe.swift"
}

# Capture why a process is stuck: the stack sample names the blocking call, open
# descriptors show a child blocked on an undrained pipe, and the partial artifact
# size says whether any bytes arrived.
capture_stall_evidence() {
    local evidence_dir="${diagnostics_dir}/stall"
    mkdir -p "${evidence_dir}"

    log "${PROBE_NAME}: overran ${PROBE_TIMEOUT_SECONDS}s, capturing evidence"

    ps -Ao pid,ppid,stat,wchan,etime,command > "${evidence_dir}/process-table.txt" 2>&1 || true

    local stuck_pids
    stuck_pids="$(pgrep -f 'swift-package|swift package|tuist' || true)"
    printf '%s\n' "${stuck_pids}" > "${evidence_dir}/stuck-pids.txt"

    local pid
    for pid in ${stuck_pids}; do
        # lsof first: sampling takes seconds, and a process that exits during it
        # leaves an empty descriptor list.
        lsof -p "${pid}" > "${evidence_dir}/lsof-${pid}.txt" 2>&1 || true
        sample "${pid}" "${SAMPLE_DURATION_SECONDS}" \
            -file "${evidence_dir}/sample-${pid}.txt" >/dev/null 2>&1 || true
    done

    netstat -an > "${evidence_dir}/netstat.txt" 2>&1 || true
    find "${HOME}/Library/Caches/org.swift.swiftpm" "${work_root}" "${repository_root}/Tuist" \
        -type f -name '*.zip*' -exec ls -la {} + \
        > "${evidence_dir}/partial-downloads.txt" 2>&1 || true

    log "${PROBE_NAME}: evidence in ${evidence_dir}"
}

probe_failed=0

record_outcome() {
    printf '%s\t%s\t%ss\n' "${PROBE_NAME}" "$1" "$2" >> "${diagnostics_dir}/summary.tsv"
    # A stall and a non-zero exit are both findings, so both must fail the job.
    if [[ "$1" != "PASSED" ]]; then
        probe_failed=1
    fi
}

# Run one command under the watchdog, streaming its output to a log file.
run_watched() {
    local probe_log="${diagnostics_dir}/${PROBE_NAME}.log"

    log "${PROBE_NAME}: starting"
    local started_at="${SECONDS}"

    "$@" > "${probe_log}" 2>&1 &
    local probe_pid=$!
    child_pids+=("${probe_pid}")

    local elapsed=0
    while kill -0 "${probe_pid}" 2>/dev/null; do
        if (( interrupted == 1 )); then
            return 130
        fi
        if (( elapsed >= PROBE_TIMEOUT_SECONDS )); then
            capture_stall_evidence
            # A stalled resolve is blocked in a mach call and may never act on
            # SIGTERM, so escalate rather than waiting forever and losing the
            # evidence upload to the job's own timeout.
            kill -TERM "${probe_pid}" 2>/dev/null || true
            local grace=0
            while kill -0 "${probe_pid}" 2>/dev/null && (( grace < KILL_GRACE_SECONDS )); do
                sleep 1
                grace=$(( grace + 1 ))
            done
            kill -KILL "${probe_pid}" 2>/dev/null || true
            wait "${probe_pid}" 2>/dev/null || true
            record_outcome "STALLED" "${elapsed}"
            return 0
        fi
        sleep "${WATCHDOG_POLL_SECONDS}"
        elapsed=$(( SECONDS - started_at ))
    done

    local probe_status=0
    wait "${probe_pid}" || probe_status=$?
    elapsed=$(( SECONDS - started_at ))

    if (( probe_status == 0 )); then
        record_outcome "PASSED" "${elapsed}"
        log "${PROBE_NAME}: completed in ${elapsed}s"
    else
        record_outcome "FAILED(${probe_status})" "${elapsed}"
        log "${PROBE_NAME}: exited ${probe_status} after ${elapsed}s"
    fi
    return 0
}

# An isolated resolve of Sparkle alone, with its own cache and scratch trees so it
# cannot read or warm anything the real build uses.
run_isolated_resolve() {
    local package_dir="${work_root}/${PROBE_NAME}"
    write_probe_package "${package_dir}"
    run_watched env -C "${package_dir}" swift package resolve \
        --cache-path "${package_dir}/cache" \
        --scratch-path "${package_dir}/scratch" \
        --verbose "$@"
}

# Apply the fix under test: the token rides in the rewritten URL, so the helper only
# stores the item SwiftPM blocks on. Clearing an existing item matters because
# SwiftPM blocks on whichever one it finds.
clear_credential_helper() {
    record_credential_state "before the fix"
    # --replace-all, because a persistent runner's global config can already hold
    # several helper values, and assigning one value over many fails.
    git config --global --replace-all credential.helper ""
    while security delete-internet-password -s github.com >/dev/null 2>&1; do
        printf 'removed one github.com keychain item\n'
    done
    record_credential_state "after the fix, before the resolve"
}

run_curl_probe() {
    local probe_log="${diagnostics_dir}/curl.log"
    log "curl: starting"
    local started_at="${SECONDS}"
    local curl_status=0
    # --fail, so an HTTP 4xx or 5xx is a failure rather than a zero-exit PASSED.
    curl --fail --silent --show-error --location \
        --max-time "${CURL_TIMEOUT_SECONDS}" \
        --output "${work_root}/curl-artifact.zip" \
        --write-out 'http_code=%{http_code} size=%{size_download} time=%{time_total}\n' \
        "${ARTIFACT_URL}" > "${probe_log}" 2>&1 || curl_status=$?
    local elapsed=$(( SECONDS - started_at ))
    if (( curl_status == 0 )); then
        record_outcome "PASSED" "${elapsed}"
    else
        record_outcome "FAILED(${curl_status})" "${elapsed}"
    fi
    log "curl: $(cat "${probe_log}")"
}

mkdir -p "${diagnostics_dir}"
printf 'probe\toutcome\telapsed\n' > "${diagnostics_dir}/summary.tsv"

log "probe ${PROBE_NAME} against ${ARTIFACT_URL}"
record_environment

case "${PROBE_NAME}" in
    curl)
        run_curl_probe
        ;;
    default)
        run_isolated_resolve
        ;;
    nocreds)
        run_isolated_resolve --disable-keychain --disable-netrc
        ;;
    swiftpm)
        # Uses the default caches, as tuist's own child resolve does.
        run_watched swift package --package-path "${repository_root}/Tuist" resolve
        ;;
    swiftpm-nokeychain)
        run_watched swift package --package-path "${repository_root}/Tuist" resolve \
            --disable-keychain --disable-netrc
        ;;
    swiftpm-nohelper)
        clear_credential_helper
        run_watched swift package --package-path "${repository_root}/Tuist" resolve
        record_credential_state "after the resolve"
        ;;
    tuist)
        run_watched tuist install --verbose
        ;;
    tuist-nohelper)
        clear_credential_helper
        run_watched tuist install --verbose
        record_credential_state "after the resolve"
        ;;
    *)
        printf 'diagnose-sparkle-download: unknown PROBE_NAME %s\n' "${PROBE_NAME}" >&2
        exit 1
        ;;
esac

printf '\n'
log "summary"
cat "${diagnostics_dir}/summary.tsv"

# Reporting green while the probe was killed at its cap is how the first matrix
# run looked like five passes.
if (( probe_failed == 1 )); then
    printf 'diagnose-sparkle-download: %s did not pass\n' "${PROBE_NAME}" >&2
    exit 1
fi
