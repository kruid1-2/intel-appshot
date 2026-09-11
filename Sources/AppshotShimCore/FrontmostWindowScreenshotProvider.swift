import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct FrontmostWindowImageCapture: @unchecked Sendable {
    public let image: CGImage
    public let windowID: CGWindowID
    public let windowFrame: CGRect
    public let mappingMethod: String
    public let mappingDurationMilliseconds: Int
    public let shareableContentDurationMilliseconds: Int
    public let imageCaptureDurationMilliseconds: Int
    public let totalDurationMilliseconds: Int

    public init(
        image: CGImage,
        windowID: CGWindowID,
        windowFrame: CGRect,
        mappingMethod: String,
        mappingDurationMilliseconds: Int,
        shareableContentDurationMilliseconds: Int,
        imageCaptureDurationMilliseconds: Int,
        totalDurationMilliseconds: Int
    ) {
        self.image = image
        self.windowID = windowID
        self.windowFrame = windowFrame
        self.mappingMethod = mappingMethod
        self.mappingDurationMilliseconds = mappingDurationMilliseconds
        self.shareableContentDurationMilliseconds = shareableContentDurationMilliseconds
        self.imageCaptureDurationMilliseconds = imageCaptureDurationMilliseconds
        self.totalDurationMilliseconds = totalDurationMilliseconds
    }

    public func writePNG(to destination: URL) throws -> FrontmostWindowScreenshot {
        let startedAt = CFAbsoluteTimeGetCurrent()
        try WindowScreenshotPNGWriter.write(image: image, to: destination)
        let writeDuration = Int(
            ((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000).rounded()
        )
        return FrontmostWindowScreenshot(
            screenshotURL: destination,
            windowID: windowID,
            windowFrame: windowFrame,
            mappingMethod: mappingMethod,
            mappingDurationMilliseconds: mappingDurationMilliseconds,
            shareableContentDurationMilliseconds: shareableContentDurationMilliseconds,
            imageCaptureDurationMilliseconds: imageCaptureDurationMilliseconds + writeDuration,
            totalDurationMilliseconds: totalDurationMilliseconds + writeDuration
        )
    }
}

public struct FrontmostWindowScreenshot {
    public let screenshotURL: URL
    public let windowID: CGWindowID
    public let windowFrame: CGRect
    public let mappingMethod: String
    public let mappingDurationMilliseconds: Int
    public let shareableContentDurationMilliseconds: Int
    public let imageCaptureDurationMilliseconds: Int
    public let totalDurationMilliseconds: Int
}

public enum FrontmostWindowScreenshotError: Error, CustomStringConvertible {
    case screenRecordingPermissionDenied
    case screenCaptureKitRequiresMacOS14
    case shareableContentUnavailable(String)
    case shareableWindowNotFound(String)
    case imageCaptureFailed(String)
    case callbackTimedOut(stage: String)

    public var description: String {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is not granted to Codex Computer Use"
        case .screenCaptureKitRequiresMacOS14:
            return "SCScreenshotManager requires macOS 14 or later"
        case let .shareableContentUnavailable(message):
            return "SCShareableContent failed: \(message)"
        case let .shareableWindowNotFound(message):
            return "no unique SCWindow matched the AX window: \(message)"
        case let .imageCaptureFailed(message):
            return "SCScreenshotManager failed: \(message)"
        case let .callbackTimedOut(stage):
            return "ScreenCaptureKit timed out during \(stage)"
        }
    }
}

private final class ScreenshotCallbackBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }

    func result() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

public final class FrontmostWindowScreenshotProvider {
    private let windowIDResolver = AXWindowIDResolver()
    private let callbackTimeout: DispatchTimeInterval
    private let screenCaptureAccess: () -> Bool

    public init(
        callbackTimeoutSeconds: Int = 10,
        screenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        callbackTimeout = .seconds(callbackTimeoutSeconds)
        self.screenCaptureAccess = screenCaptureAccess
    }

    public func capture(
        accessibilityWindow: AXUIElement,
        processIdentifier: pid_t,
        destination: URL
    ) throws -> FrontmostWindowScreenshot {
        let capture = try captureImage(
            accessibilityWindow: accessibilityWindow,
            processIdentifier: processIdentifier
        )
        return try capture.writePNG(to: destination)
    }

    public func captureImage(
        accessibilityWindow: AXUIElement,
        processIdentifier: pid_t
    ) throws -> FrontmostWindowImageCapture {
        guard #available(macOS 14.0, *) else {
            throw FrontmostWindowScreenshotError.screenCaptureKitRequiresMacOS14
        }
        guard screenCaptureAccess() else {
            throw FrontmostWindowScreenshotError.screenRecordingPermissionDenied
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        let mappingStartedAt = CFAbsoluteTimeGetCurrent()
        let resolution = try windowIDResolver.resolve(
            window: accessibilityWindow,
            processIdentifier: processIdentifier
        )
        let mappingDuration = milliseconds(since: mappingStartedAt)

        let shareableContentStartedAt = CFAbsoluteTimeGetCurrent()
        let shareableContent = try loadShareableContent()
        let shareableContentDuration = milliseconds(since: shareableContentStartedAt)
        let identities = shareableContent.windows.map {
            ShareableWindowIdentity(
                windowID: $0.windowID,
                ownerProcessIdentifier: $0.owningApplication?.processID ?? -1
            )
        }
        let matchingIndex: Int
        do {
            matchingIndex = try ShareableWindowIdentityMatcher.matchIndex(
                windowID: resolution.windowID,
                processIdentifier: processIdentifier,
                candidates: identities
            )
        } catch {
            throw FrontmostWindowScreenshotError.shareableWindowNotFound(
                String(describing: error)
            )
        }
        let window = shareableContent.windows[matchingIndex]
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let contentInfo = SCShareableContent.info(for: filter)
        let configuration = Self.windowBodyConfiguration(
            contentRect: contentInfo.contentRect,
            pointPixelScale: CGFloat(contentInfo.pointPixelScale)
        )

        let imageCaptureStartedAt = CFAbsoluteTimeGetCurrent()
        let image = try captureImage(filter: filter, configuration: configuration)
        let imageCaptureDuration = milliseconds(since: imageCaptureStartedAt)

        return FrontmostWindowImageCapture(
            image: image,
            windowID: resolution.windowID,
            windowFrame: window.frame,
            mappingMethod: resolution.method.rawValue,
            mappingDurationMilliseconds: mappingDuration,
            shareableContentDurationMilliseconds: shareableContentDuration,
            imageCaptureDurationMilliseconds: imageCaptureDuration,
            totalDurationMilliseconds: milliseconds(since: startedAt)
        )
    }

    @available(macOS 14.0, *)
    static func windowBodyConfiguration(
        contentRect: CGRect,
        pointPixelScale: CGFloat
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = max(pointPixelScale, 1)
        configuration.width = max(Int(ceil(contentRect.width * scale)), 1)
        configuration.height = max(Int(ceil(contentRect.height * scale)), 1)
        configuration.showsCursor = false
        // The bitmap must describe window.frame itself. ScreenCaptureKit otherwise
        // fits shadow padding into these same pixel dimensions, shrinking the body.
        // MagicMove owns the separate visual shadow.
        configuration.ignoreShadowsSingleWindow = true
        return configuration
    }

    @available(macOS 14.0, *)
    private func loadShareableContent() throws -> SCShareableContent {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ScreenshotCallbackBox<SCShareableContent>()
        SCShareableContent.getExcludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        ) { content, error in
            if let content {
                box.store(.success(content))
            } else {
                box.store(.failure(
                    FrontmostWindowScreenshotError.shareableContentUnavailable(
                        error?.localizedDescription ?? "unknown error"
                    )
                ))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + callbackTimeout) == .success else {
            throw FrontmostWindowScreenshotError.callbackTimedOut(stage: "shareable content")
        }
        return try box.result()!.get()
    }

    @available(macOS 14.0, *)
    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) throws -> CGImage {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ScreenshotCallbackBox<CGImage>()
        SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) { image, error in
            if let image {
                box.store(.success(image))
            } else {
                box.store(.failure(
                    FrontmostWindowScreenshotError.imageCaptureFailed(
                        error?.localizedDescription ?? "unknown error"
                    )
                ))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + callbackTimeout) == .success else {
            throw FrontmostWindowScreenshotError.callbackTimedOut(stage: "image capture")
        }
        return try box.result()!.get()
    }

    private func milliseconds(since start: CFAbsoluteTime) -> Int {
        Int(((CFAbsoluteTimeGetCurrent() - start) * 1_000).rounded())
    }
}
