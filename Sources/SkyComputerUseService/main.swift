import AppKit
import AppshotShimCore
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import UniformTypeIdentifiers

private enum PermissionDiagnosticFailure: Error {
    case bundleIdentifierUnavailable
    case executablePathUnavailable
    case outputWriteFailed
}

@discardableResult
func writePermissionDiagnostic(_ message: String, to descriptor: Int32) -> Bool {
    let data = Data(message.utf8)
    return data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return data.isEmpty }
        var offset = 0
        while offset < bytes.count {
            let written = Darwin.write(
                descriptor,
                baseAddress.advanced(by: offset),
                bytes.count - offset
            )
            if written < 0 {
                if errno == EINTR {
                    continue
                }
                return false
            }
            if written == 0 {
                return false
            }
            offset += written
        }
        return true
    }
}

if PermissionStatusDiagnostic.isRequested(arguments: CommandLine.arguments) {
    do {
        let accessibilityQuery: () throws -> Bool = {
            AXIsProcessTrusted()
        }
        let screenRecordingQuery: () throws -> Bool = {
            CGPreflightScreenCaptureAccess()
        }
        let status = try PermissionStatusDiagnostic.evaluate(
            accessibilityQuery: accessibilityQuery,
            screenRecordingQuery: screenRecordingQuery
        )
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            throw PermissionDiagnosticFailure.bundleIdentifierUnavailable
        }
        guard let executableURL = Bundle.main.executableURL else {
            throw PermissionDiagnosticFailure.executablePathUnavailable
        }
        let output = status.renderedProtocol(
            bundleIdentifier: bundleIdentifier,
            executablePath: executableURL.resolvingSymlinksInPath().path
        )
        guard writePermissionDiagnostic(output, to: STDOUT_FILENO) else {
            throw PermissionDiagnosticFailure.outputWriteFailed
        }
        Darwin.exit(EXIT_SUCCESS)
    } catch {
        writePermissionDiagnostic(
            "Permission diagnostic failed: \(error)\n",
            to: STDERR_FILENO
        )
        Darwin.exit(EX_SOFTWARE)
    }
}

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
let protocolProbe = AppshotProtocolProbe { (request: AppshotCaptureRequest) in
    let snapshot = try accessibilityProvider.capture(
        requestedBundleIdentifier: request.bundleIdentifier
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
    var transitionSnapshotURL: URL?
    var transitionSnapshotHeight: Double?
    if let animationTarget = request.animationTarget {
        let safeRequestID = request.requestID.map { character in
            character.isLetter || character.isNumber || character == "-"
                ? character
                : "-"
        }
        let destination = captureDirectory.appendingPathComponent(
            "transition-\(String(safeRequestID)).png"
        )
        let applicationIcon: NSImage
        if let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: snapshot.bundleIdentifier
        ) {
            applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            applicationIcon = NSWorkspace.shared.icon(for: .application)
        }
        let trimmedWindowTitle = snapshot.windowTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let title = trimmedWindowTitle.isEmpty
            ? snapshot.applicationName
            : trimmedWindowTitle
        do {
            let transition = try AppshotTransitionSnapshotRenderer.render(
                screenshotURL: screenshot.screenshotURL,
                applicationIcon: applicationIcon,
                title: title,
                animationTarget: animationTarget,
                destinationURL: destination
            )
            transitionSnapshotURL = transition.url
            transitionSnapshotHeight = transition.transitionSnapshotHeight
            probeLog(
                "rendered Appshot transition snapshot "
                    + "height=\(transition.transitionSnapshotHeight) "
                    + "file=\(transition.url.lastPathComponent)"
            )
        } catch {
            probeLog("transition snapshot unavailable error=\(error)")
        }
    }
    return AppshotCapturePayload(
        screenshotURL: screenshot.screenshotURL,
        accessibilityText: snapshot.accessibilityText,
        transitionSnapshotURL: transitionSnapshotURL,
        transitionSnapshotHeight: transitionSnapshotHeight
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
