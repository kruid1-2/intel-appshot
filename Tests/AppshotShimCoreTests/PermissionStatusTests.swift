import Foundation
import Testing
@testable import AppshotShimCore

private enum PermissionQueryTestError: Error {
    case failed
}

@Test("permission diagnostic recognizes only the exact internal argument")
func permissionDiagnosticRequiresExactArgument() {
    #expect(
        PermissionStatusDiagnostic.isRequested(
            arguments: ["SkyComputerUseService", "--permission-status"]
        )
    )
    #expect(
        !PermissionStatusDiagnostic.isRequested(
            arguments: ["SkyComputerUseService"]
        )
    )
    #expect(
        !PermissionStatusDiagnostic.isRequested(
            arguments: [
                "SkyComputerUseService",
                "--permission-status",
                "unexpected"
            ]
        )
    )
}

@Test("permission diagnostic reports both permissions granted")
func permissionDiagnosticReportsBothGranted() {
    let result = PermissionStatusDiagnostic.evaluate(
        accessibilityQuery: { true },
        screenRecordingQuery: { true }
    )

    #expect(
        result.renderedStatus == "Accessibility: granted\nScreen Recording: granted\n"
    )
}

@Test("permission diagnostic reports Accessibility denied independently")
func permissionDiagnosticReportsAccessibilityDenied() {
    let result = PermissionStatusDiagnostic.evaluate(
        accessibilityQuery: { false },
        screenRecordingQuery: { true }
    )

    #expect(
        result.renderedStatus == "Accessibility: denied\nScreen Recording: granted\n"
    )
}

@Test("permission diagnostic reports Screen Recording denied independently")
func permissionDiagnosticReportsScreenRecordingDenied() {
    let result = PermissionStatusDiagnostic.evaluate(
        accessibilityQuery: { true },
        screenRecordingQuery: { false }
    )

    #expect(
        result.renderedStatus == "Accessibility: granted\nScreen Recording: denied\n"
    )
}

@Test("permission diagnostic reports both permissions denied as a normal result")
func permissionDiagnosticReportsBothDenied() {
    let result = PermissionStatusDiagnostic.evaluate(
        accessibilityQuery: { false },
        screenRecordingQuery: { false }
    )

    #expect(
        result.renderedStatus == "Accessibility: denied\nScreen Recording: denied\n"
    )
}

@Test("permission diagnostic stdout protocol ends with one completion marker")
func permissionDiagnosticProtocolHasFinalCompletionMarker() {
    let result = PermissionStatusResult(
        accessibilityGranted: true,
        screenRecordingGranted: false
    )

    let output = result.renderedProtocol(
        bundleIdentifier: "com.openai.sky.CUAService",
        executablePath: "/canonical/SkyComputerUseService"
    )

    #expect(
        output == "Bundle ID: com.openai.sky.CUAService\n"
            + "Executable: /canonical/SkyComputerUseService\n"
            + "Accessibility: granted\n"
            + "Screen Recording: denied\n"
            + "Permission Diagnostic: completed\n"
    )
    #expect(
        output.components(separatedBy: "Permission Diagnostic: completed").count == 2
    )
}

@Test("permission diagnostic propagates a query mechanism failure")
func permissionDiagnosticPropagatesQueryFailure() {
    #expect(throws: PermissionQueryTestError.self) {
        try PermissionStatusDiagnostic.evaluate(
            accessibilityQuery: { throw PermissionQueryTestError.failed },
            screenRecordingQuery: { true }
        )
    }
}
