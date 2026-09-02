import Foundation

public struct PermissionStatusResult: Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }

    public var renderedStatus: String {
        let accessibility = accessibilityGranted ? "granted" : "denied"
        let screenRecording = screenRecordingGranted ? "granted" : "denied"
        return "Accessibility: \(accessibility)\n"
            + "Screen Recording: \(screenRecording)\n"
    }

    public func renderedProtocol(
        bundleIdentifier: String,
        executablePath: String
    ) -> String {
        "Bundle ID: \(bundleIdentifier)\n"
            + "Executable: \(executablePath)\n"
            + renderedStatus
            + "Permission Diagnostic: completed\n"
    }
}

public enum PermissionStatusDiagnostic {
    public static func isRequested(arguments: [String]) -> Bool {
        Array(arguments.dropFirst()) == ["--permission-status"]
    }

    public static func evaluate(
        accessibilityQuery: () throws -> Bool,
        screenRecordingQuery: () throws -> Bool
    ) rethrows -> PermissionStatusResult {
        PermissionStatusResult(
            accessibilityGranted: try accessibilityQuery(),
            screenRecordingGranted: try screenRecordingQuery()
        )
    }
}
