#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <app-bundle-path> <hash-stamp-path>" >&2
  exit 1
fi

APP_BUNDLE="$1"
STAMP_PATH="$2"
ICON_PATH="$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
  echo "missing app icon: $ICON_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$STAMP_PATH")"
CURRENT_HASH="$(shasum "$ICON_PATH" | awk '{print $1}')"
PREVIOUS_HASH=""
if [[ -f "$STAMP_PATH" ]]; then
  PREVIOUS_HASH="$(cat "$STAMP_PATH")"
fi

if [[ "$CURRENT_HASH" == "$PREVIOUS_HASH" ]]; then
  echo "app icon unchanged; skipping icon cache refresh"
  exit 0
fi

echo "$CURRENT_HASH" > "$STAMP_PATH"
echo "app icon changed; refreshing macOS icon caches"

qlmanage -r cache >/dev/null 2>&1 || true
killall Dock Finder iconservicesagent iconservicesd 2>/dev/null || true
find "$HOME/Library/Caches" -maxdepth 1 \( -name 'com.apple.iconservices*' -o -name 'com.apple.dock.iconcache' \) -exec rm -rf {} + 2>/dev/null || true
touch "$APP_BUNDLE"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" >/dev/null 2>&1 || true
