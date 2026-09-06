import Foundation
import Testing

@Test("production Appshot startup uses in-memory capture with deferred AX and PNG work")
func productionAppshotStartupUsesDeferredPreparation() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent(
            "Sources/SkyComputerUseService/main.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("accessibilityProvider.locateWindow("))
    #expect(source.contains("AppshotBackgroundWork<FrontmostAccessibilitySnapshot>"))
    #expect(source.contains("AppshotBackgroundWork<CGImage>"))
    #expect(source.contains("screenshotProvider.captureImage("))
    #expect(source.contains("AppshotBackgroundWork<FrontmostWindowScreenshot>"))
    #expect(source.contains("screenshotImage: imageCapture.image"))
    #expect(source.contains("applicationIconImage: applicationIconImage"))
}
