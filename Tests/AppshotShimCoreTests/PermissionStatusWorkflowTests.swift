import Foundation
import Testing

@Test("permissions reports a validated granted/granted diagnostic without state changes")
func permissionsReportsGrantedGrantedReadOnly() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(["--permissions"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Bundle ID: com.openai.sky.CUAService"))
    #expect(
        result.stdout.contains(
            "Executable: \(try fixture.physicalPath(of: fixture.canonicalExecutable))"
        ),
        "\(result.stdout)"
    )
    #expect(result.stdout.contains("Accessibility: granted"))
    #expect(result.stdout.contains("Screen Recording: granted"))
    #expect(result.stdout.hasSuffix("Permission Diagnostic: completed\n"))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(fixture.textIfPresent(at: fixture.processState).isEmpty)
}

@Test("permissions treats denied/granted as a successful diagnostic")
func permissionsReportsDeniedGranted() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "denied",
            "CODEX_CU_FAKE_PERMISSION_SCREEN_RECORDING": "granted"
        ]
    )

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Accessibility: denied"))
    #expect(result.stdout.contains("Screen Recording: granted"))
}

@Test("permissions treats granted/denied as a successful diagnostic")
func permissionsReportsGrantedDenied() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "granted",
            "CODEX_CU_FAKE_PERMISSION_SCREEN_RECORDING": "denied"
        ]
    )

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Accessibility: granted"))
    #expect(result.stdout.contains("Screen Recording: denied"))
}

@Test("permissions treats denied/denied as a successful diagnostic")
func permissionsReportsDeniedDenied() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "denied",
            "CODEX_CU_FAKE_PERMISSION_SCREEN_RECORDING": "denied"
        ]
    )

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Accessibility: denied"))
    #expect(result.stdout.contains("Screen Recording: denied"))
}

@Test("permissions rejects malformed output and retains its evidence")
func permissionsRejectsMalformedOutput() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_OUTPUT_MODE": "malformed"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("permission diagnostic output is malformed"))
    #expect(result.stderr.contains("malformed permission payload"))
    #expect(result.stderr.contains("permission diagnostic evidence retained:"))
}

@Test("permissions rejects duplicate completion markers")
func permissionsRequiresOneFinalCompletionMarker() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_OUTPUT_MODE": "duplicate-marker"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains("completion marker must be unique and final")
    )
}

@Test("permissions fails when the canonical Helper is missing without launching")
func permissionsRejectsMissingCanonicalHelper() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--permissions"])

    #expect(result.status != 0)
    #expect(result.stderr.contains("canonical Helper is missing"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("permissions rejects a canonical Helper that fails strict signing")
func permissionsRejectsInvalidCanonicalSigning() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_STRICT_FAILURE_SCOPE": "all"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "canonical permissions bundle: codesign strict verification failed"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("permissions rejects a non-x86_64 canonical Helper before launching")
func permissionsRejectsInvalidCanonicalArchitecture() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_ARCHS": "arm64"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "architecture verification failed: expected x86_64, got arm64"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
}

@Test("permissions preserves a pre-existing managed Helper and never sends TERM")
func permissionsPreservesExistingManagedHelper() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 5101, mappings: [fixture.canonicalExecutable.path])
    ])
    let before = fixture.textIfPresent(at: fixture.processState)

    let result = try fixture.run(["--permissions"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(fixture.textIfPresent(at: fixture.processState) == before)
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.dittoLog.path))
}

@Test("permissions fails when LaunchServices cannot start the diagnostic")
func permissionsRejectsLaunchServicesFailure() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_OPEN_FAILURE": "1"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "LaunchServices failed to start canonical permission diagnostic"
        )
    )
    #expect(result.stderr.contains("simulated LaunchServices failure"))
    #expect(fixture.textIfPresent(at: fixture.processState).isEmpty)
}

@Test("permissions times out without a completion marker and prints current evidence")
func permissionsTimesOutWithoutCompletionMarker() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_OUTPUT_MODE": "missing-marker"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic timed out: no completion marker"
        )
    )
    #expect(result.stderr.contains("Before PID set: none"))
    #expect(result.stderr.contains("Current PID set: none"))
    #expect(result.stderr.contains("Accessibility: granted"))
    #expect(result.stderr.contains("Screen Recording: granted"))
}

@Test("permissions reports a permission query mechanism failure as infrastructure failure")
func permissionsReportsPermissionQueryFailure() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_OUTPUT_MODE": "query-error"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("no completion marker"))
    #expect(result.stderr.contains("simulated permission query failure"))
}

@Test("permissions fails and reports an added PID when the PID set does not recover")
func permissionsRejectsResidualDiagnosticPID() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_PID_MODE": "retain"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic timed out: PID set did not recover"
        )
    )
    #expect(result.stderr.contains("Before PID set: none"))
    #expect(result.stderr.contains("Current PID set: 4999"))
    #expect(result.stderr.contains("Added PID: 4999"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4999"))
}

@Test("permissions reports a removed pre-existing PID when the PID set does not recover")
func permissionsReportsRemovedPID() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 5102, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(
        ["--permissions"],
        environment: ["CODEX_CU_FAKE_PERMISSION_REMOVE_PID": "5102"]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic timed out: PID set did not recover"
        )
    )
    #expect(result.stderr.contains("Before PID set: 5102"))
    #expect(result.stderr.contains("Current PID set: none"))
    #expect(result.stderr.contains("Removed PID: 5102"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("permissions rejects a status outside granted or denied")
func permissionsRejectsUnknownPermissionStatus() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "unknown"
        ]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic output is malformed: invalid Accessibility value"
        )
    )
}

@Test("permissions rejects a self-reported Bundle ID mismatch")
func permissionsRejectsReportedBundleIdentifierMismatch() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_BUNDLE_ID": "com.example.foreign"
        ]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic identity mismatch: expected Bundle ID"
        )
    )
    #expect(result.stdout.isEmpty)
}

@Test("permissions rejects a self-reported executable realpath mismatch")
func permissionsRejectsReportedExecutableMismatch() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreignExecutable = try fixture.installForeignExecutable()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_EXECUTABLE": foreignExecutable.path
        ]
    )

    #expect(result.status != 0)
    #expect(
        result.stderr.contains(
            "permission diagnostic identity mismatch: expected executable"
        )
    )
    #expect(result.stdout.isEmpty)
}

@Test("permissions uses a fresh output directory for every invocation")
func permissionsUsesUniqueOutputDirectories() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let first = try fixture.run(["--permissions"])
    let second = try fixture.run(["--permissions"])
    let outputPaths = fixture.textIfPresent(at: fixture.openLog)
        .split(separator: "\n")
        .compactMap { line -> String? in
            let prefix = "permission-stdout\t"
            guard line.hasPrefix(prefix) else { return nil }
            return String(line.dropFirst(prefix.count))
        }

    #expect(first.status == 0, "\(first.stderr)")
    #expect(second.status == 0, "\(second.stderr)")
    #expect(outputPaths.count == 2)
    if outputPaths.count == 2 {
        let firstDirectory = URL(fileURLWithPath: outputPaths[0])
            .deletingLastPathComponent()
        let secondDirectory = URL(fileURLWithPath: outputPaths[1])
            .deletingLastPathComponent()
        #expect(firstDirectory.path != secondDirectory.path)
        #expect(
            firstDirectory.lastPathComponent.hasPrefix("codex-cu-permissions.")
        )
        #expect(
            secondDirectory.lastPathComponent.hasPrefix("codex-cu-permissions.")
        )
        #expect(!FileManager.default.fileExists(atPath: firstDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: secondDirectory.path))
    }
}

@Test("permissions surfaces Helper warnings from stderr on success")
func permissionsSurfacesHelperWarnings() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--permissions"],
        environment: [
            "CODEX_CU_FAKE_PERMISSION_STDERR": "simulated Helper warning"
        ]
    )

    #expect(result.status == 0)
    #expect(result.stderr.contains("simulated Helper warning"))
    #expect(result.stdout.contains("Permission Diagnostic: completed"))
}
