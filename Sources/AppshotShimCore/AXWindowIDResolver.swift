import ApplicationServices
import CoreGraphics
import Foundation

enum AXWindowIDResolutionMethod: String {
    case privateAXUIElementGetWindow
    case strictPIDAndBoundsFallback
}

struct AXWindowIDResolution {
    let windowID: CGWindowID
    let method: AXWindowIDResolutionMethod
}

enum AXWindowIDResolutionError: Error, CustomStringConvertible {
    case accessibilityBoundsUnavailable
    case windowListUnavailable
    case unableToMap(
        directError: AXWindowIDCompatibilityError,
        fallbackError: StrictWindowIdentityMatchError
    )

    var description: String {
        switch self {
        case .accessibilityBoundsUnavailable:
            return "could not read exact AX window position and size"
        case .windowListUnavailable:
            return "CGWindowListCopyWindowInfo did not return a window list"
        case let .unableToMap(directError, fallbackError):
            return "could not map AX window to CGWindowID "
                + "(private API: \(directError); strict fallback: \(fallbackError))"
        }
    }
}

final class AXWindowIDResolver {
    typealias AccessibilityBoundsProvider = (AXUIElement) throws -> CGRect
    typealias WindowCandidatesProvider = () throws -> [WindowIdentityCandidate]

    private let compatibility: AXWindowIDCompatibility
    private let accessibilityBounds: AccessibilityBoundsProvider
    private let windowCandidates: WindowCandidatesProvider

    init(
        compatibility: AXWindowIDCompatibility = AXWindowIDCompatibility(),
        accessibilityBounds: @escaping AccessibilityBoundsProvider = AXWindowIDResolver.copyBounds,
        windowCandidates: @escaping WindowCandidatesProvider = AXWindowIDResolver.copyWindowCandidates
    ) {
        self.compatibility = compatibility
        self.accessibilityBounds = accessibilityBounds
        self.windowCandidates = windowCandidates
    }

    func resolve(
        window: AXUIElement,
        processIdentifier: pid_t
    ) throws -> AXWindowIDResolution {
        do {
            return AXWindowIDResolution(
                windowID: try compatibility.windowID(for: window),
                method: .privateAXUIElementGetWindow
            )
        } catch let directError as AXWindowIDCompatibilityError {
            let bounds = try accessibilityBounds(window)
            do {
                return AXWindowIDResolution(
                    windowID: try StrictWindowIdentityMatcher.match(
                        processIdentifier: processIdentifier,
                        accessibilityBounds: bounds,
                        candidates: try windowCandidates()
                    ),
                    method: .strictPIDAndBoundsFallback
                )
            } catch let fallbackError as StrictWindowIdentityMatchError {
                throw AXWindowIDResolutionError.unableToMap(
                    directError: directError,
                    fallbackError: fallbackError
                )
            }
        }
    }

    private static func copyBounds(from window: AXUIElement) throws -> CGRect {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                &positionValue
            ) == .success,
            AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            throw AXWindowIDResolutionError.accessibilityBoundsUnavailable
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            throw AXWindowIDResolutionError.accessibilityBoundsUnavailable
        }
        return CGRect(origin: position, size: size)
    }

    private static func copyWindowCandidates() throws -> [WindowIdentityCandidate] {
        guard let rawWindowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw AXWindowIDResolutionError.windowListUnavailable
        }

        return rawWindowList.compactMap { entry in
            guard
                let windowNumber = entry[kCGWindowNumber as String] as? NSNumber,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = entry[kCGWindowLayer as String] as? NSNumber,
                let boundsValue = entry[kCGWindowBounds as String],
                CFGetTypeID(boundsValue as CFTypeRef) == CFDictionaryGetTypeID(),
                let bounds = CGRect(
                    dictionaryRepresentation: boundsValue as! CFDictionary
                )
            else {
                return nil
            }
            return WindowIdentityCandidate(
                windowID: CGWindowID(windowNumber.uint32Value),
                ownerProcessIdentifier: pid_t(ownerPID.int32Value),
                bounds: bounds,
                layer: layer.intValue
            )
        }
    }
}
