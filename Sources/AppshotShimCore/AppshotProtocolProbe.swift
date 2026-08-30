import Foundation

public enum AppshotProtocolProbeError: Error {
    case invalidRequest
    case unsupportedRequestType(String)
}

public final class AppshotProtocolProbe {
    private let screenshotURL: URL
    private let accessibilityText: String
    private var captureRequestIDs: Set<String> = []
    private var pendingUpdates: [String: [Data]] = [:]

    public init(screenshotURL: URL, accessibilityText: String) {
        self.screenshotURL = screenshotURL
        self.accessibilityText = accessibilityText
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

        captureRequestIDs.insert(requestID)
        pendingUpdates[requestID] = [
            try responseData([
                "type": "metadata",
                "app": ["bundleIdentifier": bundleIdentifier]
            ]),
            try responseData([
                "type": "axText",
                "text": accessibilityText
            ]),
            try responseData([
                "type": "screenshot",
                "screenshotURL": screenshotURL.absoluteString
            ]),
            try responseData(["type": "completed"])
        ]
        return Data(#"{"result":"started"}"#.utf8)
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
