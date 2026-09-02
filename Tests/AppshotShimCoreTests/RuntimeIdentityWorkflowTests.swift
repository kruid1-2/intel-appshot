import Foundation
import Testing

private func prepareIdentityFixture() throws -> IsolatedWorkflowFixture {
    let fixture = try IsolatedWorkflowFixture()
    let result = try fixture.run(["--install"])
    #expect(result.status == 0, "\(result.stderr)")
    for log in [
        fixture.buildCountLog,
        fixture.dittoLog,
        fixture.openLog,
        fixture.termLog,
        fixture.xattrLog
    ] {
        try? FileManager.default.removeItem(at: log)
    }
    return fixture
}

@Test("identity reports a valid installed bundle and stopped runtime without mutation")
func identityReportsStoppedReadOnly() throws {
    let fixture = try prepareIdentityFixture()

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Installed Helper: installed"))
    #expect(result.stdout.contains("Build Identity: identity-valid"))
    #expect(result.stdout.contains("Bundle identity classification: identity-valid"))
    #expect(result.stdout.contains("Build ID: 11111111-1111-4111-8111-111111111111"))
    #expect(result.stdout.contains("Architecture: x86_64"))
    #expect(result.stdout.contains("Bundle ID: com.openai.sky.CUAService"))
    #expect(result.stdout.contains("Executable SHA-256:"))
    #expect(result.stdout.contains("CDHash:"))
    #expect(result.stdout.contains("Authority: Codex Computer Use Local Development"))
    #expect(result.stdout.contains("Strict codesign: valid"))
    #expect(result.stdout.contains("Dist copy: present (non-authoritative)"))
    #expect(result.stdout.contains("Same workflow build: yes"))
    #expect(result.stdout.contains("Running Helper: stopped"))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(
        fixture.textIfPresent(at: fixture.xattrLog)
            .split(separator: "\n")
            .allSatisfy { !$0.hasPrefix("-c ") && $0 != "-c" }
    )
}

@Test("identity reports a missing canonical without building or installing")
func identityReportsMissingCanonicalReadOnly() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--identity"])

    #expect(result.status != 0)
    #expect(result.stdout.contains("Installed Helper: missing"))
    #expect(result.stdout.contains("Running Helper: stopped"))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.dittoLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("identity reports current when canonical txt vnode matches the installed executable")
func identityReportsCurrentRuntime() throws {
    let fixture = try prepareIdentityFixture()
    try fixture.setProcesses([
        (pid: 6101, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--identity"])
    let fileIdentity = try fixture.fileIdentity(of: fixture.canonicalExecutable)

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: current"))
    #expect(result.stdout.contains("PID: 6101"))
    #expect(
        result.stdout.contains(
            "Installed device/inode: \(fileIdentity.device)/\(fileIdentity.inode)"
        )
    )
    #expect(result.stdout.contains("Running matches installed: yes"))
}

@Test("identity finds the exact canonical txt mapping among multiple candidates")
func identityFindsCanonicalAmongMultipleMappings() throws {
    let fixture = try prepareIdentityFixture()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([
        (
            pid: 6107,
            mappings: [foreign.path, fixture.canonicalExecutable.path]
        )
    ])

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: current"))
    #expect(result.stdout.contains("PID: 6107"))
    #expect(result.stdout.contains("Running matches installed: yes"))
}

@Test("identity keeps complete canonical vnode proof when an auxiliary txt mapping disappears")
func identityKeepsCanonicalProofWithVanishedAuxiliaryMapping() throws {
    let fixture = try prepareIdentityFixture()
    let vanished = fixture.root.appendingPathComponent("vanished-runtime-cache.plist")
    let installed = try fixture.fileIdentity(of: fixture.canonicalExecutable)
    let row = "6108\t\(fixture.canonicalExecutable.path)^\(installed.device)^\(installed.inode)"
        + "|\(vanished.path)^\(installed.device)^99999999\n"
    try Data(row.utf8).write(to: fixture.processState)

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: current"))
    #expect(result.stdout.contains("PID: 6108"))
    #expect(result.stdout.contains("Running matches installed: yes"))
    #expect(result.stdout.contains("Unresolved same-name processes: none"))
}

@Test("identity reports stale for the canonical path mapped to a different vnode")
func identityReportsStaleRuntime() throws {
    let fixture = try prepareIdentityFixture()
    let installed = try fixture.fileIdentity(of: fixture.canonicalExecutable)
    try fixture.setProcess(
        pid: 6102,
        mapping: fixture.canonicalExecutable.path,
        device: installed.device,
        inode: installed.inode + 1
    )

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: stale"))
    #expect(result.stdout.contains("Running matches installed: no"))
    #expect(
        result.stdout.contains(
            "running canonical path but executable vnode differs from current installation"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("identity conservatively reports foreign same-name runtime")
func identityReportsForeignRuntime() throws {
    let fixture = try prepareIdentityFixture()
    let foreign = try fixture.installForeignExecutable()
    try fixture.setProcesses([(pid: 6103, mappings: [foreign.path])])

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: foreign"))
    #expect(result.stdout.contains("PID 6103:"))
    #expect(result.stdout.contains(try fixture.physicalPath(of: foreign)))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("identity reports duplicate canonical runtimes explicitly")
func identityReportsDuplicateRuntime() throws {
    let fixture = try prepareIdentityFixture()
    try fixture.setProcesses([
        (pid: 6104, mappings: [fixture.canonicalExecutable.path]),
        (pid: 6105, mappings: [fixture.canonicalExecutable.path])
    ])

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Running Helper: duplicate"))
    #expect(result.stdout.contains("Canonical PIDs: 6104 6105"))
}

@Test("identity reports missing vnode fields as unresolved")
func identityReportsUnresolvedRuntime() throws {
    let fixture = try prepareIdentityFixture()
    try fixture.setProcess(
        pid: 6106,
        mapping: fixture.canonicalExecutable.path,
        device: 0,
        inode: 0
    )
    try Data("6106\t\(fixture.canonicalExecutable.path)^__MISSING__^__MISSING__\n".utf8)
        .write(to: fixture.processState)

    let result = try fixture.run(["--identity"])

    #expect(result.status != 0)
    #expect(result.stdout.contains("Running Helper: unresolved"))
    #expect(result.stdout.contains("PID 6106: executable vnode unresolved"))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
}

@Test("identity labels a valid pre-stage-E canonical bundle as legacy missing identity")
func identityReportsLegacyValidBundle() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical(includeBuildIdentity: false)

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Build Identity: legacy / missing"))
    #expect(result.stdout.contains("Bundle identity classification: legacy-valid"))
    #expect(result.stdout.contains("Strict codesign: valid"))
    #expect(result.stdout.contains("Running Helper: stopped"))
}

@Test("identity reports installed signature failure without mutating lifecycle state")
func identityRejectsInvalidInstalledSignatureReadOnly() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical()

    let result = try fixture.run(
        ["--identity"],
        environment: ["CODEX_CU_FAKE_STRICT_FAILURE_SCOPE": "all"]
    )

    #expect(result.status != 0)
    #expect(result.stdout.contains("Strict codesign: invalid"))
    #expect(
        result.stdout.contains(
            "Bundle identity classification: identity-invalid"
        )
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.openLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.termLog.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.buildCountLog.path))
}

@Test("identity rejects a present but malformed BuildIdentity")
func identityRejectsInvalidBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical(buildID: "not-a-uuid")

    let result = try fixture.run(["--identity"])

    #expect(result.status != 0)
    #expect(result.stdout.contains("Build Identity: identity-invalid"))
    #expect(result.stderr.contains("invalid buildID"))
}

@Test("different executable SHA values do not override equal Build IDs")
func identityUsesBuildIDInsteadOfExecutableSHAForWorkflowEquality() throws {
    let fixture = try prepareIdentityFixture()

    let result = try fixture.run(
        ["--identity"],
        environment: [
            "CODEX_CU_FAKE_CANONICAL_SHA256": String(repeating: "a", count: 64),
            "CODEX_CU_FAKE_DIST_SHA256": String(repeating: "b", count: 64)
        ]
    )

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Same workflow build: yes"))
    #expect(result.stdout.contains(String(repeating: "a", count: 64)))
    #expect(result.stdout.contains(String(repeating: "b", count: 64)))
}

@Test("identity reports a non-authoritative dist Build ID mismatch without repairing it")
func identityReportsDistBuildIdentityMismatchReadOnly() throws {
    let fixture = try prepareIdentityFixture()
    try fixture.installBuildIdentity(
        in: fixture.distApp,
        buildID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    )
    let before = try Data(
        contentsOf: fixture.distApp.appendingPathComponent(
            "Contents/Resources/BuildIdentity.plist"
        )
    )

    let result = try fixture.run(["--identity"])
    let after = try Data(
        contentsOf: fixture.distApp.appendingPathComponent(
            "Contents/Resources/BuildIdentity.plist"
        )
    )

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Same workflow build: no"))
    #expect(before == after)
}

@Test("identity treats dist FinderInfo and strict failure as non-authoritative warnings")
func identityReportsDistMetadataWarningWithoutFailingCanonical() throws {
    let fixture = try prepareIdentityFixture()
    try Data().write(to: fixture.distApp.appendingPathComponent(".dist-polluted"))

    let result = try fixture.run(["--identity"])

    #expect(result.status == 0, "\(result.stderr)")
    #expect(result.stdout.contains("Dist copy: present (non-authoritative)"))
    #expect(result.stdout.contains("FinderInfo/xattr: warning: com.apple.FinderInfo"))
    #expect(result.stdout.contains("Same workflow build: yes"))
    #expect(result.stderr.contains("dist remains non-authoritative"))
    #expect(FileManager.default.fileExists(atPath: fixture.distApp.appendingPathComponent(".dist-polluted").path))
}
