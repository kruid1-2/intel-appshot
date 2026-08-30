import AppKit
import Foundation
import Testing
@testable import AppshotShimCore

@Test("Apple Event bridge returns protocol JSON in the direct object")
func appleEventBridgeReturnsDirectObject() throws {
    let probe = AppshotProtocolProbe(
        screenshotURL: URL(fileURLWithPath: "/tmp/com.openai.sky.CUAService/probe.png"),
        accessibilityText: "Intel Appshot compatibility probe"
    )
    let bridge = AppshotAppleEventBridge(protocolProbe: probe)
    let target = NSAppleEventDescriptor.null()
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(0x536B4375),
        eventID: AEEventID(0x536E6452),
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(
        NSAppleEventDescriptor(string: "ComputerUseIPCAppStartCaptureRequest"),
        forKeyword: AEKeyword(0x52737054)
    )
    event.setParam(
        NSAppleEventDescriptor(string: "CodexComputerUseNativeBridge-1"),
        forKeyword: AEKeyword(0x436C566E)
    )
    event.setParam(
        try #require(NSAppleEventDescriptor(
            descriptorType: DescType(typeData),
            data: #"{"requestId":"request-ae","app":"com.apple.TextEdit","version":2}"#.data(using: .utf8)!
        )),
        forKeyword: AEKeyword(0x52657144)
    )
    let reply = NSAppleEventDescriptor(
        eventClass: AEEventClass(0x536B4375),
        eventID: AEEventID(0x536E6452),
        targetDescriptor: target,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )

    bridge.handleAppleEvent(event, withReplyEvent: reply)

    let response = try #require(
        reply.paramDescriptor(forKeyword: keyDirectObject)?.data
    )
    #expect(String(decoding: response, as: UTF8.self) == #"{"result":"started"}"#)
}
