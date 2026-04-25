#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
TOOL_NAME="${2:?tool name required}"

matches=()
while IFS= read -r path; do
  matches+=("$path")
done < <(find "$BUILD_DIR" -type f \( -path "*/SourcePackages/artifacts/*/Sparkle/bin/${TOOL_NAME}" -o -path "*/SourcePackages/checkouts/Sparkle/bin/${TOOL_NAME}" \) 2>/dev/null | sort)

if [ "${#matches[@]}" -eq 0 ]; then
  echo "Could not locate Sparkle tool ${TOOL_NAME} under ${BUILD_DIR}" >&2
  exit 1
fi

printf '%s\n' "${matches[0]}"
