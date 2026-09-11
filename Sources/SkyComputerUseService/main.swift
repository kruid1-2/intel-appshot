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
app.setActivationPolicy(.accessory)

let captureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("com.openai.sky.CUAService", isDirectory: true)

let accessibilityProvider = FrontmostAccessibilitySnapshotProvider()
let screenshotProvider = FrontmostWindowScreenshotProvider()
// Only the locally adapted Composer understands exterior-shadow canvas geometry.
// Stock sessions retain their original transition image sizing contract.
let magicMoveCoordinator = AppshotMagicMoveCoordinator(
    preservesExteriorShadow: ProcessInfo.processInfo.environment["APPSHOT_TRANSITION_LAYOUT"] == "1"
)
let accessibilityQueue = DispatchQueue(
    label: "com.openai.sky.CUAService.appshot.accessibility",
    qos: .userInitiated
)
let screenshotEncodingQueue = DispatchQueue(
    label: "com.openai.sky.CUAService.appshot.screenshot-encoding",
    qos: .userInitiated
)
let applicationIconQueue = DispatchQueue(
    label: "com.openai.sky.CUAService.appshot.application-icon",
    qos: .userInitiated
)
let protocolProbe = AppshotProtocolProbe { (request: AppshotCaptureRequest) in
    let safeRequestID = request.requestID.map { character in
        character.isLetter || character.isNumber || character == "-"
            ? character
            : "-"
    }
    let requestScreenshotURL = captureDirectory.appendingPathComponent(
        "frontmost-window-\(String(safeRequestID)).png"
    )
    let selectionStartedAt = CFAbsoluteTimeGetCurrent()
    let selection = try accessibilityProvider.locateWindow(
        requestedBundleIdentifier: request.bundleIdentifier
    )
    let selectionDuration = Int(
        ((CFAbsoluteTimeGetCurrent() - selectionStartedAt) * 1_000).rounded()
    )
    probeLog(
        "selected frontmost AX window app=\(selection.applicationName) "
            + "bundle=\(selection.bundleIdentifier) pid=\(selection.processIdentifier) "
            + "window=\(selection.windowTitle) durationMs=\(selectionDuration)"
    )
    let accessibilityWork = AppshotBackgroundWork<FrontmostAccessibilitySnapshot>(
        queue: accessibilityQueue
    ) {
        accessibilityProvider.capture(selection: selection)
    }
    let iconWork = request.animationTarget.map { _ in
        AppshotBackgroundWork<CGImage>(queue: applicationIconQueue) {
            let applicationIcon: NSImage
            if let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: selection.bundleIdentifier
            ) {
                applicationIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            } else {
                applicationIcon = NSWorkspace.shared.icon(for: .application)
            }
            var iconRect = CGRect(origin: .zero, size: applicationIcon.size)
            guard let iconImage = applicationIcon.cgImage(
                forProposedRect: &iconRect,
                context: nil,
                hints: nil
            ) else {
                throw AppshotMagicMoveControllerError.applicationIconUnavailable
            }
            return iconImage
        }
    }
    let imageCapture = try screenshotProvider.captureImage(
        accessibilityWindow: selection.windowElement,
        processIdentifier: selection.processIdentifier
    )
    probeLog(
        "captured frontmost window image app=\(selection.applicationName) "
            + "bundle=\(selection.bundleIdentifier) pid=\(selection.processIdentifier) "
            + "windowID=\(imageCapture.windowID) mapping=\(imageCapture.mappingMethod) "
            + "frame=\(imageCapture.windowFrame) "
            + "mappingMs=\(imageCapture.mappingDurationMilliseconds) "
            + "shareableContentMs=\(imageCapture.shareableContentDurationMilliseconds) "
            + "imageMs=\(imageCapture.imageCaptureDurationMilliseconds) "
            + "totalMs=\(imageCapture.totalDurationMilliseconds)"
    )
    let screenshotWork = AppshotBackgroundWork<FrontmostWindowScreenshot>(
        queue: screenshotEncodingQueue
    ) {
        try imageCapture.writePNG(to: requestScreenshotURL)
    }
    var startedMove: AppshotMagicMoveController?
    do {
        var transitionSnapshotURL: URL?
        var transitionSnapshotHeight: Double?
        var animationDuration: Double?
        var transitionSpringResponse: Double?
        var transitionSpringDampingFraction: Double?
        var composerHandoffFinished: (() -> Void)?
        if let animationTarget = request.animationTarget {
            let destination = captureDirectory.appendingPathComponent(
                "transition-\(String(safeRequestID)).png"
            )
            let applicationIconImage = try iconWork!.wait()
            let trimmedWindowTitle = selection.windowTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let title = trimmedWindowTitle.isEmpty
                ? selection.applicationName
                : trimmedWindowTitle
            do {
                let move = try magicMoveCoordinator.start(
                    requestID: request.requestID,
                    screenshotImage: imageCapture.image,
                    sourceFrame: imageCapture.windowFrame,
                    applicationIconImage: applicationIconImage,
                    title: title,
                    animationTarget: animationTarget,
                    transitionSnapshotURL: destination
                )
                startedMove = move
                transitionSnapshotURL = move.transitionSnapshot.url
                transitionSnapshotHeight = move.transitionSnapshot.transitionSnapshotHeight
                animationDuration = move.spring.animationDuration
                transitionSpringResponse = move.spring.response
                transitionSpringDampingFraction = move.spring.dampingFraction
                composerHandoffFinished = {
                    MainActor.assumeIsolated {
                        magicMoveCoordinator.markComposerHandoffFinished(
                            requestID: request.requestID
                        )
                    }
                }
                probeLog(
                    "prepared Appshot magic move "
                        + "response=\(move.spring.response) "
                        + "damping=\(move.spring.dampingFraction) "
                        + "duration=\(move.spring.animationDuration) "
                        + "height=\(move.transitionSnapshot.transitionSnapshotHeight) "
                        + "file=\(move.transitionSnapshot.url.lastPathComponent)"
                )
            } catch {
                probeLog("magic move unavailable error=\(error)")
                let screenshot = try screenshotWork.wait()
                do {
                    let transition = try AppshotTransitionSnapshotRenderer.render(
                        screenshotURL: screenshot.screenshotURL,
                        applicationIcon: NSImage(
                            cgImage: applicationIconImage,
                            size: .zero
                        ),
                        title: title,
                        animationTarget: animationTarget,
                        destinationURL: destination
                    )
                    transitionSnapshotURL = transition.url
                    transitionSnapshotHeight = transition.transitionSnapshotHeight
                    probeLog(
                        "rendered fallback Appshot transition snapshot "
                            + "height=\(transition.transitionSnapshotHeight) "
                            + "file=\(transition.url.lastPathComponent)"
                    )
                } catch {
                    probeLog("transition snapshot unavailable error=\(error)")
                }
            }
        }

        let snapshot = try accessibilityWork.wait()
        let screenshot = try screenshotWork.wait()
        probeLog(
            "captured frontmost AX app=\(snapshot.applicationName) "
                + "bundle=\(snapshot.bundleIdentifier) pid=\(snapshot.processIdentifier) "
                + "window=\(snapshot.windowTitle) nodes=\(snapshot.nodeCount) "
                + "truncated=\(snapshot.wasTruncated) "
                + "durationMs=\(snapshot.durationMilliseconds)"
        )
        probeLog(
            "persisted frontmost window screenshot app=\(snapshot.applicationName) "
                + "bundle=\(snapshot.bundleIdentifier) pid=\(snapshot.processIdentifier) "
                + "windowID=\(screenshot.windowID) mapping=\(screenshot.mappingMethod) "
                + "frame=\(screenshot.windowFrame) "
                + "mappingMs=\(screenshot.mappingDurationMilliseconds) "
                + "shareableContentMs=\(screenshot.shareableContentDurationMilliseconds) "
                + "imageAndPNGMs=\(screenshot.imageCaptureDurationMilliseconds) "
                + "totalMs=\(screenshot.totalDurationMilliseconds)"
        )
        // Source identity, CGImage, AX, and artifacts are now fixed. Schedule the
        // one-shot host activation without blocking this start reply or its updates.
        startedMove?.startWhenHostIsReady(.codex(), requestID: request.requestID)
        return AppshotCapturePayload(
            screenshotURL: screenshot.screenshotURL,
            accessibilityText: snapshot.accessibilityText,
            transitionSnapshotURL: transitionSnapshotURL,
            transitionSnapshotHeight: transitionSnapshotHeight,
            animationDuration: animationDuration,
            transitionSpringResponse: transitionSpringResponse,
            transitionSpringDampingFraction: transitionSpringDampingFraction,
            composerHandoffFinished: composerHandoffFinished
        )
    } catch {
        startedMove?.cancel()
        throw error
    }
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
