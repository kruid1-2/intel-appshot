import CoreGraphics
import Foundation

struct WindowIdentityCandidate {
    let windowID: CGWindowID
    let ownerProcessIdentifier: pid_t
    let bounds: CGRect
    let layer: Int
}

enum StrictWindowIdentityMatchError: Error, Equatable {
    case noUniqueCandidate
    case ambiguous(candidateCount: Int)
}

enum StrictWindowIdentityMatcher {
    static func match(
        processIdentifier: pid_t,
        accessibilityBounds: CGRect,
        candidates: [WindowIdentityCandidate]
    ) throws -> CGWindowID {
        let matches = candidates.filter {
            $0.ownerProcessIdentifier == processIdentifier
                && $0.layer == 0
                && $0.bounds == accessibilityBounds
        }
        guard matches.count == 1 else {
            if matches.count > 1 {
                throw StrictWindowIdentityMatchError.ambiguous(
                    candidateCount: matches.count
                )
            }
            throw StrictWindowIdentityMatchError.noUniqueCandidate
        }
        return matches[0].windowID
    }
}

struct ShareableWindowIdentity {
    let windowID: CGWindowID
    let ownerProcessIdentifier: pid_t
}

enum ShareableWindowIdentityMatchError: Error, Equatable {
    case noUniqueCandidate
    case ambiguous(candidateCount: Int)
}

enum ShareableWindowIdentityMatcher {
    static func matchIndex(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        candidates: [ShareableWindowIdentity]
    ) throws -> Int {
        let matches = candidates.indices.filter {
            candidates[$0].windowID == windowID
                && candidates[$0].ownerProcessIdentifier == processIdentifier
        }
        guard matches.count == 1 else {
            if matches.count > 1 {
                throw ShareableWindowIdentityMatchError.ambiguous(
                    candidateCount: matches.count
                )
            }
            throw ShareableWindowIdentityMatchError.noUniqueCandidate
        }
        return matches[0]
    }
}
