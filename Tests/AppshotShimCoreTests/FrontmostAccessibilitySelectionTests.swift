import ApplicationServices
import Testing
@testable import AppshotShimCore

@Test("lightweight AX window selection builds the unchanged full snapshot header later")
func accessibilityWindowSelectionBuildsSnapshotLater() {
    let window = AXUIElementCreateApplication(42)
    let selection = FrontmostAccessibilityWindowSelection(
        applicationName: "Safari",
        bundleIdentifier: "com.apple.Safari",
        processIdentifier: 42,
        windowTitle: "Example",
        windowElement: window
    )
    let traversal = AccessibilityTreeTraversalResult(
        text: "[AXWindow] title=\"Example\"",
        nodeCount: 7,
        wasTruncated: false
    )

    let snapshot = selection.snapshot(
        traversal: traversal,
        durationMilliseconds: 123
    )

    #expect(snapshot.applicationName == "Safari")
    #expect(snapshot.windowTitle == "Example")
    #expect(snapshot.nodeCount == 7)
    #expect(snapshot.durationMilliseconds == 123)
    #expect(snapshot.accessibilityText == """
        Application: Safari
        Bundle Identifier: com.apple.Safari
        PID: 42
        Window: Example
        AX Nodes: 7
        Accessibility Tree:
        [AXWindow] title="Example"
        """)
}
