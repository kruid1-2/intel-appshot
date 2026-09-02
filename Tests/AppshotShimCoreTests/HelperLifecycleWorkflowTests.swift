import Foundation
import Testing

@Test("status reports an installed canonical Helper as stopped without building")
func statusReportsStoppedWithoutBuilding() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Installed Helper: installed"))
    #expect(result.stdout.contains("Running Helper: stopped"))
    #expect(result.stdout.contains("Foreign same-name processes: none"))
    #expect(result.stdout.contains("Unresolved same-name processes: none"))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("status recognizes one canonical Helper from an exact executable text mapping")
func statusReportsOneCanonicalProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4101, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: running"))
    #expect(result.stdout.contains("PID: 4101"))
    #expect(
        result.stdout.contains(
            "Executable: \(try fixture.physicalPath(of: fixture.canonicalExecutable))"
        )
    )
    #expect(result.stdout.contains("Architecture: x86_64"))
    #expect(result.stdout.contains("Bundle ID: com.openai.sky.CUAService"))
    #expect(result.stdout.contains("Authority: Codex Computer Use Local Development"))
    #expect(result.stdout.contains("CDHash:"))
    #expect(result.stdout.contains("Designated Requirement: designated => identifier"))
}

@Test("status treats multiple text mappings as canonical only when one realpath is exact")
func statusFindsCanonicalAmongMultipleTextMappings() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([
        (
            pid: 4102,
            mappings: [foreign.path, fixture.canonicalExecutable.path]
        )
    ])

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: running"))
    #expect(result.stdout.contains("PID: 4102"))
    #expect(result.stdout.contains("Foreign same-name processes: none"))
}

@Test("status keeps exact canonical proof when another text mapping cannot be resolved")
func statusFindsCanonicalDespiteUnresolvableAuxiliaryTextMapping() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let missingAuxiliaryMapping = fixture.root
        .appendingPathComponent("missing-runtime-resource.dat")
    try fixture.setProcesses([
        (
            pid: 4107,
            mappings: [
                fixture.canonicalExecutable.path,
                missingAuxiliaryMapping.path
            ]
        )
    ])

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: running"))
    #expect(result.stdout.contains("PID: 4107"))
    #expect(result.stdout.contains("Unresolved same-name processes: none"))
}

@Test("status reports same-name processes with no exact canonical mapping as foreign")
func statusReportsForeignProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let first = try fixture.installForeignExecutable(named: "foreign-one")
    let second = try fixture.installForeignExecutable(named: "foreign-two")
    try fixture.setProcesses([
        (pid: 4103, mappings: [first.path, second.path])
    ])

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: stopped"))
    #expect(result.stdout.contains("Foreign same-name processes:"))
    #expect(
        result.stdout.contains(
            "PID 4103: \(try fixture.physicalPath(of: first)), \(try fixture.physicalPath(of: second))"
        )
    )
}

@Test("status reports duplicate canonical Helpers explicitly")
func statusReportsDuplicateCanonicalProcesses() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4104, mappings: [fixture.canonicalExecutable.path]),
        (pid: 4105, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: duplicate"))
    #expect(result.stdout.contains("Canonical PIDs: 4104 4105"))
}

@Test("status reports malformed executable mapping output as unresolved")
func statusReportsUnresolvedProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setMalformedProcess(pid: 4106)

    let result = try fixture.run(["--status"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("Running Helper: stopped"))
    #expect(result.stdout.contains("Unresolved same-name processes:"))
    #expect(result.stdout.contains("PID 4106: executable mapping unresolved"))
}

@Test("start returns already running for one canonical Helper without launching again")
func startDoesNotDuplicateCanonicalProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4201, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--start"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("already running: PID 4201"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("start fails when the canonical Helper is missing")
func startRejectsMissingCanonicalHelper() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--start"])

    #expect(result.status != 0)
    #expect(result.stderr.contains("canonical Helper is missing"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("start rejects a canonical Helper that fails strict signing verification")
func startRejectsInvalidCanonicalSigning() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--start"],
        environment: ["CODEX_CU_FAKE_STRICT_FAILURE_SCOPE": "all"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("canonical start bundle: codesign strict verification failed"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
}

@Test("start refuses duplicate canonical Helpers without launching another")
func startRejectsDuplicateCanonicalProcesses() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4202, mappings: [fixture.canonicalExecutable.path]),
        (pid: 4203, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--start"])

    #expect(result.status != 0)
    #expect(result.stderr.contains("duplicate canonical Helper instances: 4202 4203"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
}

@Test("start refuses a foreign same-name Helper without launching or killing it")
func startRejectsForeignProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([(pid: 4204, mappings: [foreign.path])])

    let result = try fixture.run(["--start"])

    #expect(result.status != 0)
    #expect(result.stderr.contains("foreign same-name Helper prevents canonical start"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4204"))
}

@Test("start refuses an unresolved same-name Helper")
func startRejectsUnresolvedProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setMalformedProcess(pid: 4205)

    let result = try fixture.run(["--start"])

    #expect(result.status != 0)
    #expect(result.stderr.contains("unresolved same-name Helper prevents canonical start"))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
}

@Test("start verifies the launched PID maps to the canonical executable")
func startRejectsLaunchThatMapsToForeignExecutable() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()

    let result = try fixture.run(
        ["--start"],
        environment: [
            "CODEX_CU_FAKE_NEXT_PID": "4206",
            "CODEX_CU_FAKE_OPEN_MAPPING": foreign.path
        ]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("launched Helper did not map to the canonical executable"))
    #expect(
        fixture.textIfPresent(at: fixture.openLog).contains(
            try fixture.physicalPath(of: fixture.canonicalApp)
        )
    )
}

@Test("start launches the canonical app and reports the verified PID")
func startLaunchesCanonicalApp() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--start"],
        environment: ["CODEX_CU_FAKE_NEXT_PID": "4207"]
    )

    #expect(result.status == 0)
    #expect(result.stdout.contains("started canonical Helper: PID 4207"))
    #expect(
        fixture.textIfPresent(at: fixture.openLog).contains(
            try fixture.physicalPath(of: fixture.canonicalApp)
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("stop returns already stopped when no canonical Helper is running")
func stopReturnsAlreadyStopped() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(["--stop"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("canonical Helper already stopped"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("stop sends TERM only to the exact canonical PID and confirms exit")
func stopTerminatesOneCanonicalProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4301, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--stop"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("sending TERM to canonical PID 4301"))
    #expect(result.stdout.contains("stopped canonical PID 4301"))
    #expect(fixture.textIfPresent(at: fixture.termLog) == "-TERM 4301\n")
    #expect(!fixture.textIfPresent(at: fixture.processState).contains("4301"))
}

@Test("stop never sends a signal to a foreign same-name PID")
func stopLeavesForeignProcessRunning() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([(pid: 4302, mappings: [foreign.path])])

    let result = try fixture.run(["--stop"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("canonical Helper already stopped"))
    #expect(result.stdout.contains("foreign same-name PID not signaled: 4302"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4302"))
}

@Test("stop terminates canonical PIDs while preserving a foreign same-name PID")
func stopSeparatesCanonicalAndForeignProcesses() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([
        (pid: 4303, mappings: [fixture.canonicalExecutable.path]),
        (pid: 4304, mappings: [foreign.path])
    ])

    let result = try fixture.run(["--stop"])

    #expect(result.status == 0)
    #expect(fixture.textIfPresent(at: fixture.termLog) == "-TERM 4303\n")
    #expect(!fixture.textIfPresent(at: fixture.processState).contains("4303"))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4304"))
}

@Test("stop terminates every confirmed duplicate canonical PID and no foreign PID")
func stopTerminatesDuplicateCanonicalProcesses() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([
        (pid: 4305, mappings: [fixture.canonicalExecutable.path]),
        (pid: 4306, mappings: [fixture.canonicalExecutable.path]),
        (pid: 4307, mappings: [foreign.path])
    ])

    let result = try fixture.run(["--stop"])
    let termLog = fixture.textIfPresent(at: fixture.termLog)

    #expect(result.status == 0)
    #expect(termLog.contains("-TERM 4305"))
    #expect(termLog.contains("-TERM 4306"))
    #expect(!termLog.contains("4307"))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4307"))
}

@Test("stop reports unresolved same-name PIDs without sending signals")
func stopLeavesUnresolvedProcessUntouched() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setMalformedProcess(pid: 4308)

    let result = try fixture.run(["--stop"])

    #expect(result.status == 0)
    #expect(result.stdout.contains("unresolved same-name PID not signaled: 4308"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("stop fails on TERM timeout without escalating to SIGKILL")
func stopReportsStubbornCanonicalProcess() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()
    try fixture.setProcesses([
        (pid: 4309, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(
        ["--stop"],
        environment: ["CODEX_CU_FAKE_STUBBORN_PIDS": "4309"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("stubborn canonical PID after TERM timeout: 4309"))
    #expect(fixture.textIfPresent(at: fixture.termLog) == "-TERM 4309\n")
    #expect(!fixture.textIfPresent(at: fixture.termLog).contains("KILL"))
    #expect(fixture.textIfPresent(at: fixture.processState).contains("4309"))
}

@Test(
    "legacy run verify and logs install one authoritative build and start canonical",
    arguments: ["run", "--verify", "--logs"]
)
func legacyModesInstallAndStartCanonical(mode: String) throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        [mode],
        environment: ["CODEX_CU_FAKE_NEXT_PID": "4401"]
    )
    let dittoLog = fixture.textIfPresent(at: fixture.dittoLog)
    let openLog = fixture.textIfPresent(at: fixture.openLog)

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
    #expect(openLog.contains(try fixture.expectedCanonicalAppPhysicalPath()))
    #expect(!openLog.contains(fixture.distApp.path))
    #expect(result.stdout.contains("started canonical Helper: PID 4401"))
}

@Test("debug starts the canonical app normally before attaching LLDB to its verified PID")
func debugAttachesToCanonicalProcess() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--debug"],
        environment: ["CODEX_CU_FAKE_NEXT_PID": "4402"]
    )

    #expect(result.status == 0)
    #expect(fixture.textIfPresent(at: fixture.buildCountLog) == "build\n")
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/.workflow-new-build").path
        )
    )
    #expect(
        fixture.textIfPresent(at: fixture.openLog).contains(
            try fixture.expectedCanonicalAppPhysicalPath()
        )
    )
    #expect(fixture.textIfPresent(at: fixture.lldbLog) == "-p 4402\n")
    #expect(!fixture.textIfPresent(at: fixture.lldbLog).contains(fixture.distApp.path))
}
