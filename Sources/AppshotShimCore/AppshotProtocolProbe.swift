import CoreGraphics
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
    public struct Display: Equatable, Sendable {
        public let id: Int?
        public let bounds: CGRect
        public let workArea: CGRect
        public let scaleFactor: Double

        public init(
            id: Int?,
            bounds: CGRect,
            workArea: CGRect,
            scaleFactor: Double
        ) {
            self.id = id
            self.bounds = bounds
            self.workArea = workArea
            self.scaleFactor = scaleFactor
        }
    }

    public let destinationFrame: CGRect
    public let destinationCornerRadius: Double
    public let destinationBackgroundColor: AppshotRGBColor?
    public let destinationPrimaryTextColor: AppshotRGBColor?
    public let codexDisplay: Display

    public var destinationFrameWidth: Double { destinationFrame.width }
    public var displayScaleFactor: Double { codexDisplay.scaleFactor }

    public init(
        destinationFrame: CGRect,
        destinationCornerRadius: Double,
        destinationBackgroundColor: AppshotRGBColor?,
        destinationPrimaryTextColor: AppshotRGBColor?,
        codexDisplay: Display
    ) {
        self.destinationFrame = destinationFrame
        self.destinationCornerRadius = destinationCornerRadius
        self.destinationBackgroundColor = destinationBackgroundColor
        self.destinationPrimaryTextColor = destinationPrimaryTextColor
        self.codexDisplay = codexDisplay
    }

    public init(
        destinationFrameWidth: Double,
        displayScaleFactor: Double,
        destinationPrimaryTextColor: AppshotRGBColor?
    ) {
        self.init(
            destinationFrame: CGRect(
                x: 0,
                y: 0,
                width: destinationFrameWidth,
                height: destinationFrameWidth
                    * AppshotTransitionSnapshotRenderer.screenshotHeight
                    / AppshotTransitionSnapshotRenderer.logicalWidth
            ),
            destinationCornerRadius: 0,
            destinationBackgroundColor: nil,
            destinationPrimaryTextColor: destinationPrimaryTextColor,
            codexDisplay: Display(
                id: nil,
                bounds: .zero,
                workArea: .zero,
                scaleFactor: displayScaleFactor
            )
        )
    }

    fileprivate init?(object: Any?) {
        guard
            let object = object as? [String: Any],
            let destinationFrame = object["destinationFrame"] as? [String: Any],
            let codexDisplay = object["codexDisplay"] as? [String: Any],
            let parsedDestinationFrame = Self.rect(destinationFrame),
            let displayScaleFactor = (codexDisplay["scaleFactor"] as? NSNumber)?.doubleValue,
            displayScaleFactor.isFinite,
            displayScaleFactor > 0,
            let destinationCornerRadius = Self.number(
                object["destinationCornerRadius"],
                default: 0
            ),
            destinationCornerRadius >= 0
        else {
            return nil
        }
        self.init(
            destinationFrame: parsedDestinationFrame,
            destinationCornerRadius: destinationCornerRadius,
            destinationBackgroundColor: AppshotRGBColor(
                object: object["destinationBackgroundColor"]
            ),
            destinationPrimaryTextColor: AppshotRGBColor(
                object: object["destinationPrimaryTextColor"]
            ),
            codexDisplay: Display(
                id: (codexDisplay["id"] as? NSNumber)?.intValue,
                bounds: Self.rect(codexDisplay["bounds"]) ?? .zero,
                workArea: Self.rect(codexDisplay["workArea"]) ?? .zero,
                scaleFactor: displayScaleFactor
            )
        )
    }

    private static func number(_ value: Any?, default defaultValue: Double) -> Double? {
        guard let value else { return defaultValue }
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func rect(_ value: Any?) -> CGRect? {
        guard
            let object = value as? [String: Any],
            let x = number(object["x"], default: 0),
            let y = number(object["y"], default: 0),
            let width = number(object["width"], default: -1),
            let height = number(object["height"], default: -1),
            width > 0,
            height > 0
        else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
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
    public let animationDuration: Double?
    public let transitionSpringResponse: Double?
    public let transitionSpringDampingFraction: Double?
    public let composerHandoffFinished: (() -> Void)?

    public init(
        screenshotURL: URL,
        accessibilityText: String,
        transitionSnapshotURL: URL? = nil,
        transitionSnapshotHeight: Double? = nil,
        animationDuration: Double? = nil,
        transitionSpringResponse: Double? = nil,
        transitionSpringDampingFraction: Double? = nil,
        composerHandoffFinished: (() -> Void)? = nil
    ) {
        self.screenshotURL = screenshotURL
        self.accessibilityText = accessibilityText
        self.transitionSnapshotURL = transitionSnapshotURL
        self.transitionSnapshotHeight = transitionSnapshotHeight
        self.animationDuration = animationDuration
        self.transitionSpringResponse = transitionSpringResponse
        self.transitionSpringDampingFraction = transitionSpringDampingFraction
        self.composerHandoffFinished = composerHandoffFinished
    }
}

public final class AppshotProtocolProbe {
    public typealias CaptureProvider = (AppshotCaptureRequest) throws -> AppshotCapturePayload

    private let captureProvider: CaptureProvider
    private var captureRequestIDs: Set<String> = []
    private var pendingUpdates: [String: [Data]] = [:]
    private var composerHandoffActions: [String: () -> Void] = [:]

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
        composerHandoffActions[requestID] = payload.composerHandoffFinished
        var startReply: [String: Any] = ["result": "started"]
        if let transitionSnapshotHeight = payload.transitionSnapshotHeight,
           transitionSnapshotHeight.isFinite,
           transitionSnapshotHeight > 0 {
            startReply["transitionSnapshotHeight"] = transitionSnapshotHeight
        }
        addPositiveFinite(
            payload.animationDuration,
            key: "animationDuration",
            to: &startReply
        )
        addPositiveFinite(
            payload.transitionSpringResponse,
            key: "transitionSpringResponse",
            to: &startReply
        )
        addPositiveFinite(
            payload.transitionSpringDampingFraction,
            key: "transitionSpringDampingFraction",
            to: &startReply
        )
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
        if updates.isEmpty {
            composerHandoffActions.removeValue(forKey: requestID)?()
        }
        return reply
    }

    private func addPositiveFinite(
        _ value: Double?,
        key: String,
        to object: inout [String: Any]
    ) {
        guard let value, value.isFinite, value > 0 else { return }
        object[key] = value
    }

    private func responseData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    public func hasCapture(requestID: String) -> Bool {
        captureRequestIDs.contains(requestID)
    }
}
