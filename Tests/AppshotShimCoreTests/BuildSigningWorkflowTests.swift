import Foundation
import Testing

@Test("build script rejects a configured identity that would change the stable TCC identity")
func buildScriptRejectsConfiguredSigningIdentityMismatch() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = repositoryRoot.appendingPathComponent("script/build_and_run.sh")
    let unexpectedIdentity = "Another Local Development Identity"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptURL.path, "--build"]

    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_COMPUTER_USE_SIGNING_IDENTITY"] = unexpectedIdentity
    environment["CLANG_MODULE_CACHE_PATH"] = "/private/tmp/intel-appshot-clang-cache"
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = "/private/tmp/intel-appshot-clang-cache"
    environment["SWIFTPM_CUSTOM_CACHE_PATH"] = "/private/tmp/intel-appshot-swiftpm-cache"
    process.environment = environment

    let standardError = Pipe()
    process.standardOutput = Pipe()
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let diagnostic = String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    #expect(process.terminationStatus != 0)
    #expect(
        diagnostic.contains(
            "configured signing identity mismatch: expected Codex Computer Use Local Development, got \(unexpectedIdentity)"
        )
    )
}

@Test("build script rejects test-only workflow injection during normal execution")
func buildScriptRejectsTestInjectionWithoutExplicitTestMode() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = repositoryRoot.appendingPathComponent("script/build_and_run.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptURL.path, "--build"]

    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_CU_TEST_ROOT"] = "/private/tmp/codex-cu-workflow-tests.untrusted"
    environment["CODEX_COMPUTER_USE_SIGNING_IDENTITY"] = "Untrusted Test Identity"
    process.environment = environment

    let standardError = Pipe()
    process.standardOutput = Pipe()
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let diagnostic = String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    #expect(process.terminationStatus != 0)
    #expect(
        diagnostic.contains(
            "test-only workflow injection is disabled during normal execution"
        )
    )
}

@Test("test-only workflow mode requires a validated temporary fixture root")
func buildScriptRejectsTestModeWithoutValidatedFixtureRoot() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = repositoryRoot.appendingPathComponent("script/build_and_run.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptURL.path, "--workflow-test-mode", "--build"]

    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_CU_WORKFLOW_TESTING"] = "1"
    environment["CODEX_CU_TEST_ROOT"] = "/private/tmp/not-a-codex-cu-workflow-fixture"
    environment["CODEX_COMPUTER_USE_SIGNING_IDENTITY"] = "Untrusted Test Identity"
    process.environment = environment

    let standardError = Pipe()
    process.standardOutput = Pipe()
    process.standardError = standardError

    try process.run()
    process.waitUntilExit()

    let diagnostic = String(
        decoding: standardError.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    #expect(process.terminationStatus != 0)
    #expect(
        diagnostic.contains(
            "test workflow root is invalid or missing its sentinel"
        )
    )
}
