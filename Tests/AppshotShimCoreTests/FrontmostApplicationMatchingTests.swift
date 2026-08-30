import Testing
@testable import AppshotShimCore

@Test("frontmost application matcher accepts an exact bundle identifier")
func frontmostApplicationMatcherAcceptsExactBundleIdentifier() throws {
    try FrontmostApplicationBundleMatcher.validate(
        requestedBundleIdentifier: "com.apple.finder",
        frontmostBundleIdentifier: "com.apple.finder"
    )
}

@Test("frontmost application matcher rejects a different bundle identifier")
func frontmostApplicationMatcherRejectsDifferentBundleIdentifier() {
    do {
        try FrontmostApplicationBundleMatcher.validate(
            requestedBundleIdentifier: "com.apple.Safari",
            frontmostBundleIdentifier: "com.apple.finder"
        )
        Issue.record("a mismatched frontmost application was accepted")
    } catch let error as FrontmostAccessibilitySnapshotError {
        guard case let .frontmostApplicationMismatch(expected, actual) = error else {
            Issue.record("unexpected error: \(error)")
            return
        }
        #expect(expected == "com.apple.Safari")
        #expect(actual == "com.apple.finder")
    } catch {
        Issue.record("unexpected error type: \(error)")
    }
}

@Test("frontmost application matcher rejects a missing bundle identifier")
func frontmostApplicationMatcherRejectsMissingBundleIdentifier() {
    do {
        try FrontmostApplicationBundleMatcher.validate(
            requestedBundleIdentifier: "com.apple.dt.Xcode",
            frontmostBundleIdentifier: nil
        )
        Issue.record("a frontmost application without a bundle identifier was accepted")
    } catch let error as FrontmostAccessibilitySnapshotError {
        guard case let .frontmostApplicationMismatch(expected, actual) = error else {
            Issue.record("unexpected error: \(error)")
            return
        }
        #expect(expected == "com.apple.dt.Xcode")
        #expect(actual == nil)
    } catch {
        Issue.record("unexpected error type: \(error)")
    }
}
