import Foundation
import Testing
@testable import AppshotShimCore

@MainActor
@Test("probe screenshot writer creates a non-empty PNG")
func probeScreenshotWriterCreatesPNG() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.openai.sky.CUAService", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let destination = directory.appendingPathComponent("probe.png")
    defer { try? FileManager.default.removeItem(at: directory) }

    try ProbeScreenshotWriter.write(to: destination)

    let data = try Data(contentsOf: destination)
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    #expect(data.count > 1_000)
}
