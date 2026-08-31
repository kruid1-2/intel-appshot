import Foundation
import Testing

@Test("build script rejects a missing configured signing identity")
func buildScriptRejectsMissingSigningIdentity() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = repositoryRoot.appendingPathComponent("script/build_and_run.sh")
    let missingIdentity = "Codex Computer Use Missing Test Identity"
    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("build-signing-workflow-\(UUID().uuidString)")
    let toolDirectory = fixtureRoot.appendingPathComponent("tools")
    let buildDirectory = fixtureRoot.appendingPathComponent("build")
    try FileManager.default.createDirectory(
        at: toolDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: buildDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }

    let fakeSwift = toolDirectory.appendingPathComponent("swift")
    try Data(
        #"""
#!/bin/bash
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$FAKE_SWIFT_BIN_PATH"
fi
"""#.utf8
    ).write(to: fakeSwift)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSwift.path)

    let fakeCodesign = toolDirectory.appendingPathComponent("codesign")
    try Data("#!/bin/bash\nexit 0\n".utf8).write(to: fakeCodesign)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: fakeCodesign.path
    )

    let fakeBuildBinary = buildDirectory.appendingPathComponent("SkyComputerUseService")
    try Data("fixture executable\n".utf8).write(to: fakeBuildBinary)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: fakeBuildBinary.path
    )

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [scriptURL.path, "--build"]

    var environment = ProcessInfo.processInfo.environment
    environment["CODEX_COMPUTER_USE_SIGNING_IDENTITY"] = missingIdentity
    environment["FAKE_SWIFT_BIN_PATH"] = buildDirectory.path
    environment["PATH"] = "\(toolDirectory.path):\(environment["PATH"] ?? "/usr/bin:/bin")"
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
    #expect(diagnostic.contains("signing identity not found: \(missingIdentity)"))
}
