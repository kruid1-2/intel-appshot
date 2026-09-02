#!/usr/bin/env bash
set -euo pipefail

WORKFLOW_TEST_MODE=0
WORKFLOW_TEST_ROOT=""
SECURITY_TOOL="/usr/bin/security"
CODESIGN_TOOL="/usr/bin/codesign"
LIPO_TOOL="/usr/bin/lipo"
PLISTBUDDY_TOOL="/usr/libexec/PlistBuddy"
DITTO_TOOL="/usr/bin/ditto"
XATTR_TOOL="/usr/bin/xattr"
SWIFT_TOOL="swift"
PGREP_TOOL="/usr/bin/pgrep"
LSOF_TOOL="/usr/sbin/lsof"
REALPATH_TOOL="/bin/realpath"
OPEN_TOOL="/usr/bin/open"
SLEEP_TOOL="/bin/sleep"
KILL_TOOL="/bin/kill"
LOG_TOOL="/usr/bin/log"
LLDB_TOOL="/usr/bin/lldb"
UUIDGEN_TOOL="/usr/bin/uuidgen"
GIT_TOOL="/usr/bin/git"
STAT_TOOL="/usr/bin/stat"
SHASUM_TOOL="/usr/bin/shasum"
if [[ "${1:-}" == "--workflow-test-mode" ]]; then
  WORKFLOW_TEST_MODE=1
  if [[ "${CODEX_CU_WORKFLOW_TESTING:-}" != "1" ]]; then
    printf 'test workflow root is invalid or missing its sentinel\n' >&2
    exit 1
  fi
  if [[ ! -d "${CODEX_CU_TEST_ROOT:-}" ]]; then
    printf 'test workflow root is invalid or missing its sentinel\n' >&2
    exit 1
  fi
  WORKFLOW_TEST_ROOT="$(cd "$CODEX_CU_TEST_ROOT" && pwd -P)"
  case "$WORKFLOW_TEST_ROOT" in
    /private/tmp/codex-cu-workflow-tests.*|/private/var/folders/*/T/codex-cu-workflow-tests.*)
      ;;
    *)
      printf 'test workflow root is invalid or missing its sentinel\n' >&2
      exit 1
      ;;
  esac
  if [[ ! -f "$WORKFLOW_TEST_ROOT/.codex-cu-workflow-test-root" ]] \
    || [[ "$(/bin/cat "$WORKFLOW_TEST_ROOT/.codex-cu-workflow-test-root")" \
      != "codex-cu-workflow-test-fixture-v1" ]]; then
    printf 'test workflow root is invalid or missing its sentinel\n' >&2
    exit 1
  fi
  TEST_TOOL_DIRECTORY="$WORKFLOW_TEST_ROOT/tools"
  for tool_name in security codesign lipo PlistBuddy ditto xattr swift \
    pgrep lsof realpath open sleep kill log lldb uuidgen git stat shasum; do
    if [[ ! -x "$TEST_TOOL_DIRECTORY/$tool_name" ]]; then
      printf 'test workflow tool is missing or not executable: %s\n' \
        "$TEST_TOOL_DIRECTORY/$tool_name" >&2
      exit 1
    fi
  done
  SECURITY_TOOL="$TEST_TOOL_DIRECTORY/security"
  CODESIGN_TOOL="$TEST_TOOL_DIRECTORY/codesign"
  LIPO_TOOL="$TEST_TOOL_DIRECTORY/lipo"
  PLISTBUDDY_TOOL="$TEST_TOOL_DIRECTORY/PlistBuddy"
  DITTO_TOOL="$TEST_TOOL_DIRECTORY/ditto"
  XATTR_TOOL="$TEST_TOOL_DIRECTORY/xattr"
  SWIFT_TOOL="$TEST_TOOL_DIRECTORY/swift"
  PGREP_TOOL="$TEST_TOOL_DIRECTORY/pgrep"
  LSOF_TOOL="$TEST_TOOL_DIRECTORY/lsof"
  REALPATH_TOOL="$TEST_TOOL_DIRECTORY/realpath"
  OPEN_TOOL="$TEST_TOOL_DIRECTORY/open"
  SLEEP_TOOL="$TEST_TOOL_DIRECTORY/sleep"
  KILL_TOOL="$TEST_TOOL_DIRECTORY/kill"
  LOG_TOOL="$TEST_TOOL_DIRECTORY/log"
  LLDB_TOOL="$TEST_TOOL_DIRECTORY/lldb"
  UUIDGEN_TOOL="$TEST_TOOL_DIRECTORY/uuidgen"
  GIT_TOOL="$TEST_TOOL_DIRECTORY/git"
  STAT_TOOL="$TEST_TOOL_DIRECTORY/stat"
  SHASUM_TOOL="$TEST_TOOL_DIRECTORY/shasum"
  shift
elif [[ -n "${CODEX_CU_TEST_ROOT:-}" || -n "${CODEX_CU_WORKFLOW_TESTING:-}" ]]; then
  printf 'test-only workflow injection is disabled during normal execution\n' >&2
  exit 1
fi

APP_NAME="Codex Computer Use"
PROCESS_NAME="SkyComputerUseService"
BUNDLE_ID="com.openai.sky.CUAService"
MIN_SYSTEM_VERSION="14.0"
EXPECTED_SIGNING_IDENTITY="Codex Computer Use Local Development"
EXPECTED_SIGNING_IDENTITY_SHA1="7B958AD0A1A95B41F8F78C307FC0AA4651D08807"
EXPECTED_SIGNING_IDENTITY_SHA1_LOWER="7b958ad0a1a95b41f8f78c307fc0aa4651d08807"
SIGNING_IDENTITY="${CODEX_COMPUTER_USE_SIGNING_IDENTITY:-$EXPECTED_SIGNING_IDENTITY}"

if [[ "$SIGNING_IDENTITY" != "$EXPECTED_SIGNING_IDENTITY" ]]; then
  printf 'configured signing identity mismatch: expected %s, got %s\n' \
    "$EXPECTED_SIGNING_IDENTITY" "$SIGNING_IDENTITY" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$WORKFLOW_TEST_MODE" -eq 1 ]]; then
  DIST_DIR="$WORKFLOW_TEST_ROOT/dist"
  INSTALL_DIR="$WORKFLOW_TEST_ROOT/install"
  WORKFLOW_STAGING_PARENT="$WORKFLOW_TEST_ROOT/staging"
  PERMISSIONS_TEMP_PARENT="$WORKFLOW_TEST_ROOT/permissions"
else
  DIST_DIR="$ROOT_DIR/dist"
  INSTALL_DIR="${HOME:?HOME is required}/.codex/computer-use"
  WORKFLOW_STAGING_PARENT="/private/tmp"
  PERMISSIONS_TEMP_PARENT="/private/tmp"
fi
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
INSTALLED_EXECUTABLE="$INSTALLED_APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
if [[ "$WORKFLOW_TEST_MODE" -eq 1 ]]; then
  export CODEX_CU_FAKE_DIST_APP="$APP_BUNDLE"
  export CODEX_CU_FAKE_CANONICAL_APP="$INSTALLED_APP_BUNDLE"
fi
EXPLICIT_REQUIREMENT="identifier \"$BUNDLE_ID\" and certificate leaf = H\"$EXPECTED_SIGNING_IDENTITY_SHA1_LOWER\""
DESIGNATED_REQUIREMENT="designated => $EXPLICIT_REQUIREMENT"
WORKFLOW_ROOT=""
AUTHORITATIVE_APP=""
AUTHORITATIVE_BUILD_ID=""

cleanup_workflow_root() {
  if [[ -n "$WORKFLOW_ROOT" && -d "$WORKFLOW_ROOT" ]]; then
    /bin/rm -rf "$WORKFLOW_ROOT"
  fi
}
trap cleanup_workflow_root EXIT

usage() {
  printf 'usage: %s [run|--build [--install]|--install|--start|--stop|--status|--permissions|--identity|--doctor|--debug|--logs|--telemetry|--verify]\n' \
    "$0" >&2
}

REQUEST_BUILD=0
REQUEST_INSTALL=0
LEGACY_MODE=""
LIFECYCLE_MODE=""
if [[ "$#" -eq 0 ]]; then
  LEGACY_MODE="run"
else
  for argument in "$@"; do
    case "$argument" in
      --build|build)
        REQUEST_BUILD=1
        ;;
      --install|install)
        REQUEST_INSTALL=1
        REQUEST_BUILD=1
        ;;
      --start|start|--stop|stop|--status|status|--permissions|permissions|--identity|identity|--doctor|doctor)
        if [[ "$#" -ne 1 ]]; then
          usage
          exit 2
        fi
        LIFECYCLE_MODE="$argument"
        ;;
      run|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry)
        if [[ "$#" -ne 1 ]]; then
          usage
          exit 2
        fi
        LEGACY_MODE="$argument"
        ;;
      *)
        usage
        exit 2
        ;;
    esac
  done
fi

resolve_signing_identity() {
  local matches
  local match_count

  matches="$("$SECURITY_TOOL" find-identity -p codesigning -v \
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

  local actual_fingerprint
  actual_fingerprint="$(printf '%s' "$matches" | tr '[:lower:]' '[:upper:]')"
  if [[ "$actual_fingerprint" != "$EXPECTED_SIGNING_IDENTITY_SHA1" ]]; then
    printf 'signing identity fingerprint mismatch: expected %s, got %s\n' \
      "$EXPECTED_SIGNING_IDENTITY_SHA1" "$actual_fingerprint" >&2
    return 1
  fi

  printf '%s\n' "$EXPECTED_SIGNING_IDENTITY_SHA1"
}

verify_architecture() {
  local binary_path="$1"
  local stage="$2"
  local actual_architecture

  if [[ ! -f "$binary_path" ]]; then
    printf '%s: executable is missing: %s\n' "$stage" "$binary_path" >&2
    return 1
  fi
  if ! actual_architecture="$("$LIPO_TOOL" -archs "$binary_path" 2>/dev/null)"; then
    printf '%s: architecture inspection failed: %s\n' "$stage" "$binary_path" >&2
    return 1
  fi
  actual_architecture="$(
    printf '%s\n' "$actual_architecture" | awk '{$1=$1; print}'
  )"
  if [[ "$actual_architecture" != "x86_64" ]]; then
    printf '%s: architecture verification failed: expected x86_64, got %s\n' \
      "$stage" "${actual_architecture:-unknown}" >&2
    return 1
  fi
}

BUILD_IDENTITY_STATE=""
BUILD_IDENTITY_BUILD_ID=""
BUILD_IDENTITY_GIT_HEAD=""
BUILD_IDENTITY_GIT_DIRTY=""
BUILD_IDENTITY_ARCHITECTURE=""
BUILD_IDENTITY_BUNDLE_IDENTIFIER=""

reset_build_identity_result() {
  BUILD_IDENTITY_STATE="identity-invalid"
  BUILD_IDENTITY_BUILD_ID=""
  BUILD_IDENTITY_GIT_HEAD=""
  BUILD_IDENTITY_GIT_DIRTY=""
  BUILD_IDENTITY_ARCHITECTURE=""
  BUILD_IDENTITY_BUNDLE_IDENTIFIER=""
}

inspect_build_identity() {
  local bundle_path="$1"
  local stage="$2"
  local identity_plist="$bundle_path/Contents/Resources/BuildIdentity.plist"

  reset_build_identity_result
  if [[ ! -f "$identity_plist" ]]; then
    BUILD_IDENTITY_STATE="legacy"
    return 2
  fi
  if ! BUILD_IDENTITY_BUILD_ID="$(
    "$PLISTBUDDY_TOOL" -c 'Print :buildID' "$identity_plist" 2>/dev/null
  )"; then
    printf '%s: Build Identity is malformed: missing buildID\n' "$stage" >&2
    return 1
  fi
  if [[ ! "$BUILD_IDENTITY_BUILD_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    printf '%s: Build Identity has invalid buildID: %s\n' \
      "$stage" "${BUILD_IDENTITY_BUILD_ID:-empty}" >&2
    return 1
  fi
  if ! BUILD_IDENTITY_GIT_HEAD="$(
    "$PLISTBUDDY_TOOL" -c 'Print :gitHEAD' "$identity_plist" 2>/dev/null
  )"; then
    printf '%s: Build Identity is malformed: missing gitHEAD\n' "$stage" >&2
    return 1
  fi
  if [[ ! "$BUILD_IDENTITY_GIT_HEAD" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf '%s: Build Identity has invalid gitHEAD: %s\n' \
      "$stage" "${BUILD_IDENTITY_GIT_HEAD:-empty}" >&2
    return 1
  fi
  if ! BUILD_IDENTITY_GIT_DIRTY="$(
    "$PLISTBUDDY_TOOL" -c 'Print :gitDirty' "$identity_plist" 2>/dev/null
  )"; then
    printf '%s: Build Identity is malformed: missing gitDirty\n' "$stage" >&2
    return 1
  fi
  if [[ "$BUILD_IDENTITY_GIT_DIRTY" != "true" \
    && "$BUILD_IDENTITY_GIT_DIRTY" != "false" ]]; then
    printf '%s: Build Identity has invalid gitDirty: %s\n' \
      "$stage" "${BUILD_IDENTITY_GIT_DIRTY:-empty}" >&2
    return 1
  fi
  if ! BUILD_IDENTITY_ARCHITECTURE="$(
    "$PLISTBUDDY_TOOL" -c 'Print :architecture' "$identity_plist" 2>/dev/null
  )"; then
    printf '%s: Build Identity is malformed: missing architecture\n' "$stage" >&2
    return 1
  fi
  if [[ "$BUILD_IDENTITY_ARCHITECTURE" != "x86_64" ]]; then
    printf '%s: Build Identity architecture mismatch: expected x86_64, got %s\n' \
      "$stage" "${BUILD_IDENTITY_ARCHITECTURE:-empty}" >&2
    return 1
  fi
  if ! BUILD_IDENTITY_BUNDLE_IDENTIFIER="$(
    "$PLISTBUDDY_TOOL" -c 'Print :bundleIdentifier' "$identity_plist" 2>/dev/null
  )"; then
    printf '%s: Build Identity is malformed: missing bundleIdentifier\n' "$stage" >&2
    return 1
  fi
  if [[ "$BUILD_IDENTITY_BUNDLE_IDENTIFIER" != "$BUNDLE_ID" ]]; then
    printf '%s: Build Identity Bundle ID mismatch: expected %s, got %s\n' \
      "$stage" "$BUNDLE_ID" "${BUILD_IDENTITY_BUNDLE_IDENTIFIER:-empty}" >&2
    return 1
  fi
  BUILD_IDENTITY_STATE="identity-valid"
}

verify_build_identity() {
  local bundle_path="$1"
  local stage="$2"
  local expected_build_id="${3:-}"
  local inspect_status=0

  inspect_build_identity "$bundle_path" "$stage" || inspect_status=$?
  if [[ "$inspect_status" -eq 2 ]]; then
    printf '%s: Build Identity is missing\n' "$stage" >&2
    return 1
  fi
  if [[ "$inspect_status" -ne 0 ]]; then
    return 1
  fi
  if [[ -n "$expected_build_id" \
    && "$BUILD_IDENTITY_BUILD_ID" != "$expected_build_id" ]]; then
    printf '%s: Build ID mismatch: expected %s, got %s\n' \
      "$stage" "$expected_build_id" "$BUILD_IDENTITY_BUILD_ID" >&2
    return 1
  fi
}

verify_identity_signed_bundle() {
  local bundle_path="$1"
  local stage="$2"
  local expected_build_id="${3:-}"

  if ! verify_signed_bundle "$bundle_path" "$stage"; then
    return 1
  fi
  if ! verify_build_identity "$bundle_path" "$stage" "$expected_build_id"; then
    return 1
  fi
}

create_build_identity() {
  local bundle_path="$1"
  local identity_plist="$bundle_path/Contents/Resources/BuildIdentity.plist"
  local git_head
  local git_status
  local git_dirty="false"

  if ! AUTHORITATIVE_BUILD_ID="$("$UUIDGEN_TOOL")"; then
    printf 'authoritative bundle: could not generate buildID\n' >&2
    return 1
  fi
  if [[ ! "$AUTHORITATIVE_BUILD_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    printf 'authoritative bundle: invalid buildID: %s\n' \
      "${AUTHORITATIVE_BUILD_ID:-empty}" >&2
    return 1
  fi
  if ! git_head="$("$GIT_TOOL" -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)" \
    || [[ ! "$git_head" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf 'authoritative bundle: could not resolve a valid gitHEAD\n' >&2
    return 1
  fi
  if ! git_status="$(
    "$GIT_TOOL" -C "$ROOT_DIR" status --porcelain --untracked-files=normal
  )"; then
    printf 'authoritative bundle: could not inspect Git worktree status\n' >&2
    return 1
  fi
  if [[ -n "$git_status" ]]; then
    git_dirty="true"
  fi

  /bin/mkdir -p "$(dirname "$identity_plist")"
  "$PLISTBUDDY_TOOL" -c 'Clear dict' "$identity_plist" 2>/dev/null || true
  "$PLISTBUDDY_TOOL" -c "Add :buildID string '$AUTHORITATIVE_BUILD_ID'" "$identity_plist"
  "$PLISTBUDDY_TOOL" -c "Add :gitHEAD string '$git_head'" "$identity_plist"
  "$PLISTBUDDY_TOOL" -c "Add :gitDirty bool '$git_dirty'" "$identity_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :architecture string x86_64' "$identity_plist"
  "$PLISTBUDDY_TOOL" -c "Add :bundleIdentifier string '$BUNDLE_ID'" "$identity_plist"
  verify_build_identity "$bundle_path" "authoritative bundle"
}

verify_signed_bundle() {
  local bundle_path="$1"
  local stage="$2"
  local bundle_binary="$bundle_path/Contents/MacOS/$PROCESS_NAME"
  local actual_bundle_identifier
  local signing_details
  local actual_designated_requirement

  if ! verify_architecture "$bundle_binary" "$stage"; then
    return 1
  fi
  if ! actual_bundle_identifier="$(
    "$PLISTBUDDY_TOOL" -c 'Print :CFBundleIdentifier' \
      "$bundle_path/Contents/Info.plist" 2>/dev/null
  )"; then
    printf '%s: could not read Bundle Identifier\n' "$stage" >&2
    return 1
  fi
  if [[ "$actual_bundle_identifier" != "$BUNDLE_ID" ]]; then
    printf '%s: unexpected Bundle Identifier: expected %s, got %s\n' \
      "$stage" "$BUNDLE_ID" "$actual_bundle_identifier" >&2
    return 1
  fi

  if ! "$CODESIGN_TOOL" --verify --strict --verbose=2 "$bundle_path"; then
    printf '%s: codesign strict verification failed\n' "$stage" >&2
    return 1
  fi
  if ! "$CODESIGN_TOOL" --verify --deep --strict --verbose=2 "$bundle_path"; then
    printf '%s: codesign deep strict verification failed\n' "$stage" >&2
    return 1
  fi
  if ! "$CODESIGN_TOOL" --verify -R="$EXPLICIT_REQUIREMENT" --verbose=2 "$bundle_path"; then
    printf '%s: explicit designated requirement verification failed\n' "$stage" >&2
    return 1
  fi

  signing_details="$("$CODESIGN_TOOL" -dvvv "$bundle_path" 2>&1)"
  if ! grep -Fqx "Identifier=$BUNDLE_ID" <<<"$signing_details"; then
    printf '%s: signed Identifier does not match %s\n' \
      "$stage" "$BUNDLE_ID" >&2
    return 1
  fi
  if ! grep -Fqx "Authority=$EXPECTED_SIGNING_IDENTITY" <<<"$signing_details"; then
    printf '%s: signing Authority does not match %s\n' \
      "$stage" "$EXPECTED_SIGNING_IDENTITY" >&2
    return 1
  fi

  actual_designated_requirement="$(
    "$CODESIGN_TOOL" -d -r- "$bundle_path" 2>&1 \
      | awk '/^designated => / { print; exit }'
  )"
  if [[ "$actual_designated_requirement" == *cdhash* ]]; then
    printf '%s: designated requirement must not contain an executable CDHash\n' \
      "$stage" >&2
    return 1
  fi
  if [[ "$actual_designated_requirement" != "$DESIGNATED_REQUIREMENT" ]]; then
    printf '%s: unexpected designated requirement:\n  expected: %s\n  actual:   %s\n' \
      "$stage" "$DESIGNATED_REQUIREMENT" "$actual_designated_requirement" >&2
    return 1
  fi
}

CANONICAL_PIDS=()
FOREIGN_PROCESS_DETAILS=()
UNRESOLVED_PROCESS_DETAILS=()
ALL_CANDIDATE_PIDS=()
CANONICAL_EXECUTABLE_REAL=""

join_paths() {
  local joined=""
  local path
  for path in "$@"; do
    if [[ -n "$joined" ]]; then
      joined="$joined, $path"
    else
      joined="$path"
    fi
  done
  printf '%s\n' "$joined"
}

discover_helper_processes() {
  local candidate_output=""
  local pgrep_status=0
  local pid

  CANONICAL_PIDS=()
  FOREIGN_PROCESS_DETAILS=()
  UNRESOLVED_PROCESS_DETAILS=()
  ALL_CANDIDATE_PIDS=()
  CANONICAL_EXECUTABLE_REAL=""
  if [[ -e "$INSTALLED_EXECUTABLE" ]]; then
    CANONICAL_EXECUTABLE_REAL="$("$REALPATH_TOOL" "$INSTALLED_EXECUTABLE" 2>/dev/null || true)"
    if [[ "$CANONICAL_EXECUTABLE_REAL" != /* \
      || "$CANONICAL_EXECUTABLE_REAL" == *$'\n'* ]]; then
      CANONICAL_EXECUTABLE_REAL=""
    fi
  fi

  candidate_output="$("$PGREP_TOOL" -x "$PROCESS_NAME" 2>/dev/null)" \
    || pgrep_status=$?
  if [[ "$pgrep_status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$pgrep_status" -ne 0 ]]; then
    printf 'process discovery failed: pgrep could not enumerate candidates\n' >&2
    return 1
  fi

  while IFS= read -r pid; do
    local lsof_output=""
    local lsof_status=0
    local line
    local process_line_count=0
    local descriptor_count=0
    local parse_failed=0
    local normalization_failed=0
    local path
    local normalized_path
    local canonical_match=0
    local mapping_paths=()
    local normalized_paths=()

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
      UNRESOLVED_PROCESS_DETAILS+=("PID ${pid:-unknown}: executable mapping unresolved")
      continue
    fi
    ALL_CANDIDATE_PIDS+=("$pid")
    lsof_output="$("$LSOF_TOOL" -n -P -a -p "$pid" -d txt -Fn 2>/dev/null)" \
      || lsof_status=$?
    if [[ "$lsof_status" -ne 0 || -z "$lsof_output" ]]; then
      UNRESOLVED_PROCESS_DETAILS+=("PID $pid: executable mapping unresolved")
      continue
    fi

    while IFS= read -r line; do
      case "$line" in
        "p$pid")
          process_line_count=$((process_line_count + 1))
          ;;
        ftxt)
          descriptor_count=$((descriptor_count + 1))
          ;;
        n?*)
          mapping_paths+=("${line#n}")
          ;;
        *)
          parse_failed=1
          ;;
      esac
    done <<< "$lsof_output"

    if [[ "$parse_failed" -ne 0 \
      || "$process_line_count" -ne 1 \
      || "$descriptor_count" -lt 1 \
      || "${#mapping_paths[@]}" -ne "$descriptor_count" ]]; then
      UNRESOLVED_PROCESS_DETAILS+=("PID $pid: executable mapping unresolved")
      continue
    fi

    for path in "${mapping_paths[@]}"; do
      if ! normalized_path="$("$REALPATH_TOOL" "$path" 2>/dev/null)" \
        || [[ "$normalized_path" != /* || "$normalized_path" == *$'\n'* ]]; then
        normalization_failed=1
        continue
      fi
      normalized_paths+=("$normalized_path")
      if [[ -n "$CANONICAL_EXECUTABLE_REAL" \
        && "$normalized_path" == "$CANONICAL_EXECUTABLE_REAL" ]]; then
        canonical_match=1
      fi
    done
    if [[ "$canonical_match" -eq 1 ]]; then
      CANONICAL_PIDS+=("$pid")
    elif [[ "$normalization_failed" -ne 0 ]]; then
      UNRESOLVED_PROCESS_DETAILS+=("PID $pid: executable mapping unresolved")
    else
      FOREIGN_PROCESS_DETAILS+=("PID $pid: $(join_paths "${normalized_paths[@]}")")
    fi
  done <<< "$candidate_output"
}

print_process_list() {
  local heading="$1"
  shift
  local detail
  if [[ "$#" -eq 0 ]]; then
    printf '%s: none\n' "$heading"
    return
  fi
  printf '%s:\n' "$heading"
  for detail in "$@"; do
    printf -- '- %s\n' "$detail"
  done
}

print_canonical_diagnostics() {
  local signing_details
  local architecture
  local bundle_identifier
  local authority
  local cdhash
  local designated_requirement

  architecture="$("$LIPO_TOOL" -archs "$INSTALLED_EXECUTABLE" 2>/dev/null || true)"
  bundle_identifier="$("$PLISTBUDDY_TOOL" -c 'Print :CFBundleIdentifier' \
    "$INSTALLED_APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  signing_details="$("$CODESIGN_TOOL" -dvvv "$INSTALLED_APP_BUNDLE" 2>&1 || true)"
  authority="$(printf '%s\n' "$signing_details" | awk -F= '/^Authority=/ { print substr($0, index($0, "=") + 1); exit }')"
  cdhash="$(printf '%s\n' "$signing_details" | awk -F= '/^CDHash=/ { print substr($0, index($0, "=") + 1); exit }')"
  designated_requirement="$("$CODESIGN_TOOL" -d -r- "$INSTALLED_APP_BUNDLE" 2>&1 \
    | awk '/^designated => / { print; exit }' || true)"

  printf 'Executable: %s\n' "${CANONICAL_EXECUTABLE_REAL:-unavailable}"
  printf 'Architecture: %s\n' "${architecture:-unavailable}"
  printf 'Bundle ID: %s\n' "${bundle_identifier:-unavailable}"
  printf 'Authority: %s\n' "${authority:-unavailable}"
  printf 'CDHash: %s\n' "${cdhash:-unavailable}"
  printf 'Designated Requirement: %s\n' "${designated_requirement:-unavailable}"
}

status_helper() {
  local pid

  if [[ -d "$INSTALLED_APP_BUNDLE" && -f "$INSTALLED_EXECUTABLE" ]]; then
    printf 'Installed Helper: installed\n'
  else
    printf 'Installed Helper: missing\n'
  fi
  printf 'Canonical bundle path: %s\n' "$INSTALLED_APP_BUNDLE"
  printf 'Canonical executable path: %s\n' "$INSTALLED_EXECUTABLE"

  discover_helper_processes
  if [[ "${#CANONICAL_PIDS[@]}" -eq 0 ]]; then
    printf 'Running Helper: stopped\n'
  elif [[ "${#CANONICAL_PIDS[@]}" -eq 1 ]]; then
    printf 'Running Helper: running\n'
    printf 'PID: %s\n' "${CANONICAL_PIDS[0]}"
    print_canonical_diagnostics
  else
    printf 'Running Helper: duplicate\n'
    printf 'Canonical PIDs:'
    for pid in "${CANONICAL_PIDS[@]}"; do
      printf ' %s' "$pid"
    done
    printf '\n'
    print_canonical_diagnostics
  fi
  if [[ "${#FOREIGN_PROCESS_DETAILS[@]}" -eq 0 ]]; then
    printf 'Foreign same-name processes: none\n'
  else
    print_process_list "Foreign same-name processes" "${FOREIGN_PROCESS_DETAILS[@]}"
  fi
  if [[ "${#UNRESOLVED_PROCESS_DETAILS[@]}" -eq 0 ]]; then
    printf 'Unresolved same-name processes: none\n'
  else
    print_process_list "Unresolved same-name processes" "${UNRESOLVED_PROCESS_DETAILS[@]}"
  fi
}

INSTALLED_IDENTITY_BUILD_ID=""
DIST_IDENTITY_BUILD_ID=""

report_identity_bundle() {
  local bundle_path="$1"
  local report_name="$2"
  local executable="$bundle_path/Contents/MacOS/$PROCESS_NAME"
  local bundle_identifier=""
  local architecture=""
  local executable_real=""
  local executable_sha=""
  local sha_output=""
  local signing_details=""
  local authority=""
  local cdhash=""
  local designated_requirement=""
  local verification_output=""
  local verification_status=0
  local identity_status=0
  local report_status=0

  printf '%s bundle path: %s\n' "$report_name" "$bundle_path"
  executable_real="$("$REALPATH_TOOL" "$executable" 2>/dev/null || true)"
  architecture="$("$LIPO_TOOL" -archs "$executable" 2>/dev/null || true)"
  bundle_identifier="$(
    "$PLISTBUDDY_TOOL" -c 'Print :CFBundleIdentifier' \
      "$bundle_path/Contents/Info.plist" 2>/dev/null || true
  )"
  if sha_output="$("$SHASUM_TOOL" -a 256 "$executable" 2>/dev/null)"; then
    executable_sha="${sha_output%%[[:space:]]*}"
  fi
  if [[ ! "$executable_sha" =~ ^[0-9A-Fa-f]{64}$ ]]; then
    executable_sha="unavailable"
    report_status=1
    printf '%s: executable SHA-256 inspection failed\n' "$report_name" >&2
  fi
  signing_details="$("$CODESIGN_TOOL" -dvvv "$bundle_path" 2>&1 || true)"
  authority="$(
    printf '%s\n' "$signing_details" \
      | awk -F= '/^Authority=/ { print substr($0, index($0, "=") + 1); exit }'
  )"
  cdhash="$(
    printf '%s\n' "$signing_details" \
      | awk -F= '/^CDHash=/ { print substr($0, index($0, "=") + 1); exit }'
  )"
  designated_requirement="$(
    "$CODESIGN_TOOL" -d -r- "$bundle_path" 2>&1 \
      | awk '/^designated => / { print; exit }' || true
  )"

  verification_output="$(verify_signed_bundle "$bundle_path" "$report_name" 2>&1)" \
    || verification_status=$?
  if [[ "$verification_status" -ne 0 ]]; then
    report_status=1
    if [[ -n "$verification_output" ]]; then
      printf '%s\n' "$verification_output" >&2
    fi
  fi

  inspect_build_identity "$bundle_path" "$report_name" || identity_status=$?
  case "$identity_status" in
    0)
      printf 'Build Identity: identity-valid\n'
      printf 'Build ID: %s\n' "$BUILD_IDENTITY_BUILD_ID"
      printf 'Git HEAD: %s\n' "$BUILD_IDENTITY_GIT_HEAD"
      printf 'Git Dirty: %s\n' "$BUILD_IDENTITY_GIT_DIRTY"
      ;;
    2)
      printf 'Build Identity: legacy / missing\n'
      ;;
    *)
      printf 'Build Identity: identity-invalid\n'
      report_status=1
      ;;
  esac
  if [[ "$verification_status" -ne 0 || "$identity_status" -eq 1 ]]; then
    printf 'Bundle identity classification: identity-invalid\n'
  elif [[ "$identity_status" -eq 2 ]]; then
    printf 'Bundle identity classification: legacy-valid\n'
  else
    printf 'Bundle identity classification: identity-valid\n'
  fi
  printf 'Executable: %s\n' "${executable_real:-unavailable}"
  printf 'Architecture: %s\n' "${architecture:-unavailable}"
  printf 'Bundle ID: %s\n' "${bundle_identifier:-unavailable}"
  printf 'Executable SHA-256: %s\n' "$executable_sha"
  printf 'CDHash: %s\n' "${cdhash:-unavailable}"
  printf 'Authority: %s\n' "${authority:-unavailable}"
  printf 'Designated Requirement: %s\n' "${designated_requirement:-unavailable}"
  if [[ "$verification_status" -eq 0 ]]; then
    printf 'Strict codesign: valid\n'
  else
    printf 'Strict codesign: invalid\n'
  fi

  if [[ "$report_name" == "installed canonical" ]]; then
    if [[ "$identity_status" -eq 0 ]]; then
      INSTALLED_IDENTITY_BUILD_ID="$BUILD_IDENTITY_BUILD_ID"
    else
      INSTALLED_IDENTITY_BUILD_ID=""
    fi
  elif [[ "$report_name" == "dist non-authoritative" ]]; then
    if [[ "$identity_status" -eq 0 ]]; then
      DIST_IDENTITY_BUILD_ID="$BUILD_IDENTITY_BUILD_ID"
    else
      DIST_IDENTITY_BUILD_ID=""
    fi
  fi
  return "$report_status"
}

RUNTIME_CURRENT_DETAILS=()
RUNTIME_STALE_DETAILS=()
RUNTIME_FOREIGN_DETAILS=()
RUNTIME_UNRESOLVED_DETAILS=()
RUNTIME_CANONICAL_PIDS=()
INSTALLED_EXECUTABLE_DEVICE=""
INSTALLED_EXECUTABLE_INODE=""
RUNTIME_DISCOVERY_STATUS=0

normalize_device_number() {
  local raw_value="$1"
  if [[ "$raw_value" =~ ^0[xX][0-9A-Fa-f]+$ \
    || "$raw_value" =~ ^[0-9]+$ ]]; then
    printf '%u\n' "$raw_value" 2>/dev/null
    return $?
  fi
  return 1
}

discover_runtime_identity() {
  local stat_output=""
  local candidate_output=""
  local pgrep_status=0
  local pid

  RUNTIME_CURRENT_DETAILS=()
  RUNTIME_STALE_DETAILS=()
  RUNTIME_FOREIGN_DETAILS=()
  RUNTIME_UNRESOLVED_DETAILS=()
  RUNTIME_CANONICAL_PIDS=()
  INSTALLED_EXECUTABLE_DEVICE=""
  INSTALLED_EXECUTABLE_INODE=""

  if ! CANONICAL_EXECUTABLE_REAL="$(
    "$REALPATH_TOOL" "$INSTALLED_EXECUTABLE" 2>/dev/null
  )" || [[ "$CANONICAL_EXECUTABLE_REAL" != /* \
    || "$CANONICAL_EXECUTABLE_REAL" == *$'\n'* ]]; then
    printf 'runtime identity: canonical executable realpath is unresolved\n' >&2
    return 1
  fi
  if ! stat_output="$("$STAT_TOOL" -f '%d %i' "$INSTALLED_EXECUTABLE" 2>/dev/null)"; then
    printf 'runtime identity: installed executable device/inode is unresolved\n' >&2
    return 1
  fi
  read -r INSTALLED_EXECUTABLE_DEVICE INSTALLED_EXECUTABLE_INODE <<< "$stat_output"
  if [[ ! "$INSTALLED_EXECUTABLE_DEVICE" =~ ^[0-9]+$ \
    || ! "$INSTALLED_EXECUTABLE_INODE" =~ ^[0-9]+$ ]]; then
    printf 'runtime identity: installed executable device/inode is malformed\n' >&2
    return 1
  fi

  candidate_output="$("$PGREP_TOOL" -x "$PROCESS_NAME" 2>/dev/null)" \
    || pgrep_status=$?
  if [[ "$pgrep_status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$pgrep_status" -ne 0 ]]; then
    printf 'runtime identity: pgrep could not enumerate candidates\n' >&2
    return 1
  fi

  while IFS= read -r pid; do
    local lsof_output=""
    local lsof_status=0
    local line
    local process_line_count=0
    local parse_failed=0
    local mapping_index=-1
    local index
    local normalized_path
    local normalized_device
    local canonical_matches=0
    local current_matches=0
    local stale_matches=0
    local mapping_failed=0
    local first_canonical_path=""
    local first_canonical_device=""
    local first_canonical_inode=""
    local mapping_paths=()
    local mapping_devices=()
    local mapping_inodes=()
    local normalized_paths=()

    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
      RUNTIME_UNRESOLVED_DETAILS+=("PID ${pid:-unknown}: executable vnode unresolved")
      continue
    fi
    lsof_output="$(
      "$LSOF_TOOL" -n -P -a -p "$pid" -d txt -F pfnDi 2>/dev/null
    )" || lsof_status=$?
    if [[ "$lsof_status" -ne 0 || -z "$lsof_output" ]]; then
      RUNTIME_UNRESOLVED_DETAILS+=("PID $pid: executable vnode unresolved")
      continue
    fi

    while IFS= read -r line; do
      case "$line" in
        "p$pid")
          process_line_count=$((process_line_count + 1))
          ;;
        ftxt)
          mapping_index=$((mapping_index + 1))
          mapping_paths[$mapping_index]=""
          mapping_devices[$mapping_index]=""
          mapping_inodes[$mapping_index]=""
          ;;
        D?*)
          if [[ "$mapping_index" -lt 0 \
            || -n "${mapping_devices[$mapping_index]:-}" ]]; then
            parse_failed=1
          else
            mapping_devices[$mapping_index]="${line#D}"
          fi
          ;;
        i?*)
          if [[ "$mapping_index" -lt 0 \
            || -n "${mapping_inodes[$mapping_index]:-}" ]]; then
            parse_failed=1
          else
            mapping_inodes[$mapping_index]="${line#i}"
          fi
          ;;
        n?*)
          if [[ "$mapping_index" -lt 0 \
            || -n "${mapping_paths[$mapping_index]:-}" ]]; then
            parse_failed=1
          else
            mapping_paths[$mapping_index]="${line#n}"
          fi
          ;;
        *)
          parse_failed=1
          ;;
      esac
    done <<< "$lsof_output"

    if [[ "$parse_failed" -ne 0 || "$process_line_count" -ne 1 \
      || "$mapping_index" -lt 0 ]]; then
      RUNTIME_UNRESOLVED_DETAILS+=("PID $pid: executable vnode unresolved")
      continue
    fi

    for ((index = 0; index <= mapping_index; index++)); do
      if [[ -z "${mapping_paths[$index]:-}" \
        || -z "${mapping_devices[$index]:-}" \
        || -z "${mapping_inodes[$index]:-}" ]]; then
        mapping_failed=1
        continue
      fi
      if ! normalized_path="$(
        "$REALPATH_TOOL" "${mapping_paths[$index]}" 2>/dev/null
      )" || [[ "$normalized_path" != /* \
        || "$normalized_path" == *$'\n'* ]]; then
        mapping_failed=1
        continue
      fi
      if ! normalized_device="$(
        normalize_device_number "${mapping_devices[$index]}"
      )" || [[ ! "${mapping_inodes[$index]}" =~ ^[0-9]+$ ]]; then
        mapping_failed=1
        continue
      fi
      normalized_paths+=("$normalized_path")
      if [[ "$normalized_path" == "$CANONICAL_EXECUTABLE_REAL" ]]; then
        canonical_matches=$((canonical_matches + 1))
        if [[ -z "$first_canonical_path" ]]; then
          first_canonical_path="$normalized_path"
          first_canonical_device="$normalized_device"
          first_canonical_inode="${mapping_inodes[$index]}"
        fi
        if [[ "$normalized_device" == "$INSTALLED_EXECUTABLE_DEVICE" \
          && "${mapping_inodes[$index]}" == "$INSTALLED_EXECUTABLE_INODE" ]]; then
          current_matches=$((current_matches + 1))
        else
          stale_matches=$((stale_matches + 1))
        fi
      fi
    done

    if [[ "$canonical_matches" -gt 0 ]]; then
      if [[ "$current_matches" -gt 0 && "$stale_matches" -gt 0 ]]; then
        RUNTIME_UNRESOLVED_DETAILS+=("PID $pid: executable vnode unresolved")
      elif [[ "$current_matches" -eq "$canonical_matches" ]]; then
        RUNTIME_CANONICAL_PIDS+=("$pid")
        RUNTIME_CURRENT_DETAILS+=(
          "$pid|$first_canonical_path|$first_canonical_device|$first_canonical_inode"
        )
      elif [[ "$stale_matches" -eq "$canonical_matches" ]]; then
        RUNTIME_CANONICAL_PIDS+=("$pid")
        RUNTIME_STALE_DETAILS+=(
          "$pid|$first_canonical_path|$first_canonical_device|$first_canonical_inode"
        )
      else
        RUNTIME_UNRESOLVED_DETAILS+=("PID $pid: executable vnode unresolved")
      fi
    elif [[ "$mapping_failed" -ne 0 || "${#normalized_paths[@]}" -eq 0 ]]; then
      RUNTIME_UNRESOLVED_DETAILS+=("PID $pid: executable vnode unresolved")
    else
      RUNTIME_FOREIGN_DETAILS+=("PID $pid: $(join_paths "${normalized_paths[@]}")")
    fi
  done <<< "$candidate_output"
}

print_runtime_detail() {
  local detail="$1"
  local pid
  local path
  local device
  local inode
  IFS='|' read -r pid path device inode <<< "$detail"
  printf 'PID: %s\n' "$pid"
  printf 'Running executable: %s\n' "$path"
  printf 'Running device/inode: %s/%s\n' "$device" "$inode"
  printf 'Installed device/inode: %s/%s\n' \
    "$INSTALLED_EXECUTABLE_DEVICE" "$INSTALLED_EXECUTABLE_INODE"
}

print_runtime_identity() {
  local pid

  if [[ "${#RUNTIME_CANONICAL_PIDS[@]}" -gt 1 ]]; then
    printf 'Running Helper: duplicate\n'
    printf 'Canonical PIDs:'
    for pid in "${RUNTIME_CANONICAL_PIDS[@]}"; do
      printf ' %s' "$pid"
    done
    printf '\n'
    printf 'Running matches installed: indeterminate (duplicate)\n'
  elif [[ "${#RUNTIME_UNRESOLVED_DETAILS[@]}" -gt 0 ]]; then
    printf 'Running Helper: unresolved\n'
    printf 'Running matches installed: indeterminate\n'
  elif [[ "${#RUNTIME_CURRENT_DETAILS[@]}" -eq 1 ]]; then
    printf 'Running Helper: current\n'
    print_runtime_detail "${RUNTIME_CURRENT_DETAILS[0]}"
    printf 'Running matches installed: yes\n'
  elif [[ "${#RUNTIME_STALE_DETAILS[@]}" -eq 1 ]]; then
    printf 'Running Helper: stale\n'
    print_runtime_detail "${RUNTIME_STALE_DETAILS[0]}"
    printf 'Running matches installed: no\n'
    printf 'Warning: running canonical path but executable vnode differs from current installation\n'
  elif [[ "${#RUNTIME_FOREIGN_DETAILS[@]}" -gt 0 ]]; then
    printf 'Running Helper: foreign\n'
    printf 'Running matches installed: no canonical runtime\n'
  else
    printf 'Running Helper: stopped\n'
    printf 'Running matches installed: not applicable\n'
  fi
  if [[ "${#RUNTIME_FOREIGN_DETAILS[@]}" -eq 0 ]]; then
    printf 'Foreign same-name processes: none\n'
  else
    print_process_list "Foreign same-name processes" "${RUNTIME_FOREIGN_DETAILS[@]}"
  fi
  if [[ "${#RUNTIME_UNRESOLVED_DETAILS[@]}" -eq 0 ]]; then
    printf 'Unresolved same-name processes: none\n'
  else
    print_process_list \
      "Unresolved same-name processes" "${RUNTIME_UNRESOLVED_DETAILS[@]}"
  fi
}

identity_helper() {
  local overall_status=0
  local dist_status=0
  local xattr_output=""

  INSTALLED_IDENTITY_BUILD_ID=""
  DIST_IDENTITY_BUILD_ID=""
  RUNTIME_DISCOVERY_STATUS=0
  if [[ -d "$INSTALLED_APP_BUNDLE" && -f "$INSTALLED_EXECUTABLE" ]]; then
    printf 'Installed Helper: installed\n'
    report_identity_bundle \
      "$INSTALLED_APP_BUNDLE" "installed canonical" || overall_status=1
  else
    printf 'Installed Helper: missing\n'
    printf 'Canonical bundle path: %s\n' "$INSTALLED_APP_BUNDLE"
    overall_status=1
  fi

  printf '\n'
  if [[ -d "$APP_BUNDLE" && -f "$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME" ]]; then
    printf 'Dist copy: present (non-authoritative)\n'
    report_identity_bundle "$APP_BUNDLE" "dist non-authoritative" \
      || dist_status=$?
    xattr_output="$("$XATTR_TOOL" "$APP_BUNDLE" 2>/dev/null || true)"
    if [[ -n "$xattr_output" ]]; then
      printf 'FinderInfo/xattr: warning: %s\n' \
        "$(printf '%s\n' "$xattr_output" | awk '{$1=$1; printf "%s%s", separator, $0; separator=", "}')"
    else
      printf 'FinderInfo/xattr: none\n'
    fi
    if [[ "$dist_status" -ne 0 ]]; then
      printf 'Warning: dist validation failed; dist remains non-authoritative\n' >&2
    fi
  else
    printf 'Dist copy: missing (non-authoritative)\n'
  fi

  if [[ -n "$INSTALLED_IDENTITY_BUILD_ID" \
    && -n "$DIST_IDENTITY_BUILD_ID" ]]; then
    if [[ "$INSTALLED_IDENTITY_BUILD_ID" == "$DIST_IDENTITY_BUILD_ID" ]]; then
      printf 'Same workflow build: yes\n'
    else
      printf 'Same workflow build: no\n'
    fi
  else
    printf 'Same workflow build: unavailable\n'
  fi

  printf '\n'
  if [[ -f "$INSTALLED_EXECUTABLE" ]]; then
    if discover_runtime_identity; then
      print_runtime_identity
      if [[ "${#RUNTIME_UNRESOLVED_DETAILS[@]}" -gt 0 ]]; then
        overall_status=1
      fi
    else
      printf 'Running Helper: unresolved\n'
      printf 'Running matches installed: indeterminate\n'
      RUNTIME_DISCOVERY_STATUS=1
      overall_status=1
    fi
  else
    printf 'Running Helper: stopped\n'
    printf 'Running matches installed: not applicable\n'
  fi
  return "$overall_status"
}

format_pids() {
  local formatted=""
  local pid
  for pid in "$@"; do
    if [[ -n "$formatted" ]]; then
      formatted="$formatted $pid"
    else
      formatted="$pid"
    fi
  done
  printf '%s\n' "$formatted"
}

CAPTURED_PID_SET_STRING=""

capture_candidate_pid_set() {
  local candidate_output=""
  local normalized_output=""
  local pgrep_status=0
  local pid

  CAPTURED_PID_SET_STRING=""
  candidate_output="$("$PGREP_TOOL" -x "$PROCESS_NAME" 2>/dev/null)" \
    || pgrep_status=$?
  if [[ "$pgrep_status" -eq 1 ]]; then
    return 0
  fi
  if [[ "$pgrep_status" -ne 0 ]]; then
    printf 'permission PID snapshot failed: pgrep could not enumerate candidates\n' >&2
    return 1
  fi
  normalized_output="$(printf '%s\n' "$candidate_output" | /usr/bin/sort -n -u)"
  if [[ -z "$normalized_output" ]]; then
    return 0
  fi
  while IFS= read -r pid; do
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
      printf 'permission PID snapshot failed: invalid PID value: %s\n' \
        "${pid:-empty}" >&2
      return 1
    fi
    if [[ -n "$CAPTURED_PID_SET_STRING" ]]; then
      CAPTURED_PID_SET_STRING="$CAPTURED_PID_SET_STRING $pid"
    else
      CAPTURED_PID_SET_STRING="$pid"
    fi
  done <<< "$normalized_output"
}

pid_set_contains() {
  local wanted_pid="$1"
  local pid_set="$2"
  [[ " $pid_set " == *" $wanted_pid "* ]]
}

print_permission_evidence_file() {
  local heading="$1"
  local file_path="$2"
  printf '%s:\n' "$heading" >&2
  if [[ -s "$file_path" ]]; then
    /bin/cat "$file_path" >&2
  else
    printf '(empty)\n' >&2
  fi
}

report_permission_failure() {
  local message="$1"
  local evidence_root="$2"
  local stdout_file="$3"
  local stderr_file="$4"
  local launch_stderr_file="$5"
  local before_pids="$6"
  local current_pids="$7"
  local pid

  printf '%s\n' "$message" >&2
  printf 'Before PID set: %s\n' "${before_pids:-none}" >&2
  printf 'Current PID set: %s\n' "${current_pids:-none}" >&2
  for pid in $current_pids; do
    if ! pid_set_contains "$pid" "$before_pids"; then
      printf 'Added PID: %s\n' "$pid" >&2
    fi
  done
  for pid in $before_pids; do
    if ! pid_set_contains "$pid" "$current_pids"; then
      printf 'Removed PID: %s\n' "$pid" >&2
    fi
  done
  print_permission_evidence_file "Permission diagnostic stdout" "$stdout_file"
  print_permission_evidence_file "Permission diagnostic stderr" "$stderr_file"
  print_permission_evidence_file "LaunchServices stderr" "$launch_stderr_file"
  printf 'permission diagnostic evidence retained: %s\n' "$evidence_root" >&2
}

COMPLETION_STATE="missing"

inspect_permission_completion() {
  local stdout_file="$1"
  local marker='Permission Diagnostic: completed'
  local marker_count=0
  local last_line=""

  COMPLETION_STATE="missing"
  if [[ ! -f "$stdout_file" ]]; then
    return 0
  fi
  marker_count="$(/usr/bin/grep -Fxc "$marker" "$stdout_file" 2>/dev/null || true)"
  if [[ "$marker_count" -eq 0 ]]; then
    return 0
  fi
  last_line="$(/usr/bin/tail -n 1 "$stdout_file" 2>/dev/null || true)"
  if [[ "$marker_count" -eq 1 && "$last_line" == "$marker" ]]; then
    COMPLETION_STATE="complete"
  else
    COMPLETION_STATE="malformed"
  fi
}

PERMISSION_ACCESSIBILITY=""
PERMISSION_SCREEN_RECORDING=""

parse_permission_payload() {
  local stdout_file="$1"
  local expected_executable_real="$2"
  local reported_executable
  local reported_executable_real
  local line
  local lines=()

  PERMISSION_ACCESSIBILITY=""
  PERMISSION_SCREEN_RECORDING=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done < "$stdout_file"
  if [[ "${#lines[@]}" -ne 5 ]]; then
    printf 'permission diagnostic output is malformed: expected 5 protocol lines, got %s\n' \
      "${#lines[@]}" >&2
    return 1
  fi
  if [[ "${lines[0]}" != "Bundle ID: $BUNDLE_ID" ]]; then
    printf 'permission diagnostic identity mismatch: expected Bundle ID %s, got %s\n' \
      "$BUNDLE_ID" "${lines[0]#Bundle ID: }" >&2
    return 1
  fi
  if [[ "${lines[1]}" != "Executable: "* ]]; then
    printf 'permission diagnostic output is malformed: missing Executable field\n' >&2
    return 1
  fi
  reported_executable="${lines[1]#Executable: }"
  if ! reported_executable_real="$("$REALPATH_TOOL" "$reported_executable" 2>/dev/null)" \
    || [[ "$reported_executable_real" != /* \
      || "$reported_executable_real" == *$'\n'* ]]; then
    printf 'permission diagnostic identity mismatch: executable realpath is unresolved: %s\n' \
      "$reported_executable" >&2
    return 1
  fi
  if [[ "$reported_executable_real" != "$expected_executable_real" ]]; then
    printf 'permission diagnostic identity mismatch: expected executable %s, got %s\n' \
      "$expected_executable_real" "$reported_executable_real" >&2
    return 1
  fi
  case "${lines[2]}" in
    'Accessibility: granted')
      PERMISSION_ACCESSIBILITY="granted"
      ;;
    'Accessibility: denied')
      PERMISSION_ACCESSIBILITY="denied"
      ;;
    *)
      printf 'permission diagnostic output is malformed: invalid Accessibility value\n' >&2
      return 1
      ;;
  esac
  case "${lines[3]}" in
    'Screen Recording: granted')
      PERMISSION_SCREEN_RECORDING="granted"
      ;;
    'Screen Recording: denied')
      PERMISSION_SCREEN_RECORDING="denied"
      ;;
    *)
      printf 'permission diagnostic output is malformed: invalid Screen Recording value\n' >&2
      return 1
      ;;
  esac
  if [[ "${lines[4]}" != 'Permission Diagnostic: completed' ]]; then
    printf 'permission diagnostic output is malformed: completion marker is not final\n' >&2
    return 1
  fi
}

permissions_helper() {
  local permission_root=""
  local stdout_file
  local stderr_file
  local launch_stderr_file
  local canonical_executable_real
  local before_pids=""
  local current_pids=""
  local attempt

  if [[ ! -d "$INSTALLED_APP_BUNDLE" || ! -f "$INSTALLED_EXECUTABLE" ]]; then
    printf 'canonical Helper is missing: %s\n' "$INSTALLED_APP_BUNDLE" >&2
    return 1
  fi
  verify_signed_bundle "$INSTALLED_APP_BUNDLE" "canonical permissions bundle"
  if ! canonical_executable_real="$("$REALPATH_TOOL" "$INSTALLED_EXECUTABLE" 2>/dev/null)" \
    || [[ "$canonical_executable_real" != /* \
      || "$canonical_executable_real" == *$'\n'* ]]; then
    printf 'canonical permissions executable realpath is unresolved: %s\n' \
      "$INSTALLED_EXECUTABLE" >&2
    return 1
  fi
  if ! capture_candidate_pid_set; then
    return 1
  fi
  before_pids="$CAPTURED_PID_SET_STRING"

  /bin/mkdir -p "$PERMISSIONS_TEMP_PARENT"
  if ! permission_root="$(mktemp -d "$PERMISSIONS_TEMP_PARENT/codex-cu-permissions.XXXXXX")"; then
    printf 'could not create unique permission diagnostic directory\n' >&2
    return 1
  fi
  stdout_file="$permission_root/stdout"
  stderr_file="$permission_root/stderr"
  launch_stderr_file="$permission_root/launchservices-stderr"
  : > "$stdout_file"
  : > "$stderr_file"
  : > "$launch_stderr_file"

  if ! "$OPEN_TOOL" -n -g \
    --stdout "$stdout_file" \
    --stderr "$stderr_file" \
    "$INSTALLED_APP_BUNDLE" \
    --args --permission-status \
    2> "$launch_stderr_file"; then
    capture_candidate_pid_set || true
    current_pids="$CAPTURED_PID_SET_STRING"
    report_permission_failure \
      "LaunchServices failed to start canonical permission diagnostic" \
      "$permission_root" "$stdout_file" "$stderr_file" \
      "$launch_stderr_file" "$before_pids" "$current_pids"
    return 1
  fi

  for attempt in {1..50}; do
    "$SLEEP_TOOL" 0.1
    if ! capture_candidate_pid_set; then
      current_pids=""
      report_permission_failure \
        "permission diagnostic infrastructure failed while reading the current PID set" \
        "$permission_root" "$stdout_file" "$stderr_file" \
        "$launch_stderr_file" "$before_pids" "$current_pids"
      return 1
    fi
    current_pids="$CAPTURED_PID_SET_STRING"
    inspect_permission_completion "$stdout_file"
    if [[ "$COMPLETION_STATE" == "malformed" && "$current_pids" == "$before_pids" ]]; then
      report_permission_failure \
        "permission diagnostic output is malformed: completion marker must be unique and final" \
        "$permission_root" "$stdout_file" "$stderr_file" \
        "$launch_stderr_file" "$before_pids" "$current_pids"
      return 1
    fi
    if [[ "$COMPLETION_STATE" == "complete" && "$current_pids" == "$before_pids" ]]; then
      if ! parse_permission_payload "$stdout_file" "$canonical_executable_real"; then
        report_permission_failure \
          "permission diagnostic payload validation failed" \
          "$permission_root" "$stdout_file" "$stderr_file" \
          "$launch_stderr_file" "$before_pids" "$current_pids"
        return 1
      fi
      if [[ -s "$stderr_file" ]]; then
        /bin/cat "$stderr_file" >&2
      fi
      if [[ -s "$launch_stderr_file" ]]; then
        /bin/cat "$launch_stderr_file" >&2
      fi
      /bin/cat "$stdout_file"
      /bin/rm -rf "$permission_root"
      return 0
    fi
  done

  if [[ "$COMPLETION_STATE" == "missing" && "$current_pids" != "$before_pids" ]]; then
    report_permission_failure \
      "permission diagnostic timed out: no completion marker; Helper did not exit and PID set did not recover" \
      "$permission_root" "$stdout_file" "$stderr_file" \
      "$launch_stderr_file" "$before_pids" "$current_pids"
  elif [[ "$COMPLETION_STATE" == "missing" ]]; then
    report_permission_failure \
      "permission diagnostic timed out: no completion marker" \
      "$permission_root" "$stdout_file" "$stderr_file" \
      "$launch_stderr_file" "$before_pids" "$current_pids"
  elif [[ "$current_pids" != "$before_pids" ]]; then
    report_permission_failure \
      "permission diagnostic timed out: PID set did not recover" \
      "$permission_root" "$stdout_file" "$stderr_file" \
      "$launch_stderr_file" "$before_pids" "$current_pids"
  else
    report_permission_failure \
      "permission diagnostic failed in an unresolved synchronization state" \
      "$permission_root" "$stdout_file" "$stderr_file" \
      "$launch_stderr_file" "$before_pids" "$current_pids"
  fi
  return 1
}

doctor_helper() {
  local attention=0
  local identity_status=0
  local permission_status=0
  local runtime_state="stopped"

  printf 'Expected architecture: x86_64\n'
  printf 'Expected Bundle ID: %s\n' "$BUNDLE_ID"
  printf 'Expected signing identity: %s\n' "$EXPECTED_SIGNING_IDENTITY"
  printf 'Expected designated requirement: %s\n' "$DESIGNATED_REQUIREMENT"
  printf '\nIdentity and runtime:\n'

  identity_helper || identity_status=$?
  if [[ "$identity_status" -ne 0 ]]; then
    attention=1
  fi
  if [[ -d "$INSTALLED_APP_BUNDLE" && -f "$INSTALLED_EXECUTABLE" \
    && -z "$INSTALLED_IDENTITY_BUILD_ID" ]]; then
    attention=1
  fi

  if [[ "$RUNTIME_DISCOVERY_STATUS" -ne 0 ]]; then
    runtime_state="unresolved"
  elif [[ "${#RUNTIME_CANONICAL_PIDS[@]}" -gt 1 ]]; then
    runtime_state="duplicate"
  elif [[ "${#RUNTIME_UNRESOLVED_DETAILS[@]}" -gt 0 ]]; then
    runtime_state="unresolved"
  elif [[ "${#RUNTIME_STALE_DETAILS[@]}" -gt 0 ]]; then
    runtime_state="stale"
  elif [[ "${#RUNTIME_FOREIGN_DETAILS[@]}" -gt 0 ]]; then
    runtime_state="foreign"
  elif [[ "${#RUNTIME_CURRENT_DETAILS[@]}" -eq 1 ]]; then
    runtime_state="current"
  fi
  printf 'Runtime: %s\n' "$runtime_state"
  case "$runtime_state" in
    stopped|current)
      ;;
    *)
      attention=1
      ;;
  esac

  printf '\nPermissions:\n'
  PERMISSION_ACCESSIBILITY=""
  PERMISSION_SCREEN_RECORDING=""
  if [[ ! -d "$INSTALLED_APP_BUNDLE" || ! -f "$INSTALLED_EXECUTABLE" ]]; then
    permission_status=1
    printf 'permission diagnostic unavailable: canonical Helper is missing\n' >&2
  elif ! verify_signed_bundle \
    "$INSTALLED_APP_BUNDLE" "doctor permission prerequisite"; then
    permission_status=1
    printf 'permission diagnostic unavailable: canonical Helper validation failed\n' >&2
  elif ! permissions_helper; then
    permission_status=1
  fi

  if [[ "$permission_status" -ne 0 ]]; then
    printf 'Accessibility: unavailable\n'
    printf 'Screen Recording: unavailable\n'
    attention=1
  else
    if [[ "$PERMISSION_ACCESSIBILITY" != "granted" \
      || "$PERMISSION_SCREEN_RECORDING" != "granted" ]]; then
      attention=1
    fi
  fi

  printf '\n'
  if [[ "$attention" -eq 0 ]]; then
    printf 'Overall: healthy\n'
    return 0
  fi
  printf 'Overall: attention required\n'
  return 1
}

start_helper() {
  local attempt

  if [[ ! -d "$INSTALLED_APP_BUNDLE" || ! -f "$INSTALLED_EXECUTABLE" ]]; then
    printf 'canonical Helper is missing: %s\n' "$INSTALLED_APP_BUNDLE" >&2
    return 1
  fi
  verify_signed_bundle "$INSTALLED_APP_BUNDLE" "canonical start bundle"
  discover_helper_processes

  if [[ "${#UNRESOLVED_PROCESS_DETAILS[@]}" -gt 0 ]]; then
    printf 'unresolved same-name Helper prevents canonical start\n' >&2
    print_process_list "Unresolved same-name processes" \
      "${UNRESOLVED_PROCESS_DETAILS[@]}" >&2
    return 1
  fi
  if [[ "${#CANONICAL_PIDS[@]}" -gt 1 ]]; then
    printf 'duplicate canonical Helper instances: %s\n' \
      "$(format_pids "${CANONICAL_PIDS[@]}")" >&2
    return 1
  fi
  if [[ "${#CANONICAL_PIDS[@]}" -eq 1 ]]; then
    printf 'canonical Helper already running: PID %s\n' "${CANONICAL_PIDS[0]}"
    return 0
  fi
  if [[ "${#FOREIGN_PROCESS_DETAILS[@]}" -gt 0 ]]; then
    printf 'foreign same-name Helper prevents canonical start\n' >&2
    print_process_list "Foreign same-name processes" \
      "${FOREIGN_PROCESS_DETAILS[@]}" >&2
    return 1
  fi

  if ! "$OPEN_TOOL" "$INSTALLED_APP_BUNDLE"; then
    printf 'failed to launch canonical Helper app: %s\n' \
      "$INSTALLED_APP_BUNDLE" >&2
    return 1
  fi

  for attempt in {1..100}; do
    "$SLEEP_TOOL" 0.1
    discover_helper_processes
    if [[ "${#UNRESOLVED_PROCESS_DETAILS[@]}" -gt 0 ]]; then
      printf 'launched Helper executable mapping is unresolved\n' >&2
      return 1
    fi
    if [[ "${#CANONICAL_PIDS[@]}" -gt 1 ]]; then
      printf 'duplicate canonical Helper instances after launch: %s\n' \
        "$(format_pids "${CANONICAL_PIDS[@]}")" >&2
      return 1
    fi
    if [[ "${#CANONICAL_PIDS[@]}" -eq 1 ]]; then
      if [[ "${#FOREIGN_PROCESS_DETAILS[@]}" -gt 0 ]]; then
        printf 'foreign same-name Helper appeared during canonical start\n' >&2
        return 1
      fi
      printf 'started canonical Helper: PID %s\n' "${CANONICAL_PIDS[0]}"
      return 0
    fi
    if [[ "${#FOREIGN_PROCESS_DETAILS[@]}" -gt 0 ]]; then
      printf 'launched Helper did not map to the canonical executable\n' >&2
      print_process_list "Foreign same-name processes" \
        "${FOREIGN_PROCESS_DETAILS[@]}" >&2
      return 1
    fi
  done

  printf 'timed out waiting for canonical Helper to start\n' >&2
  return 1
}

canonical_pid_present() {
  local wanted_pid="$1"
  local index
  for ((index = 0; index < ${#CANONICAL_PIDS[@]}; index++)); do
    if [[ "${CANONICAL_PIDS[$index]}" == "$wanted_pid" ]]; then
      return 0
    fi
  done
  return 1
}

candidate_pid_present() {
  local wanted_pid="$1"
  local index
  for ((index = 0; index < ${#ALL_CANDIDATE_PIDS[@]}; index++)); do
    if [[ "${ALL_CANDIDATE_PIDS[$index]}" == "$wanted_pid" ]]; then
      return 0
    fi
  done
  return 1
}

detail_pid() {
  local detail="$1"
  detail="${detail#PID }"
  printf '%s\n' "${detail%%:*}"
}

stop_helper() {
  local detail
  local pid
  local target_pid
  local attempt
  local recheck_failed=0
  local remaining_count
  local targets=()
  local signaled_pids=()

  discover_helper_processes
  if [[ "${#FOREIGN_PROCESS_DETAILS[@]}" -gt 0 ]]; then
    for detail in "${FOREIGN_PROCESS_DETAILS[@]}"; do
      printf 'foreign same-name PID not signaled: %s\n' "$(detail_pid "$detail")"
    done
  fi
  if [[ "${#UNRESOLVED_PROCESS_DETAILS[@]}" -gt 0 ]]; then
    for detail in "${UNRESOLVED_PROCESS_DETAILS[@]}"; do
      printf 'unresolved same-name PID not signaled: %s\n' "$(detail_pid "$detail")"
    done
  fi
  if [[ "${#CANONICAL_PIDS[@]}" -eq 0 ]]; then
    printf 'canonical Helper already stopped\n'
    return 0
  fi
  targets=("${CANONICAL_PIDS[@]}")

  for target_pid in "${targets[@]}"; do
    discover_helper_processes
    if ! canonical_pid_present "$target_pid"; then
      printf 'canonical PID %s changed identity before TERM; not signaled\n' \
        "$target_pid" >&2
      recheck_failed=1
      continue
    fi
    printf 'sending TERM to canonical PID %s\n' "$target_pid"
    if ! "$KILL_TOOL" -TERM "$target_pid"; then
      printf 'failed to send TERM to canonical PID %s\n' "$target_pid" >&2
      recheck_failed=1
      continue
    fi
    signaled_pids+=("$target_pid")
  done

  if [[ "${#signaled_pids[@]}" -eq 0 ]]; then
    return 1
  fi
  for attempt in {1..100}; do
    "$SLEEP_TOOL" 0.1
    discover_helper_processes
    remaining_count=0
    for target_pid in "${signaled_pids[@]}"; do
      if candidate_pid_present "$target_pid"; then
        remaining_count=$((remaining_count + 1))
      fi
    done
    if [[ "$remaining_count" -eq 0 ]]; then
      for pid in "${signaled_pids[@]}"; do
        printf 'stopped canonical PID %s\n' "$pid"
      done
      if [[ "$recheck_failed" -ne 0 ]]; then
        return 1
      fi
      return 0
    fi
  done

  discover_helper_processes
  for target_pid in "${signaled_pids[@]}"; do
    if canonical_pid_present "$target_pid"; then
      printf 'stubborn canonical PID after TERM timeout: %s\n' \
        "$target_pid" >&2
    elif candidate_pid_present "$target_pid"; then
      printf 'PID exit could not be confirmed after TERM: %s\n' \
        "$target_pid" >&2
    fi
  done
  return 1
}

create_info_plist() {
  local bundle_path="$1"
  local info_plist="$bundle_path/Contents/Info.plist"

  "$PLISTBUDDY_TOOL" -c 'Clear dict' "$info_plist" 2>/dev/null || true
  "$PLISTBUDDY_TOOL" -c "Add :CFBundleExecutable string '$PROCESS_NAME'" "$info_plist"
  "$PLISTBUDDY_TOOL" -c "Add :CFBundleIdentifier string '$BUNDLE_ID'" "$info_plist"
  "$PLISTBUDDY_TOOL" -c "Add :CFBundleName string '$APP_NAME'" "$info_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :CFBundlePackageType string APPL' "$info_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :CFBundleShortVersionString string 0.1' "$info_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :CFBundleVersion string 1' "$info_plist"
  "$PLISTBUDDY_TOOL" -c "Add :LSMinimumSystemVersion string '$MIN_SYSTEM_VERSION'" "$info_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :LSUIElement bool true' "$info_plist"
  "$PLISTBUDDY_TOOL" -c 'Add :NSPrincipalClass string NSApplication' "$info_plist"
}

copy_non_authoritative_dist() {
  /bin/rm -rf "$APP_BUNDLE"
  /bin/mkdir -p "$DIST_DIR"
  if ! "$DITTO_TOOL" "$AUTHORITATIVE_APP" "$APP_BUNDLE"; then
    printf 'non-authoritative dist copy creation failed\n' >&2
    return 1
  fi
  if ! "$XATTR_TOOL" -cr "$APP_BUNDLE"; then
    printf 'warning: non-authoritative dist copy xattr cleanup failed\n' >&2
  fi
  if ! verify_identity_signed_bundle \
    "$APP_BUNDLE" "non-authoritative dist copy" "$AUTHORITATIVE_BUILD_ID"; then
    printf 'warning: non-authoritative dist copy failed immediate verification; authoritative staging remains valid and install will not read dist\n' >&2
    return 0
  fi
  printf 'dist copy (non-authoritative): %s\n' "$APP_BUNDLE"
}

build_authoritative_bundle() {
  local authoritative_contents
  local authoritative_macos
  local authoritative_binary

  resolve_signing_identity >/dev/null
  env \
    CLANG_MODULE_CACHE_PATH=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/private/tmp/intel-appshot-swiftpm-cache \
    "$SWIFT_TOOL" build --disable-sandbox --product "$PROCESS_NAME"

  BUILD_BINARY="$(env \
    CLANG_MODULE_CACHE_PATH=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/intel-appshot-clang-cache \
    SWIFTPM_CUSTOM_CACHE_PATH=/private/tmp/intel-appshot-swiftpm-cache \
    "$SWIFT_TOOL" build --disable-sandbox --show-bin-path)/$PROCESS_NAME"
  verify_architecture "$BUILD_BINARY" "SwiftPM build product"

  /bin/mkdir -p "$WORKFLOW_STAGING_PARENT"
  WORKFLOW_ROOT="$(mktemp -d "$WORKFLOW_STAGING_PARENT/codex-cu-workflow.XXXXXX")"
  AUTHORITATIVE_APP="$WORKFLOW_ROOT/$APP_NAME.app"
  authoritative_contents="$AUTHORITATIVE_APP/Contents"
  authoritative_macos="$authoritative_contents/MacOS"
  authoritative_binary="$authoritative_macos/$PROCESS_NAME"
  /bin/mkdir -p "$authoritative_macos"
  /bin/cp "$BUILD_BINARY" "$authoritative_binary"
  /bin/chmod +x "$authoritative_binary"
  create_info_plist "$AUTHORITATIVE_APP"
  create_build_identity "$AUTHORITATIVE_APP"
  if ! "$XATTR_TOOL" -cr "$AUTHORITATIVE_APP"; then
    printf 'authoritative bundle: xattr cleanup failed before signing\n' >&2
    return 1
  fi

  if ! "$CODESIGN_TOOL" \
    --force \
    --sign "$EXPECTED_SIGNING_IDENTITY_SHA1" \
    --requirements "=$DESIGNATED_REQUIREMENT" \
    "$AUTHORITATIVE_APP"; then
    printf 'authoritative bundle: signing failed\n' >&2
    return 1
  fi
  verify_identity_signed_bundle \
    "$AUTHORITATIVE_APP" "authoritative bundle" "$AUTHORITATIVE_BUILD_ID"
  printf 'authoritative signed artifact: %s\n' "$AUTHORITATIVE_APP"
  copy_non_authoritative_dist
}

rollback_previous_canonical() {
  local backup_bundle="$1"
  local failure_message="$2"
  local identity_status=0

  /bin/rm -rf "$INSTALLED_APP_BUNDLE"
  if [[ ! -e "$backup_bundle" ]]; then
    printf '%s; no previous canonical bundle existed\n' "$failure_message" >&2
    return 0
  fi
  if ! /bin/mv "$backup_bundle" "$INSTALLED_APP_BUNDLE"; then
    printf '%s; rollback move failed and backup was retained at %s\n' \
      "$failure_message" "$backup_bundle" >&2
    return 1
  fi
  if ! "$XATTR_TOOL" -cr "$INSTALLED_APP_BUNDLE" \
    || ! verify_signed_bundle "$INSTALLED_APP_BUNDLE" "rollback restored canonical"; then
    /bin/mkdir -p "$(dirname "$backup_bundle")"
    if /bin/mv "$INSTALLED_APP_BUNDLE" "$backup_bundle"; then
      printf '%s; rollback verification failed and backup was retained at %s\n' \
        "$failure_message" "$backup_bundle" >&2
    else
      printf '%s; rollback verification failed and canonical removal could not be preserved safely\n' \
        "$failure_message" >&2
    fi
    return 1
  fi
  inspect_build_identity \
    "$INSTALLED_APP_BUNDLE" "rollback restored canonical" || identity_status=$?
  case "$identity_status" in
    0)
      printf 'Build Identity: identity-valid (%s)\n' \
        "$BUILD_IDENTITY_BUILD_ID" >&2
      printf 'Bundle identity classification: identity-valid\n' >&2
      ;;
    2)
      printf 'Build Identity: legacy / missing\n' >&2
      printf 'Bundle identity classification: legacy-valid\n' >&2
      ;;
    *)
      printf 'Build Identity: identity-invalid\n' >&2
      printf 'Bundle identity classification: identity-invalid\n' >&2
      ;;
  esac
  printf '%s; rollback restored and verified previous canonical\n' \
    "$failure_message" >&2
}

install_authoritative_bundle() {
  local staging_root
  local staging_bundle
  local backup_root
  local backup_bundle
  local had_previous=0

  verify_identity_signed_bundle \
    "$AUTHORITATIVE_APP" "authoritative install source" "$AUTHORITATIVE_BUILD_ID"
  /bin/mkdir -p "$INSTALL_DIR"
  staging_root="$(mktemp -d "$INSTALL_DIR/.codex-cu-install.XXXXXX")"
  staging_bundle="$staging_root/$APP_NAME.app"
  backup_root="$(mktemp -d "$INSTALL_DIR/.codex-cu-backup.XXXXXX")"
  backup_bundle="$backup_root/$APP_NAME.app"

  if ! "$DITTO_TOOL" "$AUTHORITATIVE_APP" "$staging_bundle"; then
    printf 'canonical staging: copy from authoritative bundle failed\n' >&2
    /bin/rm -rf "$staging_root" "$backup_root"
    return 1
  fi
  if ! "$XATTR_TOOL" -cr "$staging_bundle"; then
    printf 'canonical staging: xattr cleanup failed\n' >&2
    /bin/rm -rf "$staging_root" "$backup_root"
    return 1
  fi
  if ! verify_identity_signed_bundle \
    "$staging_bundle" "canonical staging bundle" "$AUTHORITATIVE_BUILD_ID"; then
    printf 'canonical staging verification failed; canonical was not modified\n' >&2
    /bin/rm -rf "$staging_root" "$backup_root"
    return 1
  fi

  if [[ -e "$INSTALLED_APP_BUNDLE" ]]; then
    had_previous=1
    if ! /bin/mv "$INSTALLED_APP_BUNDLE" "$backup_bundle"; then
      printf 'canonical replacement: could not move existing bundle to backup\n' >&2
      /bin/rm -rf "$staging_root" "$backup_root"
      return 1
    fi
  fi

  if ! /bin/mv "$staging_bundle" "$INSTALLED_APP_BUNDLE"; then
    rollback_previous_canonical "$backup_bundle" \
      "canonical replacement move failed" || true
    /bin/rm -rf "$staging_root"
    if [[ "$had_previous" -eq 0 || -e "$INSTALLED_APP_BUNDLE" ]]; then
      /bin/rm -rf "$backup_root"
    fi
    return 1
  fi

  if ! "$XATTR_TOOL" -cr "$INSTALLED_APP_BUNDLE" \
    || ! verify_identity_signed_bundle \
      "$INSTALLED_APP_BUNDLE" "canonical final bundle" "$AUTHORITATIVE_BUILD_ID"; then
    rollback_previous_canonical "$backup_bundle" \
      "canonical final verification failed" || true
    /bin/rm -rf "$staging_root"
    if [[ "$had_previous" -eq 0 || -e "$INSTALLED_APP_BUNDLE" ]]; then
      /bin/rm -rf "$backup_root"
    fi
    return 1
  fi

  /bin/rm -rf "$staging_root" "$backup_root"
  printf 'canonical install verified: %s\n' "$INSTALLED_APP_BUNDLE"
}

case "$LIFECYCLE_MODE" in
  --start|start)
    start_helper
    exit $?
    ;;
  --stop|stop)
    stop_helper
    exit $?
    ;;
  --status|status)
    status_helper
    exit 0
    ;;
  --permissions|permissions)
    permissions_helper
    exit $?
    ;;
  --identity|identity)
    identity_helper
    exit $?
    ;;
  --doctor|doctor)
    doctor_helper
    exit $?
    ;;
esac

build_authoritative_bundle

if [[ "$REQUEST_INSTALL" -eq 1 ]]; then
  install_authoritative_bundle
  exit 0
fi
if [[ "$REQUEST_BUILD" -eq 1 ]]; then
  printf '%s\n' "$APP_BUNDLE"
  exit 0
fi

install_authoritative_bundle

case "$LEGACY_MODE" in
  run)
    start_helper
    ;;
  --verify|verify)
    start_helper
    status_helper
    ;;
  --debug|debug)
    start_helper
    discover_helper_processes
    if [[ "${#CANONICAL_PIDS[@]}" -ne 1 ]]; then
      printf 'debug requires exactly one verified canonical Helper PID\n' >&2
      exit 1
    fi
    "$LLDB_TOOL" -p "${CANONICAL_PIDS[0]}"
    ;;
  --logs|logs|--telemetry|telemetry)
    start_helper
    "$LOG_TOOL" stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  *)
    usage
    exit 2
    ;;
esac
