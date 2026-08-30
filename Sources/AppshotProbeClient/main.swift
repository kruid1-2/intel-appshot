import Foundation

enum ProbeClientError: Error, CustomStringConvertible {
    case invalidPID
    case descriptorCreationFailed
    case serviceError(Int32, String)
    case missingResponse
    case invalidResponse
    case unexpectedResponse(String)

    var description: String {
        switch self {
        case .invalidPID:
            return "usage: AppshotProbeClient <service-pid>"
        case .descriptorCreationFailed:
            return "could not create Apple Event descriptor"
        case let .serviceError(number, message):
            return "service error \(number): \(message)"
        case .missingResponse:
            return "reply did not include direct-object response data"
        case .invalidResponse:
            return "reply response was not a JSON object"
        case let .unexpectedResponse(message):
            return message
        }
    }
}

let eventClass = AEEventClass(0x536B4375) // SkCu
let eventID = AEEventID(0x536E6452) // SndR
let requestTypeKeyword = AEKeyword(0x52737054) // RspT
let requestDataKeyword = AEKeyword(0x52657144) // ReqD
let clientVersionKeyword = AEKeyword(0x436C566E) // ClVn

func sendRequest(
    pid: pid_t,
    requestType: String,
    request: [String: Any]
) throws -> [String: Any] {
    let target = NSAppleEventDescriptor(processIdentifier: pid)
    let event = NSAppleEventDescriptor(
        eventClass: eventClass,
        eventID: eventID,
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(
        NSAppleEventDescriptor(string: requestType),
        forKeyword: requestTypeKeyword
    )
    event.setParam(
        NSAppleEventDescriptor(string: "CodexComputerUseNativeBridge-1"),
        forKeyword: clientVersionKeyword
    )
    let requestData = try JSONSerialization.data(
        withJSONObject: request,
        options: [.sortedKeys]
    )
    guard let requestDescriptor = NSAppleEventDescriptor(
        descriptorType: DescType(typeData),
        data: requestData
    ) else {
        throw ProbeClientError.descriptorCreationFailed
    }
    event.setParam(requestDescriptor, forKeyword: requestDataKeyword)

    let reply = try event.sendEvent(
        options: [.waitForReply, .neverInteract],
        timeout: 3
    )
    if let errorDescriptor = reply.paramDescriptor(forKeyword: keyErrorNumber) {
        let message = reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue
            ?? "Unknown error"
        throw ProbeClientError.serviceError(errorDescriptor.int32Value, message)
    }
    guard let responseData = reply.paramDescriptor(forKeyword: keyDirectObject)?.data else {
        throw ProbeClientError.missingResponse
    }
    guard let response = try JSONSerialization.jsonObject(with: responseData)
        as? [String: Any] else {
        throw ProbeClientError.invalidResponse
    }
    return response
}

do {
    guard
        CommandLine.arguments.count == 2,
        let parsedPID = Int32(CommandLine.arguments[1]),
        parsedPID > 0
    else {
        throw ProbeClientError.invalidPID
    }

    let requestID = "standalone-integration-probe"
    let started = try sendRequest(
        pid: parsedPID,
        requestType: "ComputerUseIPCAppStartCaptureRequest",
        request: [
            "requestId": requestID,
            "app": "com.apple.TextEdit",
            "permissionRequestId": "standalone-permission-probe",
            "version": 2
        ]
    )
    guard started["result"] as? String == "started" else {
        throw ProbeClientError.unexpectedResponse("start response was not started")
    }

    var updateTypes: [String] = []
    var screenshotPath: String?
    for _ in 0..<4 {
        let update = try sendRequest(
            pid: parsedPID,
            requestType: "ComputerUseIPCAppNextCaptureUpdateRequest",
            request: ["requestId": requestID]
        )
        guard let type = update["type"] as? String else {
            throw ProbeClientError.unexpectedResponse("capture update had no type")
        }
        updateTypes.append(type)
        if type == "screenshot", let value = update["screenshotURL"] as? String {
            screenshotPath = URL(string: value)?.path
        }
    }

    guard updateTypes == ["metadata", "axText", "screenshot", "completed"] else {
        throw ProbeClientError.unexpectedResponse(
            "unexpected update sequence: \(updateTypes.joined(separator: ","))"
        )
    }
    guard
        let screenshotPath,
        FileManager.default.fileExists(atPath: screenshotPath)
    else {
        throw ProbeClientError.unexpectedResponse("screenshot file was not created")
    }

    let result: [String: Any] = [
        "pid": parsedPID,
        "result": "passed",
        "screenshotPath": screenshotPath,
        "updateTypes": updateTypes
    ]
    let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: output, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
