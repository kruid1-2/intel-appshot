import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

enum AXWindowIDCompatibilityError: Error, Equatable {
    case symbolUnavailable
    case callFailed(AXError)
    case invalidWindowID
}

final class AXWindowIDCompatibility {
    typealias SymbolLookup = (String) -> UnsafeMutableRawPointer?
    private typealias AXUIElementGetWindowFunction = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private let function: AXUIElementGetWindowFunction?

    init(symbolLookup: @escaping SymbolLookup = AXWindowIDCompatibility.defaultSymbolLookup) {
        function = symbolLookup("_AXUIElementGetWindow").map {
            unsafeBitCast($0, to: AXUIElementGetWindowFunction.self)
        }
    }

    func windowID(for window: AXUIElement) throws -> CGWindowID {
        guard let function else {
            throw AXWindowIDCompatibilityError.symbolUnavailable
        }
        var windowID: CGWindowID = 0
        let error = function(window, &windowID)
        guard error == .success else {
            throw AXWindowIDCompatibilityError.callFailed(error)
        }
        guard windowID != 0 else {
            throw AXWindowIDCompatibilityError.invalidWindowID
        }
        return windowID
    }

    private static func defaultSymbolLookup(_ name: String) -> UnsafeMutableRawPointer? {
        guard let processImageHandle = dlopen(nil, RTLD_LAZY | RTLD_LOCAL) else {
            return nil
        }
        defer { dlclose(processImageHandle) }
        return name.withCString { dlsym(processImageHandle, $0) }
    }
}
