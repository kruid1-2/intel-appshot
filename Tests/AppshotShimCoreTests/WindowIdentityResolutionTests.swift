import ApplicationServices
import CoreGraphics
import Testing
@testable import AppshotShimCore

@Test("AX window compatibility reports a missing private symbol")
func axWindowCompatibilityReportsMissingSymbol() throws {
    let compatibility = AXWindowIDCompatibility(symbolLookup: { _ in nil })
    let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)

    #expect(throws: AXWindowIDCompatibilityError.symbolUnavailable) {
        _ = try compatibility.windowID(for: application)
    }
}

@Test("strict fallback selects the sole PID and bounds candidate")
func strictFallbackSelectsUniqueCandidate() throws {
    let requestedBounds = CGRect(x: 40, y: 80, width: 1200, height: 800)
    let candidates = [
        WindowIdentityCandidate(
            windowID: 10,
            ownerProcessIdentifier: 1342,
            bounds: requestedBounds,
            layer: 0
        ),
        WindowIdentityCandidate(
            windowID: 11,
            ownerProcessIdentifier: 999,
            bounds: requestedBounds,
            layer: 0
        )
    ]

    let match = try StrictWindowIdentityMatcher.match(
        processIdentifier: 1342,
        accessibilityBounds: requestedBounds,
        candidates: candidates
    )

    #expect(match == 10)
}

@Test("strict fallback rejects ambiguous PID and bounds candidates")
func strictFallbackRejectsAmbiguousCandidates() {
    let requestedBounds = CGRect(x: 40, y: 80, width: 1200, height: 800)
    let candidates = [10, 11].map {
        WindowIdentityCandidate(
            windowID: CGWindowID($0),
            ownerProcessIdentifier: 1342,
            bounds: requestedBounds,
            layer: 0
        )
    }

    #expect(throws: StrictWindowIdentityMatchError.ambiguous(candidateCount: 2)) {
        _ = try StrictWindowIdentityMatcher.match(
            processIdentifier: 1342,
            accessibilityBounds: requestedBounds,
            candidates: candidates
        )
    }
}

@Test("strict fallback rejects a bounds mismatch")
func strictFallbackRejectsBoundsMismatch() {
    let candidate = WindowIdentityCandidate(
        windowID: 10,
        ownerProcessIdentifier: 1342,
        bounds: CGRect(x: 41, y: 80, width: 1200, height: 800),
        layer: 0
    )

    #expect(throws: StrictWindowIdentityMatchError.noUniqueCandidate) {
        _ = try StrictWindowIdentityMatcher.match(
            processIdentifier: 1342,
            accessibilityBounds: CGRect(x: 40, y: 80, width: 1200, height: 800),
            candidates: [candidate]
        )
    }
}

@Test("shareable window matching requires both window ID and owner PID")
func shareableWindowMatchingRequiresWindowAndOwnerIdentity() throws {
    let candidates = [
        ShareableWindowIdentity(windowID: 90, ownerProcessIdentifier: 1342),
        ShareableWindowIdentity(windowID: 91, ownerProcessIdentifier: 1342),
        ShareableWindowIdentity(windowID: 90, ownerProcessIdentifier: 999)
    ]

    let index = try ShareableWindowIdentityMatcher.matchIndex(
        windowID: 90,
        processIdentifier: 1342,
        candidates: candidates
    )

    #expect(index == 0)
}

@Test("shareable window matching rejects duplicate exact identities")
func shareableWindowMatchingRejectsDuplicates() {
    let candidates = [
        ShareableWindowIdentity(windowID: 90, ownerProcessIdentifier: 1342),
        ShareableWindowIdentity(windowID: 90, ownerProcessIdentifier: 1342)
    ]

    #expect(throws: ShareableWindowIdentityMatchError.ambiguous(candidateCount: 2)) {
        _ = try ShareableWindowIdentityMatcher.matchIndex(
            windowID: 90,
            processIdentifier: 1342,
            candidates: candidates
        )
    }
}

@Test("AX window resolver uses the strict fallback when the private symbol is missing")
func axWindowResolverUsesStrictFallback() throws {
    let bounds = CGRect(x: 40, y: 80, width: 1200, height: 800)
    let window = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    let resolver = AXWindowIDResolver(
        compatibility: AXWindowIDCompatibility(symbolLookup: { _ in nil }),
        accessibilityBounds: { _ in bounds },
        windowCandidates: {
            [
                WindowIdentityCandidate(
                    windowID: 77,
                    ownerProcessIdentifier: 1342,
                    bounds: bounds,
                    layer: 0
                )
            ]
        }
    )

    let resolution = try resolver.resolve(window: window, processIdentifier: 1342)

    #expect(resolution.windowID == 77)
    #expect(resolution.method == .strictPIDAndBoundsFallback)
}

@Test("AX window resolver reports both direct and fallback failures")
func axWindowResolverReportsFallbackFailure() {
    let window = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
    let resolver = AXWindowIDResolver(
        compatibility: AXWindowIDCompatibility(symbolLookup: { _ in nil }),
        accessibilityBounds: { _ in CGRect(x: 0, y: 0, width: 900, height: 600) },
        windowCandidates: { [] }
    )

    #expect(throws: AXWindowIDResolutionError.self) {
        _ = try resolver.resolve(window: window, processIdentifier: 1342)
    }
}
