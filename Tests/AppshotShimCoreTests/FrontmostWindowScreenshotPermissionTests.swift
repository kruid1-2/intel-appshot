import ApplicationServices
import Foundation
import ScreenCaptureKit
import Testing
@testable import AppshotShimCore

@Test("window body capture excludes shadow padding without changing its pixel scale")
@available(macOS 14.0, *)
func windowBodyCaptureHasNoShadowInsets() {
    let configuration = FrontmostWindowScreenshotProvider.windowBodyConfiguration(
        contentRect: CGRect(x: 274, y: 99, width: 1_238, height: 600),
        pointPixelScale: 2
    )

    #expect(configuration.ignoreShadowsSingleWindow)
    #expect(configuration.width == 2_476)
    #expect(configuration.height == 1_200)
    #expect(!configuration.showsCursor)
}

@Test("window body capture rounds fractional pixel extents outwards")
@available(macOS 14.0, *)
func windowBodyCaptureKeepsFractionalEdgePixels() {
    let configuration = FrontmostWindowScreenshotProvider.windowBodyConfiguration(
        contentRect: CGRect(x: -100, y: 30, width: 400.25, height: 300.25),
        pointPixelScale: 2
    )

    #expect(configuration.width == 801)
    #expect(configuration.height == 601)
    #expect(configuration.ignoreShadowsSingleWindow)
}

@Test("frontmost window screenshot reports Screen Recording denial before capture")
func frontmostWindowScreenshotReportsScreenRecordingDenial() {
    let provider = FrontmostWindowScreenshotProvider(screenCaptureAccess: { false })
    let window = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

    do {
        _ = try provider.capture(
            accessibilityWindow: window,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            destination: FileManager.default.temporaryDirectory
                .appendingPathComponent("must-not-be-written.png")
        )
        Issue.record("capture unexpectedly succeeded without Screen Recording permission")
    } catch {
        #expect(
            String(describing: error)
                == "Screen Recording permission is not granted to Codex Computer Use"
        )
    }
}

@Test("in-memory window capture reports Screen Recording denial before capture")
func inMemoryWindowCaptureReportsScreenRecordingDenial() {
    let provider = FrontmostWindowScreenshotProvider(screenCaptureAccess: { false })
    let window = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

    do {
        _ = try provider.captureImage(
            accessibilityWindow: window,
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        Issue.record("capture unexpectedly succeeded without Screen Recording permission")
    } catch {
        #expect(
            String(describing: error)
                == "Screen Recording permission is not granted to Codex Computer Use"
        )
    }
}
