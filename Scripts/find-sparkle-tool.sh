#!/bin/bash
set -euo pipefail

BUILD_DIR="${1:-build}"
TOOL_NAME="${2:?tool name required}"

search_roots=(
  "$BUILD_DIR"
  "Tuist/.build/artifacts"
  "Tuist/.build/checkouts"
  "Tuist/.build"
)

matches=()
for root in "${search_roots[@]}"; do
  if [ ! -d "$root" ]; then
    continue
  fi

  while IFS= read -r path; do
    matches+=("$path")
  done < <(find "$root" -type f \( \
    -path "*/SourcePackages/artifacts/*/Sparkle/bin/${TOOL_NAME}" -o \
    -path "*/SourcePackages/checkouts/Sparkle/bin/${TOOL_NAME}" -o \
    -path "*/artifacts/*/Sparkle/bin/${TOOL_NAME}" -o \
    -path "*/checkouts/Sparkle/bin/${TOOL_NAME}" \
  \) 2>/dev/null | sort)
done

if [ "${#matches[@]}" -eq 0 ]; then
  echo "Could not locate Sparkle tool ${TOOL_NAME}" >&2
  exit 1
fi

printf '%s\n' "${matches[0]}"
