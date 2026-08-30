import AppKit
import Foundation

public final class AppshotAppleEventBridge: NSObject {
    public static let eventClass = AEEventClass(0x536B4375) // SkCu
    public static let eventID = AEEventID(0x536E6452) // SndR

    private static let requestTypeKeyword = AEKeyword(0x52737054) // RspT
    private static let requestDataKeyword = AEKeyword(0x52657144) // ReqD
    private static let clientVersionKeyword = AEKeyword(0x436C566E) // ClVn
    private static let clientVersion = "CodexComputerUseNativeBridge-1"

    private let protocolProbe: AppshotProtocolProbe

    public init(protocolProbe: AppshotProtocolProbe) {
        self.protocolProbe = protocolProbe
        super.init()
    }

    @objc public func handleAppleEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        do {
            guard
                event.paramDescriptor(forKeyword: Self.clientVersionKeyword)?.stringValue
                    == Self.clientVersion,
                let requestType = event.paramDescriptor(
                    forKeyword: Self.requestTypeKeyword
                )?.stringValue,
                let requestData = event.paramDescriptor(
                    forKeyword: Self.requestDataKeyword
                )?.data
            else {
                throw AppshotProtocolProbeError.invalidRequest
            }

            let response = try protocolProbe.handle(
                requestType: requestType,
                requestJSON: requestData
            )
            guard let descriptor = NSAppleEventDescriptor(
                descriptorType: DescType(typeData),
                data: response
            ) else {
                throw AppshotProtocolProbeError.invalidRequest
            }
            replyEvent.setParam(descriptor, forKeyword: keyDirectObject)
        } catch {
            replyEvent.setParam(
                NSAppleEventDescriptor(int32: -1708),
                forKeyword: keyErrorNumber
            )
            replyEvent.setParam(
                NSAppleEventDescriptor(string: String(describing: error)),
                forKeyword: keyErrorString
            )
        }
    }
}
