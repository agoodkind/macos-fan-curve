#!/bin/bash
set -euo pipefail

GENERATED_DIR="${DERIVED_FILE_DIR}/Generated"
TEMPLATES_DIR="${SRCROOT}/Templates"

mkdir -p "${GENERATED_DIR}"

GIT_COMMIT=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_VERSION=$(git -C "${SRCROOT}" describe --tags --always --dirty 2>/dev/null || echo "dev")
GIT_DIRTY=$(git -C "${SRCROOT}" diff --quiet 2>/dev/null && echo "false" || echo "true")
GIT_DATE=$(TZ=America/Los_Angeles git -C "${SRCROOT}" log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M %Z' 2>/dev/null || echo "unknown")
GIT_BRANCH=$(git -C "${SRCROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(TZ=America/Los_Angeles date +"%Y-%m-%d %H:%M %Z")
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
AGENT_EXECUTABLE_NAME="${AGENT_EXECUTABLE_NAME:-FanCurveAgent}"

find "${TEMPLATES_DIR}" -name '*.template' | while read -r template; do
  filename=$(basename "${template}" .template)
  sed \
    -e "s|@@HELPER_BUNDLE_ID@@|${HELPER_BUNDLE_ID}|g" \
    -e "s|@@APP_BUNDLE_ID@@|${APP_BUNDLE_ID}|g" \
    -e "s|@@AGENT_BUNDLE_ID@@|${AGENT_BUNDLE_ID}|g" \
    -e "s|@@AGENT_EXECUTABLE_NAME@@|${AGENT_EXECUTABLE_NAME}|g" \
    -e "s|@@SHARED_SUITE_ID@@|${SHARED_SUITE_ID}|g" \
    -e "s|@@DEVELOPMENT_TEAM@@|${DEVELOPMENT_TEAM}|g" \
    -e "s|@@BUNDLE_ID_PREFIX@@|${BUNDLE_ID_PREFIX}|g" \
    -e "s|@@GIT_COMMIT@@|${GIT_COMMIT}|g" \
    -e "s|@@GIT_VERSION@@|${GIT_VERSION}|g" \
    -e "s|@@GIT_DIRTY@@|${GIT_DIRTY}|g" \
    -e "s|@@GIT_DATE@@|${GIT_DATE}|g" \
    -e "s|@@GIT_BRANCH@@|${GIT_BRANCH}|g" \
    -e "s|@@BUILD_DATE@@|${BUILD_DATE}|g" \
    -e "s|@@SPARKLE_FEED_URL@@|${SPARKLE_FEED_URL}|g" \
    -e "s|@@SPARKLE_PUBLIC_ED_KEY@@|${SPARKLE_PUBLIC_ED_KEY}|g" \
    "${template}" > "${GENERATED_DIR}/${filename}"
done
