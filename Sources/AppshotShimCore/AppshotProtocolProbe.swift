import Foundation

public enum AppshotProtocolProbeError: Error {
    case invalidRequest
    case unsupportedRequestType(String)
}

public struct AppshotRGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    fileprivate init?(object: Any?) {
        guard
            let object = object as? [String: Any],
            let red = Self.number(object["red"]),
            let green = Self.number(object["green"]),
            let blue = Self.number(object["blue"])
        else {
            return nil
        }
        self.init(red: red, green: green, blue: blue)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

public struct AppshotAnimationTarget: Equatable, Sendable {
    public let destinationFrameWidth: Double
    public let displayScaleFactor: Double
    public let destinationPrimaryTextColor: AppshotRGBColor?

    public init(
        destinationFrameWidth: Double,
        displayScaleFactor: Double,
        destinationPrimaryTextColor: AppshotRGBColor?
    ) {
        self.destinationFrameWidth = destinationFrameWidth
        self.displayScaleFactor = displayScaleFactor
        self.destinationPrimaryTextColor = destinationPrimaryTextColor
    }

    fileprivate init?(object: Any?) {
        guard
            let object = object as? [String: Any],
            let destinationFrame = object["destinationFrame"] as? [String: Any],
            let codexDisplay = object["codexDisplay"] as? [String: Any],
            let destinationFrameWidth = (destinationFrame["width"] as? NSNumber)?.doubleValue,
            destinationFrameWidth > 0,
            let displayScaleFactor = (codexDisplay["scaleFactor"] as? NSNumber)?.doubleValue,
            displayScaleFactor > 0
        else {
            return nil
        }
        self.init(
            destinationFrameWidth: destinationFrameWidth,
            displayScaleFactor: displayScaleFactor,
            destinationPrimaryTextColor: AppshotRGBColor(
                object: object["destinationPrimaryTextColor"]
            )
        )
    }
}

public struct AppshotCaptureRequest: Equatable, Sendable {
    public let requestID: String
    public let bundleIdentifier: String
    public let animationTarget: AppshotAnimationTarget?

    public init(
        requestID: String,
        bundleIdentifier: String,
        animationTarget: AppshotAnimationTarget?
    ) {
        self.requestID = requestID
        self.bundleIdentifier = bundleIdentifier
        self.animationTarget = animationTarget
    }
}

public struct AppshotCapturePayload {
    public let screenshotURL: URL
    public let accessibilityText: String
    public let transitionSnapshotURL: URL?
    public let transitionSnapshotHeight: Double?

    public init(
        screenshotURL: URL,
        accessibilityText: String,
        transitionSnapshotURL: URL? = nil,
        transitionSnapshotHeight: Double? = nil
    ) {
        self.screenshotURL = screenshotURL
        self.accessibilityText = accessibilityText
        self.transitionSnapshotURL = transitionSnapshotURL
        self.transitionSnapshotHeight = transitionSnapshotHeight
    }
}

public final class AppshotProtocolProbe {
    public typealias CaptureProvider = (AppshotCaptureRequest) throws -> AppshotCapturePayload

    private let captureProvider: CaptureProvider
    private var captureRequestIDs: Set<String> = []
    private var pendingUpdates: [String: [Data]] = [:]

    public init(screenshotURL: URL, accessibilityText: String) {
        self.captureProvider = { _ in
            AppshotCapturePayload(
                screenshotURL: screenshotURL,
                accessibilityText: accessibilityText
            )
        }
    }

    public init(captureProvider: @escaping CaptureProvider) {
        self.captureProvider = captureProvider
    }

    public convenience init(
        captureProvider: @escaping (String) throws -> AppshotCapturePayload
    ) {
        self.init { request in
            try captureProvider(request.bundleIdentifier)
        }
    }

    public func handle(requestType: String, requestJSON: Data) throws -> Data {
        switch requestType {
        case "ComputerUseIPCAppStartCaptureRequest":
            return try startCapture(requestJSON: requestJSON)
        case "ComputerUseIPCAppNextCaptureUpdateRequest":
            return try nextCaptureUpdate(requestJSON: requestJSON)
        case "ComputerUseIPCAppGetSkyshotRequest":
            return Data("{}".utf8)
        default:
            throw AppshotProtocolProbeError.unsupportedRequestType(requestType)
        }
    }

    private func startCapture(requestJSON: Data) throws -> Data {
        guard
            let object = try JSONSerialization.jsonObject(with: requestJSON) as? [String: Any],
            let requestID = object["requestId"] as? String,
            let bundleIdentifier = object["app"] as? String,
            !requestID.isEmpty
        else {
            throw AppshotProtocolProbeError.invalidRequest
        }

        let captureRequest = AppshotCaptureRequest(
            requestID: requestID,
            bundleIdentifier: bundleIdentifier,
            animationTarget: AppshotAnimationTarget(object: object["animationTarget"])
        )
        let payload = try captureProvider(captureRequest)
        var screenshotUpdate: [String: Any] = [
            "type": "screenshot",
            "screenshotURL": payload.screenshotURL.absoluteString
        ]
        if let transitionSnapshotURL = payload.transitionSnapshotURL {
            screenshotUpdate["transitionSnapshotURL"] = transitionSnapshotURL.absoluteString
        }
        captureRequestIDs.insert(requestID)
        pendingUpdates[requestID] = [
            try responseData([
                "type": "metadata",
                "app": ["bundleIdentifier": bundleIdentifier]
            ]),
            try responseData([
                "type": "axText",
                "text": payload.accessibilityText
            ]),
            try responseData(screenshotUpdate),
            try responseData(["type": "completed"])
        ]
        var startReply: [String: Any] = ["result": "started"]
        if let transitionSnapshotHeight = payload.transitionSnapshotHeight,
           transitionSnapshotHeight.isFinite,
           transitionSnapshotHeight > 0 {
            startReply["transitionSnapshotHeight"] = transitionSnapshotHeight
        }
        return try responseData(startReply)
    }

    private func nextCaptureUpdate(requestJSON: Data) throws -> Data {
        guard
            let object = try JSONSerialization.jsonObject(with: requestJSON) as? [String: Any],
            let requestID = object["requestId"] as? String,
            var updates = pendingUpdates[requestID],
            !updates.isEmpty
        else {
            throw AppshotProtocolProbeError.invalidRequest
        }

        let reply = updates.removeFirst()
        pendingUpdates[requestID] = updates
        return reply
    }

    private func responseData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public func hasCapture(requestID: String) -> Bool {
        captureRequestIDs.contains(requestID)
    }
}
