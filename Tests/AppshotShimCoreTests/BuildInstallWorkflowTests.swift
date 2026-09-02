import Foundation
import Testing

final class IsolatedWorkflowFixture {
    let root: URL
    let toolsDirectory: URL
    let scriptURL: URL
    let buildDirectory: URL
    let buildCountLog: URL
    let codesignLog: URL
    let dittoLog: URL
    let distApp: URL
    let canonicalApp: URL
    let plistPathLog: URL
    let pkillLog: URL
    let processState: URL
    let openLog: URL
    let termLog: URL
    let systemLog: URL
    let lldbLog: URL
    let uuidLog: URL
    let gitLog: URL
    let xattrLog: URL

    init() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let requestedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-cu-workflow-tests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: requestedRoot,
            withIntermediateDirectories: true
        )
        scriptURL = repositoryRoot.appendingPathComponent("script/build_and_run.sh")
        root = requestedRoot.resolvingSymlinksInPath()
        toolsDirectory = root.appendingPathComponent("tools")
        buildDirectory = root.appendingPathComponent("build")
        buildCountLog = root.appendingPathComponent("build-count.log")
        codesignLog = root.appendingPathComponent("codesign.log")
        dittoLog = root.appendingPathComponent("ditto.log")
        distApp = root.appendingPathComponent("dist/Codex Computer Use.app")
        canonicalApp = root.appendingPathComponent("install/Codex Computer Use.app")
        plistPathLog = root.appendingPathComponent("plist-paths.log")
        pkillLog = root.appendingPathComponent("pkill.log")
        processState = root.appendingPathComponent("process-state.tsv")
        openLog = root.appendingPathComponent("open.log")
        termLog = root.appendingPathComponent("term.log")
        systemLog = root.appendingPathComponent("system-log.log")
        lldbLog = root.appendingPathComponent("lldb.log")
        uuidLog = root.appendingPathComponent("uuid.log")
        gitLog = root.appendingPathComponent("git.log")
        xattrLog = root.appendingPathComponent("xattr.log")
        try FileManager.default.createDirectory(
            at: toolsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: buildDirectory,
            withIntermediateDirectories: true
        )
        try Data("codex-cu-workflow-test-fixture-v1".utf8).write(
            to: root.appendingPathComponent(".codex-cu-workflow-test-root")
        )

        try writeExecutable(
            named: "security",
            contents: #"""
#!/bin/bash
printf 'isolated security shim invoked\n' >&2
if [[ "${CODEX_CU_FAKE_IDENTITY_MODE:-valid}" == "missing" ]]; then
  printf '     0 valid identities found\n'
elif [[ "${CODEX_CU_FAKE_IDENTITY_MODE:-valid}" == "wrong-fingerprint" ]]; then
  printf '  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Codex Computer Use Local Development"\n'
  printf '     1 valid identities found\n'
elif [[ "${CODEX_CU_FAKE_IDENTITY_MODE:-valid}" == "duplicate" ]]; then
  printf '  1) 7B958AD0A1A95B41F8F78C307FC0AA4651D08807 "Codex Computer Use Local Development"\n'
  printf '  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Codex Computer Use Local Development"\n'
  printf '     2 valid identities found\n'
else
  printf '  1) 7B958AD0A1A95B41F8F78C307FC0AA4651D08807 "Codex Computer Use Local Development"\n'
  printf '     1 valid identities found\n'
fi
"""#
        )
        try writeExecutable(
            named: "pkill",
            contents: #"""
#!/bin/bash
printf 'pkill invoked\n' >> "$CODEX_CU_FAKE_PKILL_LOG"
exit 0
"""#
        )
        try writeExecutable(
            named: "pgrep",
            contents: #"""
#!/bin/bash
if [[ "${CODEX_CU_FAKE_PGREP_ERROR:-0}" == "1" ]]; then
  exit 2
fi
if [[ ! -s "$CODEX_CU_FAKE_PROCESS_STATE" ]]; then
  exit 1
fi
/usr/bin/awk -F '\t' 'NF >= 2 { print $1 }' "$CODEX_CU_FAKE_PROCESS_STATE"
"""#
        )
        try writeExecutable(
            named: "lsof",
            contents: #"""
#!/bin/bash
pid=""
identity_fields=0
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "-p" && "$#" -ge 2 ]]; then
    pid="$2"
    shift 2
  elif [[ "$1" == "-F" && "$#" -ge 2 ]]; then
    if [[ "$2" == *D* && "$2" == *i* ]]; then
      identity_fields=1
    fi
    shift 2
  elif [[ "$1" == -F* ]]; then
    if [[ "${1#-F}" == *D* && "${1#-F}" == *i* ]]; then
      identity_fields=1
    fi
    shift
  else
    shift
  fi
done
line="$(/usr/bin/awk -F '\t' -v wanted="$pid" '$1 == wanted { print; exit }' "$CODEX_CU_FAKE_PROCESS_STATE" 2>/dev/null)"
if [[ -z "$line" ]]; then
  exit 1
fi
payload="${line#*$'\t'}"
if [[ "$payload" == "__MALFORMED__" ]]; then
  printf 'p%s\nftxt\nn\n' "$pid"
  exit 0
fi
printf 'p%s\n' "$pid"
IFS='|' read -r -a mappings <<< "$payload"
for mapping in "${mappings[@]}"; do
  IFS='^' read -r path device inode <<< "$mapping"
  printf 'ftxt\n'
  if [[ "$identity_fields" -eq 1 ]]; then
    if [[ "$device" == "__MISSING__" || "$inode" == "__MISSING__" ]]; then
      printf 'n%s\n' "$path"
      continue
    fi
    if [[ -z "$device" || -z "$inode" ]]; then
      read -r device inode < <(/usr/bin/stat -f '%d %i' "$path")
    fi
    printf 'D0x%x\ni%s\n' "$device" "$inode"
  fi
  printf 'n%s\n' "$path"
done
"""#
        )
        try writeExecutable(
            named: "realpath",
            contents: #"""
#!/bin/bash
exec /bin/realpath "$@"
"""#
        )
        try writeExecutable(
            named: "open",
            contents: #"""
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_OPEN_LOG"
if [[ " $* " == *" --permission-status "* ]]; then
  if [[ "${CODEX_CU_FAKE_OPEN_FAILURE:-0}" == "1" ]]; then
    printf 'simulated LaunchServices failure\n' >&2
    exit 72
  fi

  stdout_path=""
  stderr_path=""
  app_path=""
  saw_new=0
  saw_background=0
  saw_permission_argument=0
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -n)
        saw_new=1
        shift
        ;;
      -g)
        saw_background=1
        shift
        ;;
      --stdout)
        stdout_path="$2"
        shift 2
        ;;
      --stderr)
        stderr_path="$2"
        shift 2
        ;;
      --args)
        shift
        if [[ "$#" -eq 1 && "$1" == "--permission-status" ]]; then
          saw_permission_argument=1
          shift
        else
          printf 'invalid permission diagnostic arguments\n' >&2
          exit 73
        fi
        ;;
      *)
        if [[ -z "$app_path" ]]; then
          app_path="$1"
          shift
        else
          printf 'unexpected permission diagnostic argument: %s\n' "$1" >&2
          exit 73
        fi
        ;;
    esac
  done
  if [[ "$saw_new" -ne 1 || "$saw_background" -ne 1 \
    || "$saw_permission_argument" -ne 1 \
    || "$app_path" != "$CODEX_CU_FAKE_CANONICAL_APP" \
    || -z "$stdout_path" || -z "$stderr_path" ]]; then
    printf 'invalid canonical permission diagnostic launch\n' >&2
    exit 73
  fi

  printf 'permission-stdout\t%s\n' "$stdout_path" >> "$CODEX_CU_FAKE_OPEN_LOG"
  printf 'permission-stderr\t%s\n' "$stderr_path" >> "$CODEX_CU_FAKE_OPEN_LOG"
  diagnostic_pid="${CODEX_CU_FAKE_PERMISSION_PID:-4999}"
  printf '%s\t%s\n' "$diagnostic_pid" \
    "$CODEX_CU_FAKE_CANONICAL_EXECUTABLE" >> "$CODEX_CU_FAKE_PROCESS_STATE"

  output_mode="${CODEX_CU_FAKE_PERMISSION_OUTPUT_MODE:-normal}"
  bundle_identifier="${CODEX_CU_FAKE_PERMISSION_BUNDLE_ID:-com.openai.sky.CUAService}"
  executable_path="${CODEX_CU_FAKE_PERMISSION_EXECUTABLE:-$(/bin/realpath "$CODEX_CU_FAKE_CANONICAL_EXECUTABLE")}"
  accessibility="${CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY:-granted}"
  screen_recording="${CODEX_CU_FAKE_PERMISSION_SCREEN_RECORDING:-granted}"
  case "$output_mode" in
    normal)
      printf 'Bundle ID: %s\nExecutable: %s\nAccessibility: %s\nScreen Recording: %s\nPermission Diagnostic: completed\n' \
        "$bundle_identifier" "$executable_path" "$accessibility" \
        "$screen_recording" > "$stdout_path"
      ;;
    malformed)
      printf 'malformed permission payload\nPermission Diagnostic: completed\n' \
        > "$stdout_path"
      ;;
    missing-marker)
      printf 'Bundle ID: %s\nExecutable: %s\nAccessibility: %s\nScreen Recording: %s\n' \
        "$bundle_identifier" "$executable_path" "$accessibility" \
        "$screen_recording" > "$stdout_path"
      ;;
    duplicate-marker)
      printf 'Bundle ID: %s\nExecutable: %s\nAccessibility: %s\nScreen Recording: %s\nPermission Diagnostic: completed\nPermission Diagnostic: completed\n' \
        "$bundle_identifier" "$executable_path" "$accessibility" \
        "$screen_recording" > "$stdout_path"
      ;;
    query-error)
      printf 'simulated permission query failure\n' > "$stderr_path"
      ;;
  esac
  if [[ -n "${CODEX_CU_FAKE_PERMISSION_STDERR:-}" ]]; then
    printf '%s\n' "$CODEX_CU_FAKE_PERMISSION_STDERR" >> "$stderr_path"
  fi

  if [[ "${CODEX_CU_FAKE_PERMISSION_PID_MODE:-restore}" != "retain" ]]; then
    removed_pid="${CODEX_CU_FAKE_PERMISSION_REMOVE_PID:-}"
    /usr/bin/awk -F '\t' -v completed="$diagnostic_pid" -v removed="$removed_pid" \
      '$1 != completed && (removed == "" || $1 != removed) { print }' \
      "$CODEX_CU_FAKE_PROCESS_STATE" \
      > "$CODEX_CU_FAKE_PROCESS_STATE.tmp"
    /bin/mv "$CODEX_CU_FAKE_PROCESS_STATE.tmp" "$CODEX_CU_FAKE_PROCESS_STATE"
  fi
  exit 0
fi
if [[ "${CODEX_CU_FAKE_OPEN_NO_PROCESS:-0}" == "1" ]]; then
  exit 0
fi
pid="${CODEX_CU_FAKE_NEXT_PID:-4200}"
mapping="${CODEX_CU_FAKE_OPEN_MAPPING:-$CODEX_CU_FAKE_CANONICAL_EXECUTABLE}"
printf '%s\t%s\n' "$pid" "$mapping" >> "$CODEX_CU_FAKE_PROCESS_STATE"
"""#
        )
        try writeExecutable(
            named: "sleep",
            contents: #"""
#!/bin/bash
exit 0
"""#
        )
        try writeExecutable(
            named: "kill",
            contents: #"""
#!/bin/bash
signal="$1"
pid="$2"
printf '%s %s\n' "$signal" "$pid" >> "$CODEX_CU_FAKE_TERM_LOG"
case " ${CODEX_CU_FAKE_STUBBORN_PIDS:-} " in
  *" $pid "*)
    exit 0
    ;;
esac
/usr/bin/awk -F '\t' -v stopped="$pid" '$1 != stopped { print }' \
  "$CODEX_CU_FAKE_PROCESS_STATE" > "$CODEX_CU_FAKE_PROCESS_STATE.tmp"
/bin/mv "$CODEX_CU_FAKE_PROCESS_STATE.tmp" "$CODEX_CU_FAKE_PROCESS_STATE"
"""#
        )
        try writeExecutable(
            named: "log",
            contents: #"""
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_SYSTEM_LOG"
exit 0
"""#
        )
        try writeExecutable(
            named: "lldb",
            contents: #"""
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_LLDB_LOG"
exit 0
"""#
        )
        try writeExecutable(
            named: "swift",
            contents: #"""
#!/bin/bash
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$CODEX_CU_FAKE_BUILD_DIR"
  exit 0
fi
printf 'build\n' >> "$CODEX_CU_FAKE_BUILD_COUNT_LOG"
printf '#!/bin/bash\nexit 0\n' > "$CODEX_CU_FAKE_BUILD_DIR/SkyComputerUseService"
chmod +x "$CODEX_CU_FAKE_BUILD_DIR/SkyComputerUseService"
"""#
        )
        try writeExecutable(
            named: "PlistBuddy",
            contents: #"""
#!/bin/bash
printf '%s\n' "${@: -1}" >> "$CODEX_CU_FAKE_PLIST_PATH_LOG"
if [[ "$2" == "Print :CFBundleIdentifier" && -n "${CODEX_CU_FAKE_BUNDLE_ID:-}" ]]; then
  printf '%s\n' "$CODEX_CU_FAKE_BUNDLE_ID"
  exit 0
fi
if [[ "${CODEX_CU_FAKE_PLIST_PROBE_ONLY:-0}" == "1" ]]; then
  printf 'plist probe stopped workflow\n' >&2
  exit 95
fi
exec /usr/libexec/PlistBuddy "$@"
"""#
        )
        try writeExecutable(
            named: "lipo",
            contents: #"""
#!/bin/bash
printf '%s\n' "${CODEX_CU_FAKE_ARCHS:-x86_64}"
"""#
        )
        try writeExecutable(
            named: "ditto",
            contents: #"""
#!/bin/bash
printf '%s\t%s\n' "$1" "$2" >> "$CODEX_CU_FAKE_DITTO_LOG"
if [[ "${CODEX_CU_FAKE_DITTO_FAILURE_SCOPE:-}" == "dist" \
  && "$2" == "$CODEX_CU_FAKE_DIST_APP" ]]; then
  printf 'simulated dist copy failure\n' >&2
  exit 97
fi
exec /usr/bin/ditto "$@"
"""#
        )
        try writeExecutable(
            named: "xattr",
            contents: #"""
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_XATTR_LOG"
if [[ "$#" -eq 1 && "$1" == "$CODEX_CU_FAKE_DIST_APP" \
  && -e "$1/.dist-polluted" ]]; then
  printf 'com.apple.FinderInfo\n'
  exit 0
fi
/usr/bin/xattr "$@"
status=$?
target="${@: -1}"
if [[ "$status" -eq 0 && "${CODEX_CU_FAKE_REATTACH_DIST_XATTR:-0}" == "1" \
  && "$target" == "$CODEX_CU_FAKE_DIST_APP" ]]; then
  touch "$target/.dist-polluted"
fi
if [[ "$status" -eq 0 && "${CODEX_CU_FAKE_FINAL_BUILD_ID_MISMATCH:-0}" == "1" \
  && "$target" == "$CODEX_CU_FAKE_CANONICAL_APP" \
  && -e "$target/Contents/.workflow-new-build" ]]; then
  /usr/libexec/PlistBuddy -c \
    'Set :buildID 99999999-9999-4999-8999-999999999999' \
    "$target/Contents/Resources/BuildIdentity.plist"
fi
exit "$status"
"""#
        )
        try writeExecutable(
            named: "uuidgen",
            contents: #"""
#!/bin/bash
count=0
if [[ -f "$CODEX_CU_FAKE_UUID_LOG" ]]; then
  count="$(/usr/bin/wc -l < "$CODEX_CU_FAKE_UUID_LOG" | /usr/bin/tr -d ' ')"
fi
case "$count" in
  0) value='11111111-1111-4111-8111-111111111111' ;;
  1) value='22222222-2222-4222-8222-222222222222' ;;
  *) value='33333333-3333-4333-8333-333333333333' ;;
esac
if [[ "${CODEX_CU_FAKE_MALFORMED_BUILD_ID:-0}" == "1" ]]; then
  value='not-a-uuid'
fi
printf '%s\n' "$value" >> "$CODEX_CU_FAKE_UUID_LOG"
printf '%s\n' "$value"
"""#
        )
        try writeExecutable(
            named: "git",
            contents: #"""
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_GIT_LOG"
if [[ "$*" == *" rev-parse HEAD" ]]; then
  printf '%s\n' "${CODEX_CU_FAKE_GIT_HEAD:-0123456789abcdef0123456789abcdef01234567}"
  exit 0
fi
if [[ "$*" == *" status --porcelain --untracked-files=normal" ]]; then
  if [[ -n "${CODEX_CU_FAKE_GIT_STATUS:-}" ]]; then
    printf '%s\n' "$CODEX_CU_FAKE_GIT_STATUS"
  fi
  exit 0
fi
printf 'unsupported fake git invocation: %s\n' "$*" >&2
exit 94
"""#
        )
        try writeExecutable(
            named: "stat",
            contents: #"""
#!/bin/bash
if [[ "${CODEX_CU_FAKE_STAT_FAILURE:-0}" == "1" ]]; then
  exit 1
fi
exec /usr/bin/stat "$@"
"""#
        )
        try writeExecutable(
            named: "shasum",
            contents: #"""
#!/bin/bash
target="${@: -1}"
if [[ "$target" == "$CODEX_CU_FAKE_CANONICAL_APP/Contents/MacOS/SkyComputerUseService" \
  && -n "${CODEX_CU_FAKE_CANONICAL_SHA256:-}" ]]; then
  printf '%s  %s\n' "$CODEX_CU_FAKE_CANONICAL_SHA256" "$target"
  exit 0
fi
if [[ "$target" == "$CODEX_CU_FAKE_DIST_APP/Contents/MacOS/SkyComputerUseService" \
  && -n "${CODEX_CU_FAKE_DIST_SHA256:-}" ]]; then
  printf '%s  %s\n' "$CODEX_CU_FAKE_DIST_SHA256" "$target"
  exit 0
fi
exec /usr/bin/shasum "$@"
"""#
        )
        try writeExecutable(
            named: "codesign",
            contents: #"""
#!/bin/bash
bundle="${@: -1}"
printf '%s\n' "$*" >> "$CODEX_CU_FAKE_CODESIGN_LOG"

if [[ " $* " == *" --force "* ]]; then
  mkdir -p "$bundle/Contents"
  touch "$bundle/Contents/.workflow-new-build"
  exit 0
fi

if [[ " $* " == *" --verify "* ]]; then
  if [[ -e "$bundle/.dist-polluted" ]]; then
    printf 'simulated dist metadata verification failure\n' >&2
    exit 1
  fi
  if [[ "${CODEX_CU_FAKE_STRICT_FAILURE_SCOPE:-}" == "all" \
    && " $* " == *" --strict "* ]]; then
    printf 'simulated strict verification failure\n' >&2
    exit 1
  fi
  if [[ "${CODEX_CU_FAKE_FINAL_VERIFY_FAILURE:-0}" == "1" \
    && "$bundle" == "$CODEX_CU_FAKE_CANONICAL_APP" \
    && -e "$bundle/Contents/.workflow-new-build" \
    && " $* " == *" --strict "* ]]; then
    printf 'simulated canonical final verification failure\n' >&2
    exit 1
  fi
  exit 0
fi

if [[ " $* " == *" -dvvv "* ]]; then
  printf 'Identifier=%s\n' "${CODEX_CU_FAKE_SIGNED_IDENTIFIER:-com.openai.sky.CUAService}"
  printf 'Authority=%s\n' "${CODEX_CU_FAKE_AUTHORITY:-Codex Computer Use Local Development}"
  printf 'CDHash=%s\n' "${CODEX_CU_FAKE_CDHASH:-0123456789abcdef0123456789abcdef01234567}"
  exit 0
fi

if [[ " $* " == *" -d -r- "* ]]; then
  printf 'Executable=%s\n' "$bundle/Contents/MacOS/SkyComputerUseService"
  printf '%s\n' "${CODEX_CU_FAKE_DESIGNATED_REQUIREMENT:-designated => identifier \"com.openai.sky.CUAService\" and certificate leaf = H\"7b958ad0a1a95b41f8f78c307fc0aa4651d08807\"}"
  exit 0
fi

printf 'unsupported fake codesign invocation: %s\n' "$*" >&2
exit 96
"""#
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func run(
        _ arguments: [String],
        environment overrides: [String: String] = [:]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--workflow-test-mode"] + arguments

        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_CU_WORKFLOW_TESTING"] = "1"
        environment["CODEX_CU_TEST_ROOT"] = root.path
        environment["CODEX_CU_FAKE_BUILD_DIR"] = buildDirectory.path
        environment["CODEX_CU_FAKE_BUILD_COUNT_LOG"] = root
            .appendingPathComponent("build-count.log").path
        environment["CODEX_CU_FAKE_CODESIGN_LOG"] = codesignLog.path
        environment["CODEX_CU_FAKE_DITTO_LOG"] = dittoLog.path
        environment["CODEX_CU_FAKE_DIST_APP"] = distApp.path
        environment["CODEX_CU_FAKE_CANONICAL_APP"] = canonicalApp.path
        environment["CODEX_CU_FAKE_PLIST_PATH_LOG"] = plistPathLog.path
        environment["CODEX_CU_FAKE_PKILL_LOG"] = pkillLog.path
        environment["CODEX_CU_FAKE_PROCESS_STATE"] = processState.path
        environment["CODEX_CU_FAKE_OPEN_LOG"] = openLog.path
        environment["CODEX_CU_FAKE_CANONICAL_EXECUTABLE"] = canonicalExecutable.path
        environment["CODEX_CU_FAKE_TERM_LOG"] = termLog.path
        environment["CODEX_CU_FAKE_SYSTEM_LOG"] = systemLog.path
        environment["CODEX_CU_FAKE_LLDB_LOG"] = lldbLog.path
        environment["CODEX_CU_FAKE_UUID_LOG"] = uuidLog.path
        environment["CODEX_CU_FAKE_GIT_LOG"] = gitLog.path
        environment["CODEX_CU_FAKE_XATTR_LOG"] = xattrLog.path
        environment["PATH"] = "\(toolsDirectory.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(
                decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            String(
                decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }

    private func writeExecutable(named name: String, contents: String) throws {
        let url = toolsDirectory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    func installExistingCanonical(
        marker: String = "old canonical",
        includeBuildIdentity: Bool = true,
        buildID: String = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    ) throws {
        let contents = canonicalApp.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: contents.appendingPathComponent("old-install-marker"))
        try Data("old executable\n".utf8).write(
            to: macOS.appendingPathComponent("SkyComputerUseService")
        )
        let plist: [String: Any] = [
            "CFBundleExecutable": "SkyComputerUseService",
            "CFBundleIdentifier": "com.openai.sky.CUAService",
            "CFBundleName": "Codex Computer Use",
            "CFBundlePackageType": "APPL"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))
        if includeBuildIdentity {
            try installBuildIdentity(in: canonicalApp, buildID: buildID)
        }
    }

    func installBuildIdentity(
        in app: URL,
        buildID: String,
        gitHEAD: String = "0123456789abcdef0123456789abcdef01234567",
        gitDirty: Bool = true
    ) throws {
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(
            at: resources,
            withIntermediateDirectories: true
        )
        let identity: [String: Any] = [
            "buildID": buildID,
            "gitHEAD": gitHEAD,
            "gitDirty": gitDirty,
            "architecture": "x86_64",
            "bundleIdentifier": "com.openai.sky.CUAService"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: identity,
            format: .xml,
            options: 0
        )
        try data.write(
            to: resources.appendingPathComponent("BuildIdentity.plist")
        )
    }

    var canonicalExecutable: URL {
        canonicalApp.appendingPathComponent("Contents/MacOS/SkyComputerUseService")
    }

    @discardableResult
    func installForeignExecutable(named directoryName: String = "foreign") throws -> URL {
        let executable = root
            .appendingPathComponent(directoryName)
            .appendingPathComponent("SkyComputerUseService")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("foreign executable\n".utf8).write(to: executable)
        return executable
    }

    func setProcesses(_ processes: [(pid: Int, mappings: [String])]) throws {
        let rows = processes.map { process in
            "\(process.pid)\t\(process.mappings.joined(separator: "|"))"
        }
        try Data(rows.joined(separator: "\n").appending("\n").utf8)
            .write(to: processState)
    }

    func setMalformedProcess(pid: Int) throws {
        try Data("\(pid)\t__MALFORMED__\n".utf8).write(to: processState)
    }

    func setProcess(
        pid: Int,
        mapping: String,
        device: UInt64,
        inode: UInt64
    ) throws {
        try Data("\(pid)\t\(mapping)^\(device)^\(inode)\n".utf8)
            .write(to: processState)
    }

    func fileIdentity(of url: URL) throws -> (device: UInt64, inode: UInt64) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        return (device.uint64Value, inode.uint64Value)
    }

    func buildIdentity(in app: URL) throws -> [String: Any] {
        let url = app.appendingPathComponent(
            "Contents/Resources/BuildIdentity.plist"
        )
        let data = try Data(contentsOf: url)
        guard let identity = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return identity
    }

    func textIfPresent(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func physicalPath(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/realpath")
        process.arguments = [url.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func expectedCanonicalAppPhysicalPath() throws -> String {
        try physicalPath(of: root) + "/install/Codex Computer Use.app"
    }
}

@Test("validated workflow test mode uses only its isolated security shim")
func validatedWorkflowTestModeUsesIsolatedSecurityShim() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_IDENTITY_MODE": "missing"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "signing identity not found: Codex Computer Use Local Development"
        )
    )
    #expect(result.stderr.contains("isolated security shim invoked"))
    #expect(!FileManager.default.fileExists(atPath: fixture.pkillLog.path))
}

@Test("workflow test mode confines generated dist paths to its validated fixture root")
func workflowTestModeConfinesGeneratedPathsToFixtureRoot() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_PLIST_PROBE_ONLY": "1"]
    )

    let loggedPaths = try String(contentsOf: fixture.plistPathLog, encoding: .utf8)
    #expect(result.status != 0)
    #expect(
        loggedPaths.contains(
            "/\(fixture.root.lastPathComponent)/staging/codex-cu-workflow."
        )
    )
    #expect(!loggedPaths.contains("/Users/a66/Documents/ChatGPT/智能快照/dist"))
}

@Test("build signs and verifies without stopping a running Helper")
func buildDoesNotInvokePkill() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--build"])

    #expect(result.status == 0)
    #expect(!FileManager.default.fileExists(atPath: fixture.pkillLog.path))
    #expect(fixture.textIfPresent(at: fixture.buildCountLog) == "build\n")
    #expect(FileManager.default.fileExists(atPath: fixture.distApp.path))
}

@Test("build fails when it cannot create the requested non-authoritative dist copy")
func buildFailsWhenDistCopyCannotBeCreated() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_DITTO_FAILURE_SCOPE": "dist"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "non-authoritative dist copy creation failed"
        )
    )
}

@Test("build rejects an executable that is not exactly x86_64")
func buildRejectsNonX8664Architecture() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_ARCHS": "arm64"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "architecture verification failed: expected x86_64, got arm64"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.distApp.path))
}

@Test("build rejects the stable identity label when its certificate fingerprint changed")
func buildRejectsUnexpectedSigningFingerprint() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_IDENTITY_MODE": "wrong-fingerprint"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "signing identity fingerprint mismatch: expected 7B958AD0A1A95B41F8F78C307FC0AA4651D08807, got AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
    )
}

@Test("build rejects duplicate stable signing identities")
func buildRejectsDuplicateStableSigningIdentities() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_IDENTITY_MODE": "duplicate"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "signing identity is not unique: Codex Computer Use Local Development (2 matches)"
        )
    )
}

@Test("authoritative bundle verification rejects a wrong Bundle ID")
func authoritativeVerificationRejectsWrongBundleIdentifier() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_BUNDLE_ID": "com.example.wrong"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "unexpected Bundle Identifier: expected com.openai.sky.CUAService, got com.example.wrong"
        )
    )
}

@Test("authoritative bundle verification rejects a wrong designated requirement")
func authoritativeVerificationRejectsWrongDesignatedRequirement() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: [
            "CODEX_CU_FAKE_DESIGNATED_REQUIREMENT": "designated => identifier \"com.example.wrong\""
        ]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("unexpected designated requirement"))
}

@Test("authoritative bundle verification explicitly rejects a CDHash-only requirement")
func authoritativeVerificationRejectsCDHashOnlyRequirement() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: [
            "CODEX_CU_FAKE_DESIGNATED_REQUIREMENT": "designated => cdhash H\"0123456789abcdef\""
        ]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "designated requirement must not contain an executable CDHash"
        )
    )
}

@Test("strict verification failure prevents any canonical replacement")
func strictVerificationFailurePreventsInstall() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_STRICT_FAILURE_SCOPE": "all"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "authoritative bundle: codesign strict verification failed"
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/old-install-marker").path
        )
    )
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/.workflow-new-build").path
        )
    )
}

@Test("build plus install compiles once and installs the same authoritative staging bundle")
func buildAndInstallReuseOneAuthoritativeBuild() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--build", "--install"])
    let dittoLog = fixture.textIfPresent(at: fixture.dittoLog)

    #expect(result.status == 0)
    #expect(fixture.textIfPresent(at: fixture.buildCountLog) == "build\n")
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/.workflow-new-build").path
        )
    )
    #expect(dittoLog.contains("/staging/codex-cu-workflow."))
    #expect(!dittoLog.contains("\(fixture.distApp.path)\t\(fixture.root.path)/install/"))
}

@Test("dist metadata pollution is reported but install still uses authoritative staging")
func distPollutionCannotBecomeInstallSource() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_REATTACH_DIST_XATTR": "1"]
    )

    #expect(result.status == 0)
    #expect(
        result.stderr.contains(
            "warning: non-authoritative dist copy failed immediate verification"
        )
    )
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/.workflow-new-build").path
        )
    )
}

@Test("canonical final verification failure restores and verifies the prior bundle")
func canonicalFinalVerificationFailureRollsBackAndVerifies() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical(includeBuildIdentity: false)

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_FINAL_VERIFY_FAILURE": "1"]
    )
    let codesignLog = fixture.textIfPresent(at: fixture.codesignLog)
    let canonicalStrictVerifications = codesignLog
        .split(separator: "\n")
        .filter {
            $0.contains("--strict") && $0.contains(fixture.canonicalApp.path)
        }

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "canonical final verification failed; rollback restored and verified previous canonical"
        )
    )
    #expect(canonicalStrictVerifications.count >= 2)
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/old-install-marker").path
        )
    )
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/.workflow-new-build").path
        )
    )
}
