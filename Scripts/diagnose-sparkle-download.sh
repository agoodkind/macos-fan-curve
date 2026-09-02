#!/usr/bin/env bash
#
# Attribute the SwiftPM binary-artifact stall that hangs the appcast job.
#
# The appcast job stops forever on "Downloading binary artifact
# .../Sparkle-for-Swift-Package-Manager.zip" whenever the SwiftPM cache misses on a
# hosted runner. This probe runs three variants of that one download so the failing
# layer names itself instead of being inferred:
#
#   curl      plain HTTPS reach for the same URL, no SwiftPM involved
#   default   swift package resolve exactly as the appcast job runs it
#   nocreds   the same resolve with the macOS keychain and netrc lookups disabled
#
# A stall in `default` that `curl` and `nocreds` both clear attributes the hang to
# SwiftPM's credential lookup rather than to the network or the artifact itself.
#
# Every probe runs under a watchdog. When one overruns, the watchdog samples the
# stuck process, records its open files and sockets, and stores the partial download
# size before killing it, because a killed process leaves no evidence otherwise.

set -euo pipefail

readonly SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"
# A healthy resolve of this one dependency takes about ten seconds, and the artifact
# itself downloads in under two. Sixty seconds is well past healthy, so a probe that
# reaches the cap is stalled rather than slow.
readonly PROBE_TIMEOUT_SECONDS="${PROBE_TIMEOUT_SECONDS:-60}"
readonly CURL_TIMEOUT_SECONDS="${CURL_TIMEOUT_SECONDS:-60}"
readonly SAMPLE_DURATION_SECONDS=5
readonly WATCHDOG_POLL_SECONDS=2

readonly ARTIFACT_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-for-Swift-Package-Manager.zip"

diagnostics_dir="${DIAGNOSTICS_DIR:-${PWD}/sparkle-download-diagnostics}"
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
        printf '## host\n'
        sw_vers
        uname -m
        printf '\n## xcode\n'
        xcodebuild -version 2>&1 || true
        swift --version 2>&1 || true
        printf '\n## keychains\n'
        security list-keychains 2>&1 || true
        printf 'default: '
        security default-keychain 2>&1 || true
        printf '\n## github internet-password entries\n'
        # A locked or prompting keychain is the leading suspect, so record whether any
        # github.com credential exists at all before the resolve looks for one.
        if security find-internet-password -s github.com >/dev/null 2>&1; then
            printf 'present\n'
        else
            printf 'absent\n'
        fi
        printf '\n## netrc\n'
        if [[ -f "${HOME}/.netrc" ]]; then
            printf 'present, %s bytes\n' "$(wc -c < "${HOME}/.netrc" | tr -d ' ')"
        else
            printf 'absent\n'
        fi
        printf '\n## git credential config\n'
        git config --list --show-origin 2>&1 | grep -iE 'credential|extraheader|includeif' || printf 'none\n'
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

# Capture why a process is stuck. A stack sample names the blocking call, the open
# sockets say whether a connection was ever established, and the partial artifact size
# says whether any bytes arrived.
capture_stall_evidence() {
    local probe_name="$1"
    local package_dir="$2"
    local evidence_dir="${diagnostics_dir}/${probe_name}-stall"
    mkdir -p "${evidence_dir}"

    log "${probe_name}: overran ${PROBE_TIMEOUT_SECONDS}s, capturing evidence"

    ps -Ao pid,ppid,stat,etime,command > "${evidence_dir}/process-table.txt" 2>&1 || true

    local stuck_pids
    stuck_pids="$(pgrep -f 'swift-package|swift-build|swift package' || true)"
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
    find "${package_dir}" -type f -name '*.zip*' -exec ls -la {} + \
        > "${evidence_dir}/partial-downloads.txt" 2>&1 || true
    du -sk "${package_dir}" > "${evidence_dir}/package-dir-size.txt" 2>&1 || true

    log "${probe_name}: evidence in ${evidence_dir}"
}

# Run one resolve under a watchdog and report elapsed seconds plus outcome.
run_resolve_probe() {
    local probe_name="$1"
    shift
    local package_dir="${work_root}/${probe_name}"
    local probe_log="${diagnostics_dir}/${probe_name}.log"

    write_probe_package "${package_dir}"

    log "${probe_name}: starting resolve"
    local started_at="${SECONDS}"

    (
        cd "${package_dir}"
        swift package resolve \
            --cache-path "${package_dir}/cache" \
            --scratch-path "${package_dir}/scratch" \
            --verbose \
            "$@"
    ) > "${probe_log}" 2>&1 &
    local probe_pid=$!
    child_pids+=("${probe_pid}")

    local elapsed=0
    while kill -0 "${probe_pid}" 2>/dev/null; do
        if (( interrupted == 1 )); then
            return 130
        fi
        if (( elapsed >= PROBE_TIMEOUT_SECONDS )); then
            capture_stall_evidence "${probe_name}" "${package_dir}"
            kill -TERM "${probe_pid}" 2>/dev/null || true
            wait "${probe_pid}" 2>/dev/null || true
            printf '%s\tSTALLED\t%ss\n' "${probe_name}" "${elapsed}" \
                >> "${diagnostics_dir}/summary.tsv"
            return 0
        fi
        sleep "${WATCHDOG_POLL_SECONDS}"
        elapsed=$(( SECONDS - started_at ))
    done

    local probe_status=0
    wait "${probe_pid}" || probe_status=$?
    elapsed=$(( SECONDS - started_at ))

    if (( probe_status == 0 )); then
        printf '%s\tPASSED\t%ss\n' "${probe_name}" "${elapsed}" \
            >> "${diagnostics_dir}/summary.tsv"
        log "${probe_name}: resolved in ${elapsed}s"
    else
        printf '%s\tFAILED(%s)\t%ss\n' "${probe_name}" "${probe_status}" "${elapsed}" \
            >> "${diagnostics_dir}/summary.tsv"
        log "${probe_name}: exited ${probe_status} after ${elapsed}s"
    fi
    return 0
}

run_curl_probe() {
    local probe_log="${diagnostics_dir}/curl.log"
    log "curl: starting"
    local started_at="${SECONDS}"
    local curl_status=0
    curl --silent --show-error --location \
        --max-time "${CURL_TIMEOUT_SECONDS}" \
        --output "${work_root}/curl-artifact.zip" \
        --write-out 'http_code=%{http_code} size=%{size_download} time=%{time_total} url=%{url_effective}\n' \
        "${ARTIFACT_URL}" > "${probe_log}" 2>&1 || curl_status=$?
    local elapsed=$(( SECONDS - started_at ))
    if (( curl_status == 0 )); then
        printf 'curl\tPASSED\t%ss\n' "${elapsed}" >> "${diagnostics_dir}/summary.tsv"
    else
        printf 'curl\tFAILED(%s)\t%ss\n' "${curl_status}" "${elapsed}" \
            >> "${diagnostics_dir}/summary.tsv"
    fi
    log "curl: $(cat "${probe_log}")"
}

mkdir -p "${diagnostics_dir}"
printf 'probe\toutcome\telapsed\n' > "${diagnostics_dir}/summary.tsv"

log "artifact ${ARTIFACT_URL}"
record_environment
run_curl_probe
run_resolve_probe "default"
run_resolve_probe "nocreds" --disable-keychain --disable-netrc

printf '\n'
log "summary"
cat "${diagnostics_dir}/summary.tsv"
