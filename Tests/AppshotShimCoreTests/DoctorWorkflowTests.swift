import Foundation
import Testing

@Suite("Doctor workflow")
struct DoctorWorkflowTests {
    @Test("healthy stopped canonical reports healthy")
    func healthyStopped() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Expected architecture: x86_64"))
        #expect(result.stdout.contains("Expected Bundle ID: com.openai.sky.CUAService"))
        #expect(result.stdout.contains("Runtime: stopped"))
        #expect(result.stdout.contains("Accessibility: granted"))
        #expect(result.stdout.contains("Screen Recording: granted"))
        #expect(result.stdout.hasSuffix("Overall: healthy\n"))
    }

    @Test("healthy current canonical reports healthy")
    func healthyCurrent() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.setProcesses([
            (pid: 4101, mappings: [fixture.canonicalExecutable.path])
        ])

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Runtime: current"))
        #expect(result.stdout.hasSuffix("Overall: healthy\n"))
    }

    @Test("missing canonical is attention required and permissions unavailable")
    func canonicalMissing() throws {
        let fixture = try IsolatedWorkflowFixture()

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Installed Helper: missing"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
        #expect(result.stdout.contains("Screen Recording: unavailable"))
    }

    @Test("wrong canonical architecture is attention required")
    func wrongArchitecture() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_ARCHS": "arm64"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Architecture: arm64"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
    }

    @Test("invalid canonical signature is attention required")
    func invalidSignature() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_STRICT_FAILURE_SCOPE": "all"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Strict codesign: invalid"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
    }

    @Test("wrong canonical Bundle ID is attention required")
    func wrongBundleID() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_BUNDLE_ID": "example.wrong.bundle"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Bundle ID: example.wrong.bundle"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
    }

    @Test("wrong canonical signing authority is attention required")
    func wrongAuthority() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_AUTHORITY": "Wrong Authority"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Authority: Wrong Authority"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
    }

    @Test("wrong canonical designated requirement is attention required")
    func wrongDesignatedRequirement() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: [
                "CODEX_CU_FAKE_DESIGNATED_REQUIREMENT": "designated => identifier example.wrong"
            ]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Designated Requirement: designated => identifier example.wrong"))
        #expect(result.stdout.contains("Accessibility: unavailable"))
    }

    @Test("invalid installed BuildIdentity is attention required")
    func invalidBuildIdentity() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.installBuildIdentity(
            in: fixture.canonicalApp,
            buildID: "not-a-uuid",
            gitHEAD: "0123456789abcdef0123456789abcdef01234567",
            gitDirty: false
        )

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Build Identity: identity-invalid"))
        #expect(result.stdout.contains("Accessibility: granted"))
        #expect(result.stdout.contains("Screen Recording: granted"))
    }

    @Test("Accessibility denied is attention required after full diagnostics")
    func accessibilityDenied() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "denied"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Accessibility: denied"))
        #expect(result.stdout.contains("Screen Recording: granted"))
        let screenResult = result.stdout.range(of: "Screen Recording: granted")
        let overallResult = result.stdout.range(of: "Overall: attention required")
        #expect(screenResult != nil)
        #expect(overallResult != nil)
        if let screenResult, let overallResult {
            #expect(screenResult.lowerBound < overallResult.lowerBound)
        }
    }

    @Test("Screen Recording denied is attention required after full diagnostics")
    func screenRecordingDenied() throws {
        let fixture = try prepareDoctorFixture()

        let result = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_PERMISSION_SCREEN_RECORDING": "denied"]
        )

        assertAttention(result)
        #expect(result.stdout.contains("Accessibility: granted"))
        #expect(result.stdout.contains("Screen Recording: denied"))
    }

    @Test("stale canonical-path process is attention required")
    func staleRuntime() throws {
        let fixture = try prepareDoctorFixture()
        let installed = try fixture.fileIdentity(of: fixture.canonicalExecutable)
        try fixture.setProcess(
            pid: 4201,
            mapping: fixture.canonicalExecutable.path,
            device: installed.device,
            inode: installed.inode + 1
        )

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Runtime: stale"))
        #expect(result.stdout.contains("Accessibility: granted"))
    }

    @Test("duplicate current canonical processes are attention required")
    func duplicateRuntime() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.setProcesses([
            (pid: 4301, mappings: [fixture.canonicalExecutable.path]),
            (pid: 4302, mappings: [fixture.canonicalExecutable.path])
        ])

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Runtime: duplicate"))
        #expect(result.stdout.contains("Accessibility: granted"))
    }

    @Test("unresolved process mapping is attention required")
    func unresolvedRuntime() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.setMalformedProcess(pid: 4401)

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Runtime: unresolved"))
        #expect(result.stdout.contains("Accessibility: granted"))
    }

    @Test("foreign same-name process is attention required")
    func foreignRuntime() throws {
        let fixture = try prepareDoctorFixture()
        let foreignExecutable = try fixture.installForeignExecutable()
        try fixture.setProcesses([(pid: 4501, mappings: [foreignExecutable.path])])

        let result = try fixture.run(["--doctor"])

        assertAttention(result)
        #expect(result.stdout.contains("Runtime: foreign"))
        #expect(result.stdout.contains("Accessibility: granted"))
    }

    @Test("missing non-authoritative dist does not pollute Overall")
    func distMissing() throws {
        let fixture = try prepareDoctorFixture()
        try FileManager.default.removeItem(at: fixture.distApp)

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Dist copy: missing (non-authoritative)"))
        #expect(result.stdout.hasSuffix("Overall: healthy\n"))
    }

    @Test("FinderInfo strict warning on non-authoritative dist does not pollute Overall")
    func distFinderInfoWarning() throws {
        let fixture = try prepareDoctorFixture()
        try Data().write(to: fixture.distApp.appendingPathComponent(".dist-polluted"))

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Strict codesign: invalid"))
        #expect(result.stdout.contains("FinderInfo/xattr: warning: com.apple.FinderInfo"))
        #expect(result.stdout.hasSuffix("Overall: healthy\n"))
    }

    @Test("non-authoritative dist Build ID mismatch does not pollute Overall")
    func distBuildIDMismatch() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.installBuildIdentity(
            in: fixture.distApp,
            buildID: "11111111-2222-4333-8444-555555555555",
            gitHEAD: "0123456789abcdef0123456789abcdef01234567",
            gitDirty: false
        )

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Same workflow build: no"))
        #expect(result.stdout.hasSuffix("Overall: healthy\n"))
    }

    @Test("doctor does not build")
    func doesNotBuild() throws {
        let fixture = try prepareDoctorFixture()

        _ = try fixture.run(["--doctor"])

        #expect(fixture.textIfPresent(at: fixture.buildCountLog).isEmpty)
        #expect(fixture.textIfPresent(at: fixture.uuidLog).isEmpty)
        #expect(fixture.textIfPresent(at: fixture.gitLog).isEmpty)
    }

    @Test("doctor does not install")
    func doesNotInstall() throws {
        let fixture = try prepareDoctorFixture()

        _ = try fixture.run(["--doctor"])

        #expect(fixture.textIfPresent(at: fixture.dittoLog).isEmpty)
    }

    @Test("doctor does not stop an existing managed Helper")
    func doesNotStopManagedHelper() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.setProcesses([
            (pid: 4601, mappings: [fixture.canonicalExecutable.path])
        ])
        let before = fixture.textIfPresent(at: fixture.processState)

        _ = try fixture.run(["--doctor"])

        #expect(fixture.textIfPresent(at: fixture.termLog).isEmpty)
        #expect(fixture.textIfPresent(at: fixture.processState) == before)
    }

    @Test("doctor launches only the transient permission diagnostic")
    func doesNotStartLongLivedHelper() throws {
        let fixture = try prepareDoctorFixture()

        _ = try fixture.run(["--doctor"])

        let openLog = fixture.textIfPresent(at: fixture.openLog)
        #expect(openLog.contains("--permission-status"))
        #expect(fixture.textIfPresent(at: fixture.processState).isEmpty)
    }

    @Test("permission diagnostic restores the pre-existing PID set")
    func permissionPIDSetRestored() throws {
        let fixture = try prepareDoctorFixture()
        try fixture.setProcesses([
            (pid: 4701, mappings: [fixture.canonicalExecutable.path])
        ])
        let before = fixture.textIfPresent(at: fixture.processState)

        let result = try fixture.run(["--doctor"])

        #expect(result.status == 0)
        #expect(fixture.textIfPresent(at: fixture.processState) == before)
        #expect(fixture.textIfPresent(at: fixture.termLog).isEmpty)
    }

    @Test("Overall is the final line and controls the exit status")
    func overallIsFinalAndControlsExitStatus() throws {
        let fixture = try prepareDoctorFixture()

        let healthy = try fixture.run(["--doctor"])
        let attention = try fixture.run(
            ["--doctor"],
            environment: ["CODEX_CU_FAKE_PERMISSION_ACCESSIBILITY": "denied"]
        )

        #expect(healthy.status == 0)
        #expect(healthy.stdout.hasSuffix("Overall: healthy\n"))
        #expect(attention.status != 0)
        #expect(attention.stdout.hasSuffix("Overall: attention required\n"))
    }
}

private func prepareDoctorFixture() throws -> IsolatedWorkflowFixture {
    let fixture = try IsolatedWorkflowFixture()
    let install = try fixture.run(["--install"])
    guard install.status == 0 else {
        throw DoctorFixtureError.installFailed(install.stderr)
    }

    for log in [
        fixture.buildCountLog,
        fixture.dittoLog,
        fixture.termLog,
        fixture.openLog,
        fixture.xattrLog,
        fixture.uuidLog,
        fixture.gitLog,
    ] {
        try? FileManager.default.removeItem(at: log)
    }

    return fixture
}

private func assertAttention(
    _ result: (status: Int32, stdout: String, stderr: String)
) {
    #expect(result.status != 0)
    #expect(result.stdout.hasSuffix("Overall: attention required\n"))
}

private enum DoctorFixtureError: Error {
    case installFailed(String)
}
