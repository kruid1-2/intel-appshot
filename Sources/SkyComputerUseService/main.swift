import AppKit
import AppshotShimCore
import Darwin
import Foundation

func probeLog(_ message: String) {
    let data = Data("\(message)\n".utf8)
    data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        _ = Darwin.write(STDERR_FILENO, baseAddress, bytes.count)
    }
}

final class LoggingAppleEventBridge: NSObject {
    let bridge: AppshotAppleEventBridge

    init(bridge: AppshotAppleEventBridge) {
        self.bridge = bridge
    }

    @objc func handleAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        probeLog("received Appshots Apple Event")
        bridge.handleAppleEvent(event, withReplyEvent: replyEvent)
        probeLog("replied to Appshots Apple Event")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let captureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("com.openai.sky.CUAService", isDirectory: true)
let screenshotURL = captureDirectory.appendingPathComponent("frontmost-window.png")

let accessibilityProvider = FrontmostAccessibilitySnapshotProvider()
let screenshotProvider = FrontmostWindowScreenshotProvider()
let protocolProbe = AppshotProtocolProbe { requestedBundleIdentifier in
    let snapshot = try accessibilityProvider.capture(
        requestedBundleIdentifier: requestedBundleIdentifier
    )
    probeLog(
        "captured frontmost AX app=\(snapshot.applicationName) "
            + "bundle=\(snapshot.bundleIdentifier) pid=\(snapshot.processIdentifier) "
            + "window=\(snapshot.windowTitle) nodes=\(snapshot.nodeCount) "
            + "truncated=\(snapshot.wasTruncated) "
            + "durationMs=\(snapshot.durationMilliseconds)"
    )
    let screenshot = try screenshotProvider.capture(
        accessibilityWindow: snapshot.windowElement,
        processIdentifier: snapshot.processIdentifier,
        destination: screenshotURL
    )
    probeLog(
        "captured frontmost window screenshot app=\(snapshot.applicationName) "
            + "bundle=\(snapshot.bundleIdentifier) pid=\(snapshot.processIdentifier) "
            + "windowID=\(screenshot.windowID) mapping=\(screenshot.mappingMethod) "
            + "mappingMs=\(screenshot.mappingDurationMilliseconds) "
            + "shareableContentMs=\(screenshot.shareableContentDurationMilliseconds) "
            + "imageMs=\(screenshot.imageCaptureDurationMilliseconds) "
            + "totalMs=\(screenshot.totalDurationMilliseconds)"
    )
    return AppshotCapturePayload(
        screenshotURL: screenshot.screenshotURL,
        accessibilityText: snapshot.accessibilityText
    )
}
let appleEventBridge = AppshotAppleEventBridge(protocolProbe: protocolProbe)
let loggingBridge = LoggingAppleEventBridge(bridge: appleEventBridge)

NSAppleEventManager.shared().setEventHandler(
    loggingBridge,
    andSelector: #selector(
        LoggingAppleEventBridge.handleAppleEvent(_:withReplyEvent:)
    ),
    forEventClass: AppshotAppleEventBridge.eventClass,
    andEventID: AppshotAppleEventBridge.eventID
)

probeLog("SkyComputerUseService probe ready pid=\(ProcessInfo.processInfo.processIdentifier)")
app.run()
