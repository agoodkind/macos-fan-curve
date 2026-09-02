#!/usr/bin/env bash
#
# Attribute the stall that hangs the appcast job on "Downloading binary artifact
# .../Sparkle-for-Swift-Package-Manager.zip".
#
# The job runs `make install-dependencies`, which reaches `tuist install`, which
# shells out to `swift package --package-path <repo>/Tuist resolve`. The stall lands
# on the artifact download line and never returns. This script runs one named probe
# so each layer of that chain can be tested on its own runner, with nothing else
# warming the caches first:
#
#   curl       plain HTTPS reach for the artifact URL, no SwiftPM involved
#   default    an isolated `swift package resolve` of Sparkle alone
#   nocreds    the same isolated resolve with keychain and netrc lookups disabled
#   swiftpm    the exact command tuist shells out to, run directly
#   tuist      `tuist install`, which is what the appcast job actually reaches
#
# `swiftpm` and `tuist` differ by one variable: who invokes the resolve. A stall in
# `tuist` that `swiftpm` clears puts the defect in tuist's handling of the child
# process rather than in SwiftPM, the network, or the artifact.
#
# Every probe runs under a watchdog. When one overruns, the watchdog records the
# stuck process's open file descriptors, samples its stacks, and stores the partial
# download size before killing it, because a killed process leaves no evidence.

set -euo pipefail

readonly SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"
readonly PROBE_NAME="${PROBE_NAME:?PROBE_NAME is required}"
# A healthy resolve of these dependencies takes about twenty seconds on a hosted
# runner, and the artifact itself downloads in under one. Three minutes is well past
# healthy, so a probe that reaches the cap is stalled rather than slow.
readonly PROBE_TIMEOUT_SECONDS="${PROBE_TIMEOUT_SECONDS:-180}"
readonly CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-60}"
readonly SAMPLE_DURATION_SECONDS=5
readonly WATCHDOG_POLL_SECONDS=2

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
        # A blocking keychain lookup was the first suspect, so record whether any
        # github.com credential exists at all before a resolve looks for one.
        if security find-internet-password -s github.com >/dev/null 2>&1; then
            printf 'keychain github.com entry: present\n'
        else
            printf 'keychain github.com entry: absent\n'
        fi
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

# Capture why a process is stuck. Open file descriptors say whether the child is
# blocked writing to a pipe nobody drains, the stack sample names the blocking call,
# and the partial artifact size says whether any bytes ever arrived.
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
        # lsof first: sampling takes seconds, and a process that exits during the
        # sample leaves an empty file-descriptor list behind.
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

record_outcome() {
    printf '%s\t%s\t%ss\n' "${PROBE_NAME}" "$1" "$2" >> "${diagnostics_dir}/summary.tsv"
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
            kill -TERM "${probe_pid}" 2>/dev/null || true
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

run_curl_probe() {
    local probe_log="${diagnostics_dir}/curl.log"
    log "curl: starting"
    local started_at="${SECONDS}"
    local curl_status=0
    curl --silent --show-error --location \
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
        # The exact command `tuist install` shells out to, run directly. It uses the
        # default caches, as tuist's own child does.
        run_watched swift package --package-path "${repository_root}/Tuist" resolve
        ;;
    tuist)
        run_watched tuist install --verbose
        ;;
    *)
        printf 'diagnose-sparkle-download: unknown PROBE_NAME %s\n' "${PROBE_NAME}" >&2
        exit 1
        ;;
esac

printf '\n'
log "summary"
cat "${diagnostics_dir}/summary.tsv"
