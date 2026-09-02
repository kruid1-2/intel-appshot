import Foundation
import Testing

@Test("authoritative build writes one valid BuildIdentity using Git's own status semantics")
func authoritativeBuildWritesValidBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: [
            "CODEX_CU_FAKE_GIT_STATUS": " M script/build_and_run.sh\n?? Sources/NewFile.swift"
        ]
    )
    let identity = try fixture.buildIdentity(in: fixture.distApp)
    let buildID = identity["buildID"] as? String

    #expect(result.status == 0, "\(result.stderr)")
    #expect(buildID.flatMap(UUID.init(uuidString:)) != nil)
    #expect(identity["gitHEAD"] as? String == "0123456789abcdef0123456789abcdef01234567")
    #expect(identity["gitDirty"] as? Bool == true)
    #expect(identity["architecture"] as? String == "x86_64")
    #expect(identity["bundleIdentifier"] as? String == "com.openai.sky.CUAService")
    #expect(fixture.textIfPresent(at: fixture.uuidLog).split(separator: "\n").count == 1)
    #expect(
        fixture.textIfPresent(at: fixture.gitLog).contains(
            "status --porcelain --untracked-files=normal"
        )
    )
}

@Test("ignored build products do not make gitDirty true when Git reports a clean worktree")
func buildIdentityUsesGitIgnoredSemantics() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--build"])
    let identity = try fixture.buildIdentity(in: fixture.distApp)

    #expect(result.status == 0, "\(result.stderr)")
    #expect(identity["gitDirty"] as? Bool == false)
    #expect(
        fixture.textIfPresent(at: fixture.gitLog).contains(
            "status --porcelain --untracked-files=normal"
        )
    )
}

@Test("build plus install generates one Build ID shared by dist and canonical")
func buildInstallSharesOneBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--build", "--install"])
    let distIdentity = try fixture.buildIdentity(in: fixture.distApp)
    let canonicalIdentity = try fixture.buildIdentity(in: fixture.canonicalApp)

    #expect(result.status == 0, "\(result.stderr)")
    #expect(distIdentity["buildID"] as? String == canonicalIdentity["buildID"] as? String)
    #expect(fixture.textIfPresent(at: fixture.uuidLog).split(separator: "\n").count == 1)
    #expect(fixture.textIfPresent(at: fixture.buildCountLog) == "build\n")
}

@Test("install workflow generates one Build ID and never regenerates it while copying")
func installDoesNotRegenerateBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(["--install"])
    let canonicalIdentity = try fixture.buildIdentity(in: fixture.canonicalApp)

    #expect(result.status == 0, "\(result.stderr)")
    #expect(
        canonicalIdentity["buildID"] as? String
            == "11111111-1111-4111-8111-111111111111"
    )
    #expect(fixture.textIfPresent(at: fixture.uuidLog).split(separator: "\n").count == 1)
}

@Test("a separate authoritative build receives a different Build ID")
func separateBuildReceivesDifferentBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()

    let first = try fixture.run(["--build"])
    let firstID = try fixture.buildIdentity(in: fixture.distApp)["buildID"] as? String
    let second = try fixture.run(["--build"])
    let secondID = try fixture.buildIdentity(in: fixture.distApp)["buildID"] as? String

    #expect(first.status == 0, "\(first.stderr)")
    #expect(second.status == 0, "\(second.stderr)")
    #expect(firstID != nil)
    #expect(secondID != nil)
    #expect(firstID != secondID)
    #expect(fixture.textIfPresent(at: fixture.uuidLog).split(separator: "\n").count == 2)
}

@Test("a malformed generated Build ID fails before publishing dist")
func malformedGeneratedBuildIdentityFails() throws {
    let fixture = try IsolatedWorkflowFixture()

    let result = try fixture.run(
        ["--build"],
        environment: ["CODEX_CU_FAKE_MALFORMED_BUILD_ID": "1"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("invalid buildID"))
    #expect(!FileManager.default.fileExists(atPath: fixture.distApp.path))
}

@Test("canonical Build ID mismatch fails final verification and restores legacy-valid backup")
func canonicalBuildIdentityMismatchRestoresLegacyBackup() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical(includeBuildIdentity: false)

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_FINAL_BUILD_ID_MISMATCH": "1"]
    )

    #expect(result.status != 0)
    #expect(result.stderr.contains("canonical final bundle: Build ID mismatch"))
    #expect(result.stderr.contains("Build Identity: legacy / missing"))
    #expect(result.stderr.contains("rollback restored and verified previous canonical"))
    #expect(
        FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/old-install-marker").path
        )
    )
    #expect(
        !FileManager.default.fileExists(
            atPath: fixture.canonicalApp
                .appendingPathComponent("Contents/Resources/BuildIdentity.plist").path
        )
    )
}

@Test("rollback preserves an identity-valid backup's original Build ID")
func rollbackPreservesPreviousBuildIdentity() throws {
    let fixture = try IsolatedWorkflowFixture()
    let previousID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    try fixture.installExistingCanonical(buildID: previousID)

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_FINAL_BUILD_ID_MISMATCH": "1"]
    )
    let restored = try fixture.buildIdentity(in: fixture.canonicalApp)

    #expect(result.status != 0)
    #expect(result.stderr.contains("Build Identity: identity-valid"))
    #expect(restored["buildID"] as? String == previousID)
}

@Test("rollback preserves and reports an identity-invalid backup without rewriting it")
func rollbackPreservesIdentityInvalidBackup() throws {
    let fixture = try IsolatedWorkflowFixture()
    try fixture.installExistingCanonical(buildID: "not-a-uuid")

    let result = try fixture.run(
        ["--install"],
        environment: ["CODEX_CU_FAKE_FINAL_BUILD_ID_MISMATCH": "1"]
    )
    let restored = try fixture.buildIdentity(in: fixture.canonicalApp)

    #expect(result.status != 0)
    #expect(result.stderr.contains("Build Identity: identity-invalid"))
    #expect(
        result.stderr.contains(
            "Bundle identity classification: identity-invalid"
        )
    )
    #expect(restored["buildID"] as? String == "not-a-uuid")
}
