import AppKit
import ApplicationServices
import Foundation

public struct MusicAccessibilitySnapshot {
    public let applicationName: String
    public let bundleIdentifier: String
    public let processIdentifier: pid_t
    public let windowTitle: String
    public let accessibilityText: String
    public let nodeCount: Int
    public let wasTruncated: Bool
    public let durationMilliseconds: Int
}

public enum MusicAccessibilitySnapshotError: Error, CustomStringConvertible {
    case accessibilityPermissionDenied
    case frontmostApplicationUnavailable
    case requestedApplicationUnsupported(String)
    case frontmostApplicationMismatch(expected: String, actual: String?)
    case focusedAndMainWindowUnavailable(focusedError: AXError, mainError: AXError)

    public var description: String {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is not granted to Codex Computer Use"
        case .frontmostApplicationUnavailable:
            return "macOS did not report a frontmost application"
        case let .requestedApplicationUnsupported(bundleIdentifier):
            return "requested application is not Music: \(bundleIdentifier)"
        case let .frontmostApplicationMismatch(expected, actual):
            let actualBundleIdentifier = actual ?? "unknown"
            return "frontmost application mismatch: expected \(expected), got \(actualBundleIdentifier)"
        case let .focusedAndMainWindowUnavailable(focusedError, mainError):
            return "Music has no focused or main AX window (focused=\(focusedError.rawValue), main=\(mainError.rawValue))"
        }
    }
}

public final class MusicAccessibilitySnapshotProvider {
    public static let musicBundleIdentifier = "com.apple.Music"

    private let maximumDepth: Int
    private let maximumNodeCount: Int

    public init(maximumDepth: Int = 30, maximumNodeCount: Int = 1_200) {
        self.maximumDepth = maximumDepth
        self.maximumNodeCount = maximumNodeCount
    }

    public func capture(requestedBundleIdentifier: String) throws -> MusicAccessibilitySnapshot {
        let startedAt = CFAbsoluteTimeGetCurrent()

        guard requestedBundleIdentifier == Self.musicBundleIdentifier else {
            throw MusicAccessibilitySnapshotError.requestedApplicationUnsupported(
                requestedBundleIdentifier
            )
        }
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            throw MusicAccessibilitySnapshotError.frontmostApplicationUnavailable
        }
        guard frontmostApplication.bundleIdentifier == requestedBundleIdentifier else {
            throw MusicAccessibilitySnapshotError.frontmostApplicationMismatch(
                expected: requestedBundleIdentifier,
                actual: frontmostApplication.bundleIdentifier
            )
        }

        guard AXIsProcessTrusted() else {
            throw MusicAccessibilitySnapshotError.accessibilityPermissionDenied
        }

        let processIdentifier = frontmostApplication.processIdentifier
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let focusedWindow = copyElement(
            from: applicationElement,
            attribute: kAXFocusedWindowAttribute as CFString
        )
        let mainWindow = focusedWindow.element == nil
            ? copyElement(
                from: applicationElement,
                attribute: kAXMainWindowAttribute as CFString
            )
            : (nil, AXError.success)

        guard let window = focusedWindow.element ?? mainWindow.0 else {
            throw MusicAccessibilitySnapshotError.focusedAndMainWindowUnavailable(
                focusedError: focusedWindow.error,
                mainError: mainWindow.1
            )
        }

        let traversal = AccessibilityTreeTraversal<AXUIElement>(
            maximumDepth: maximumDepth,
            maximumNodeCount: maximumNodeCount,
            snapshot: { [self] element in treeNode(for: element) }
        )
        let result = traversal.render(root: window)
        let applicationName = frontmostApplication.localizedName ?? "Music"
        let windowTitle = stringValue(
            of: window,
            attribute: kAXTitleAttribute as CFString
        ) ?? ""
        let durationMilliseconds = Int(
            ((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000).rounded()
        )
        let displayedWindowTitle = windowTitle.isEmpty ? "(untitled)" : windowTitle
        let truncationSuffix = result.wasTruncated ? " (truncated)" : ""
        let header = [
            "Application: \(applicationName)",
            "Bundle Identifier: \(requestedBundleIdentifier)",
            "PID: \(processIdentifier)",
            "Window: \(displayedWindowTitle)",
            "AX Nodes: \(result.nodeCount)\(truncationSuffix)",
            "Accessibility Tree:"
        ]

        return MusicAccessibilitySnapshot(
            applicationName: applicationName,
            bundleIdentifier: requestedBundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitle: windowTitle,
            accessibilityText: (header + [result.text]).joined(separator: "\n"),
            nodeCount: result.nodeCount,
            wasTruncated: result.wasTruncated,
            durationMilliseconds: durationMilliseconds
        )
    }

    private func copyElement(
        from parent: AXUIElement,
        attribute: CFString
    ) -> (element: AXUIElement?, error: AXError) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(parent, attribute, &value)
        guard
            error == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return (nil, error)
        }
        return ((value as! AXUIElement), error)
    }

    private func treeNode(for element: AXUIElement) -> AccessibilityTreeNode<AXUIElement> {
        let attributes: [CFString] = [
            kAXRoleAttribute as CFString,
            kAXSubroleAttribute as CFString,
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXValueAttribute as CFString,
            kAXHelpAttribute as CFString,
            kAXIdentifierAttribute as CFString,
            kAXEnabledAttribute as CFString,
            kAXFocusedAttribute as CFString,
            kAXSelectedAttribute as CFString,
            kAXVisibleChildrenAttribute as CFString,
            kAXChildrenAttribute as CFString
        ]
        var copiedValues: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            [],
            &copiedValues
        )
        guard error == .success, let copiedValues else {
            return AccessibilityTreeNode(description: "[AXUnknown]", children: [])
        }

        let values = copiedValues as NSArray
        func value(at index: Int) -> Any? {
            guard index < values.count else { return nil }
            let value = values[index]
            guard !(value is NSNull) else { return nil }
            if CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID(),
               AXValueGetType(value as! AXValue) == .axError {
                return nil
            }
            return value
        }

        let role = stringValue(from: value(at: 0)) ?? "AXUnknown"
        let stringAttributes: [(String, Int)] = [
            ("subrole", 1),
            ("title", 2),
            ("description", 3),
            ("value", 4),
            ("help", 5),
            ("identifier", 6)
        ]
        let booleanAttributes: [(String, Int)] = [
            ("enabled", 7),
            ("focused", 8),
            ("selected", 9)
        ]
        var fragments = stringAttributes.compactMap { label, index -> String? in
            guard let value = stringValue(from: value(at: index)) else { return nil }
            return "\(label)=\"\(escaped(value))\""
        }
        fragments.append(contentsOf: booleanAttributes.compactMap { label, index in
            guard let value = booleanValue(from: value(at: index)) else { return nil }
            return "\(label)=\(value)"
        })

        let visibleChildren = elementArray(from: value(at: 10))
        let allChildren = elementArray(from: value(at: 11)) ?? []
        return AccessibilityTreeNode(
            description: (["[\(role)]"] + fragments).joined(separator: " "),
            children: visibleChildren ?? allChildren
        )
    }

    private func stringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value
        else {
            return nil
        }

        return stringValue(from: value)
    }

    private func stringValue(from value: Any?) -> String? {
        let string: String?
        if let plainString = value as? String {
            string = plainString
        } else if let attributedString = value as? NSAttributedString {
            string = attributedString.string
        } else if let number = value as? NSNumber {
            string = number.stringValue
        } else {
            string = nil
        }
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > 1_000 {
            return String(trimmed.prefix(1_000)) + "…"
        }
        return trimmed
    }

    private func booleanValue(from value: Any?) -> Bool? {
        guard let number = value as? NSNumber else { return nil }
        return number.boolValue
    }

    private func elementArray(from value: Any?) -> [AXUIElement]? {
        guard let value else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == CFArrayGetTypeID() else { return nil }
        return value as? [AXUIElement]
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
