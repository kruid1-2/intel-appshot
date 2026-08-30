import ApplicationServices
import Foundation
import Testing
@testable import AppshotShimCore

@Test("Music window screenshot reports Screen Recording denial before capture")
func musicWindowScreenshotReportsScreenRecordingDenial() {
    let provider = MusicWindowScreenshotProvider(screenCaptureAccess: { false })
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
