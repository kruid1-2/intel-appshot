#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex Computer Use"
PROCESS_NAME="SkyComputerUseService"
BUNDLE_ID="com.openai.sky.CUAService"
MIN_SYSTEM_VERSION="14.0"
SIGNING_IDENTITY="${CODEX_COMPUTER_USE_SIGNING_IDENTITY:-Codex Computer Use Local Development}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
INSTALL_DIR="${CODEX_COMPUTER_USE_INSTALL_DIR:-${HOME:?HOME is required}/.codex/computer-use}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

resolve_signing_identity() {
  local matches
  local match_count

  matches="$(/usr/bin/security find-identity -p codesigning -v \
    | awk -v label="\"$SIGNING_IDENTITY\"" 'index($0, label) { print $2 }')"
  if [[ -z "$matches" ]]; then
    printf 'signing identity not found: %s\n' "$SIGNING_IDENTITY" >&2
    return 1
  fi

  match_count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  if [[ "$match_count" -ne 1 ]]; then
    printf 'signing identity is not unique: %s (%s matches)\n' \
      "$SIGNING_IDENTITY" "$match_count" >&2
    return 1
  fi

  printf '%s\n' "$matches"
}

verify_signed_bundle() {
  local bundle_path="$1"
  local actual_bundle_identifier
  local signing_details
  local actual_designated_requirement

  actual_bundle_identifier="$(
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
      "$bundle_path/Contents/Info.plist"
  )"
  if [[ "$actual_bundle_identifier" != "$BUNDLE_ID" ]]; then
    printf 'unexpected Bundle Identifier: expected %s, got %s\n' \
      "$BUNDLE_ID" "$actual_bundle_identifier" >&2
    return 1
  fi

  /usr/bin/xattr -cr "$bundle_path"
  /usr/bin/codesign --verify --strict --verbose=2 "$bundle_path"
  /usr/bin/xattr -cr "$bundle_path"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle_path"
  /usr/bin/xattr -cr "$bundle_path"
  /usr/bin/codesign --verify -R="$EXPLICIT_REQUIREMENT" --verbose=2 "$bundle_path"

  signing_details="$(/usr/bin/codesign -dvvv "$bundle_path" 2>&1)"
  if ! grep -Fqx "Identifier=$BUNDLE_ID" <<<"$signing_details"; then
    printf 'signed Identifier does not match %s\n' "$BUNDLE_ID" >&2
    return 1
  fi
  if ! grep -Fqx "Authority=$SIGNING_IDENTITY" <<<"$signing_details"; then
    printf 'signing Authority does not match %s\n' "$SIGNING_IDENTITY" >&2
    return 1
  fi

  actual_designated_requirement="$(
    /usr/bin/codesign -d -r- "$bundle_path" 2>&1 \
      | awk '/^designated => / { print; exit }'
  )"
  if [[ "$actual_designated_requirement" != "$DESIGNATED_REQUIREMENT" ]]; then
    printf 'unexpected designated requirement:\n  expected: %s\n  actual:   %s\n' \
      "$DESIGNATED_REQUIREMENT" "$actual_designated_requirement" >&2
    return 1
  fi
  if [[ "$actual_designated_requirement" == *cdhash* ]]; then
    printf 'designated requirement must not contain an executable CDHash\n' >&2
    return 1
  fi
}

install_bundle() {
  local staging_root
  local staging_bundle
  local backup_root
  local backup_bundle

  /bin/mkdir -p "$INSTALL_DIR"
  staging_root="$(mktemp -d "$INSTALL_DIR/.codex-cu-install.XXXXXX")"
  staging_bundle="$staging_root/$APP_NAME.app"
  backup_root="$(mktemp -d "$INSTALL_DIR/.codex-cu-backup.XXXXXX")"
  backup_bundle="$backup_root/$APP_NAME.app"

  /usr/bin/ditto "$APP_BUNDLE" "$staging_bundle"
  /usr/bin/xattr -cr "$staging_bundle"
  verify_signed_bundle "$staging_bundle"

  if [[ -e "$INSTALLED_APP_BUNDLE" ]]; then
    /bin/mv "$INSTALLED_APP_BUNDLE" "$backup_bundle"
  fi

  if ! /bin/mv "$staging_bundle" "$INSTALLED_APP_BUNDLE"; then
    if [[ -e "$backup_bundle" ]]; then
      /bin/mv "$backup_bundle" "$INSTALLED_APP_BUNDLE"
    fi
    /bin/rm -rf "$staging_root" "$backup_root"
    return 1
  fi

  if ! verify_signed_bundle "$INSTALLED_APP_BUNDLE"; then
    /bin/rm -rf "$INSTALLED_APP_BUNDLE"
    if [[ -e "$backup_bundle" ]]; then
      /bin/mv "$backup_bundle" "$INSTALLED_APP_BUNDLE"
    fi
    /bin/rm -rf "$staging_root" "$backup_root"
    return 1
  fi

  /bin/rm -rf "$staging_root" "$backup_root"
  printf '%s\n' "$INSTALLED_APP_BUNDLE"
}

build_bundle() {
  local signing_root
  local signing_bundle

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

  signing_root="$(mktemp -d /private/tmp/codex-cu-sign.XXXXXX)"
  signing_bundle="$signing_root/$APP_NAME.app"
  /usr/bin/ditto "$APP_BUNDLE" "$signing_bundle"
  /usr/bin/xattr -cr "$signing_bundle"

  if ! /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY_SHA1" \
    --requirements "=$DESIGNATED_REQUIREMENT" \
    "$signing_bundle"; then
    /bin/rm -rf "$signing_root"
    return 1
  fi
  if ! verify_signed_bundle "$signing_bundle"; then
    /bin/rm -rf "$signing_root"
    return 1
  fi

  /bin/rm -rf "$APP_BUNDLE"
  /usr/bin/ditto "$signing_bundle" "$APP_BUNDLE"
  /bin/rm -rf "$signing_root"
}

SIGNING_IDENTITY_SHA1="$(resolve_signing_identity)"
SIGNING_IDENTITY_SHA1_LOWER="$(
  printf '%s' "$SIGNING_IDENTITY_SHA1" | tr '[:upper:]' '[:lower:]'
)"
EXPLICIT_REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SIGNING_IDENTITY_SHA1_LOWER\""
DESIGNATED_REQUIREMENT="designated => $EXPLICIT_REQUIREMENT"

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
  --install|install)
    install_bundle
    ;;
  *)
    echo "usage: $0 [run|--build|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
