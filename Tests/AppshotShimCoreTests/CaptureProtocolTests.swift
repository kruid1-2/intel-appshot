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

@Test("start capture resolves its payload for the requested application")
func startCaptureResolvesPayloadForRequestedApplication() throws {
    var capturedBundleIdentifiers: [String] = []
    let probe = AppshotProtocolProbe { bundleIdentifier in
        capturedBundleIdentifiers.append(bundleIdentifier)
        return AppshotCapturePayload(
            screenshotURL: URL(
                fileURLWithPath: "/tmp/com.openai.sky.CUAService/music-probe.png"
            ),
            accessibilityText: "Live Music accessibility content"
        )
    }

    _ = try probe.handle(
        requestType: "ComputerUseIPCAppStartCaptureRequest",
        requestJSON: #"{"requestId":"request-music","app":"com.apple.Music","version":2}"#.data(using: .utf8)!
    )

    let nextRequest = #"{"requestId":"request-music"}"#.data(using: .utf8)!
    let replies = try (0..<4).map { _ in
        try #require(
            JSONSerialization.jsonObject(
                with: probe.handle(
                    requestType: "ComputerUseIPCAppNextCaptureUpdateRequest",
                    requestJSON: nextRequest
                )
            ) as? [String: Any]
        )
    }

    #expect(capturedBundleIdentifiers == ["com.apple.Music"])
    #expect(replies[1]["type"] as? String == "axText")
    #expect(replies[1]["text"] as? String == "Live Music accessibility content")
    #expect(replies[2]["type"] as? String == "screenshot")
    #expect(
        replies[2]["screenshotURL"] as? String
            == "file:///tmp/com.openai.sky.CUAService/music-probe.png"
    )
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

@Test("screenshot update owns the transition snapshot and completed waits behind it")
func screenshotOwnsTransitionSnapshotBeforeCompleted() throws {
    var receivedRequest: AppshotCaptureRequest?
    let screenshotURL = URL(
        fileURLWithPath: "/tmp/com.openai.sky.CUAService/finder-final.png"
    )
    let transitionURL = URL(
        fileURLWithPath: "/tmp/com.openai.sky.CUAService/finder-transition.png"
    )
    let probe = AppshotProtocolProbe { request in
        receivedRequest = request
        return AppshotCapturePayload(
            screenshotURL: screenshotURL,
            accessibilityText: "Finder accessibility content",
            transitionSnapshotURL: transitionURL,
            transitionSnapshotHeight: 322
        )
    }

    let startReply = try #require(
        JSONSerialization.jsonObject(
            with: probe.handle(
                requestType: "ComputerUseIPCAppStartCaptureRequest",
                requestJSON: Data(
                    #"{"requestId":"request-transition","app":"com.apple.finder","animationTarget":{"codexDisplay":{"scaleFactor":2},"destinationFrame":{"width":464,"height":280,"x":100,"y":200},"destinationPrimaryTextColor":{"red":17,"green":34,"blue":51}},"version":2}"#.utf8
                )
            )
        ) as? [String: Any]
    )

    #expect(startReply["result"] as? String == "started")
    #expect(startReply["transitionSnapshotHeight"] as? Double == 322)
    #expect(receivedRequest?.requestID == "request-transition")
    #expect(receivedRequest?.bundleIdentifier == "com.apple.finder")
    #expect(receivedRequest?.animationTarget?.destinationFrameWidth == 464)
    #expect(receivedRequest?.animationTarget?.displayScaleFactor == 2)
    #expect(
        receivedRequest?.animationTarget?.destinationPrimaryTextColor
            == AppshotRGBColor(red: 17, green: 34, blue: 51)
    )

    let nextRequest = Data(#"{"requestId":"request-transition"}"#.utf8)
    let updates = try (0..<4).map { _ in
        try #require(
            JSONSerialization.jsonObject(
                with: probe.handle(
                    requestType: "ComputerUseIPCAppNextCaptureUpdateRequest",
                    requestJSON: nextRequest
                )
            ) as? [String: Any]
        )
    }

    #expect(updates.map { $0["type"] as? String } == [
        "metadata", "axText", "screenshot", "completed"
    ])
    #expect(updates[2]["screenshotURL"] as? String == screenshotURL.absoluteString)
    #expect(
        updates[2]["transitionSnapshotURL"] as? String
            == transitionURL.absoluteString
    )
    #expect(updates[3]["transitionSnapshotURL"] == nil)
}
