import Foundation
import Testing
@testable import AppshotShimCore

@Test("start capture returns started and registers the request")
func startCaptureRegistersRequest() throws {
    let probe = AppshotProtocolProbe(
        screenshotURL: URL(fileURLWithPath: "/tmp/com.openai.sky.CUAService/probe.png"),
        accessibilityText: "Intel Appshot compatibility probe"
    )

    let reply = try probe.handle(
        requestType: "ComputerUseIPCAppStartCaptureRequest",
        requestJSON: #"{"requestId":"request-1","app":"com.apple.TextEdit","version":2}"#.data(using: .utf8)!
    )

    #expect(String(decoding: reply, as: UTF8.self) == #"{"result":"started"}"#)
    #expect(probe.hasCapture(requestID: "request-1"))
}

@Test("next capture update emits the Appshots sequence in protocol order")
func nextCaptureUpdateSequence() throws {
    let probe = AppshotProtocolProbe(
        screenshotURL: URL(fileURLWithPath: "/tmp/com.openai.sky.CUAService/probe.png"),
        accessibilityText: "Intel Appshot compatibility probe"
    )
    _ = try probe.handle(
        requestType: "ComputerUseIPCAppStartCaptureRequest",
        requestJSON: #"{"requestId":"request-2","app":"com.apple.TextEdit","version":2}"#.data(using: .utf8)!
    )

    let nextRequest = #"{"requestId":"request-2"}"#.data(using: .utf8)!
    let replies = try (0..<4).map { _ in
        String(
            decoding: try probe.handle(
                requestType: "ComputerUseIPCAppNextCaptureUpdateRequest",
                requestJSON: nextRequest
            ),
            as: UTF8.self
        )
    }

    let expectedReplies = [
        #"{"type":"metadata","app":{"bundleIdentifier":"com.apple.TextEdit"}}"#,
        #"{"type":"axText","text":"Intel Appshot compatibility probe"}"#,
        #"{"type":"screenshot","screenshotURL":"file:///tmp/com.openai.sky.CUAService/probe.png"}"#,
        #"{"type":"completed"}"#
    ]

    for (reply, expectedReply) in zip(replies, expectedReplies) {
        let actualObject = try #require(
            JSONSerialization.jsonObject(with: Data(reply.utf8)) as? NSDictionary
        )
        let expectedObject = try #require(
            JSONSerialization.jsonObject(with: Data(expectedReply.utf8)) as? NSDictionary
        )
        #expect(actualObject == expectedObject)
    }
}
