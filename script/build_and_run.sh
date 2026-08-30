#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex Computer Use"
PROCESS_NAME="SkyComputerUseService"
BUNDLE_ID="com.openai.sky.CUAService"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

build_bundle() {
  env \
    CLANG_MODULE_CACHE_PATH=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/private/tmp/intel-appshot-swiftpm-cache \
    swift build --disable-sandbox --product "$PROCESS_NAME"

  BUILD_BINARY="$(env \
    CLANG_MODULE_CACHE_PATH=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/private/tmp/intel-appshot-swiftpm-cache \
    swift build --disable-sandbox --show-bin-path)/$PROCESS_NAME"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  /usr/libexec/PlistBuddy -c 'Clear dict' "$INFO_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string '$PROCESS_NAME'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string '$BUNDLE_ID'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string '$APP_NAME'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1' "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string '$MIN_SYSTEM_VERSION'" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$INFO_PLIST"
  xattr -cr "$APP_BUNDLE"
  codesign --force --deep --sign - "$APP_BUNDLE"
}

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
build_bundle

case "$MODE" in
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs|--telemetry|telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --build|build)
    printf '%s\n' "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
