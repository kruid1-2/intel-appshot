import ApplicationServices
import Foundation
import Testing
@testable import AppshotShimCore

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
