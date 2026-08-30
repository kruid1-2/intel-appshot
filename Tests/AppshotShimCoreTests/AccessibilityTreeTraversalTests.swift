import Testing
@testable import AppshotShimCore

@Test("accessibility traversal visits cyclic elements only once")
func accessibilityTraversalAvoidsCycles() {
    let children = [
        1: [2],
        2: [1, 3],
        3: []
    ]
    let traversal = AccessibilityTreeTraversal<Int>(
        maximumDepth: 10,
        maximumNodeCount: 10,
        describe: { "node \($0)" },
        children: { children[$0, default: []] }
    )

    let result = traversal.render(root: 1)

    #expect(result.text == "node 1\n  node 2\n    node 3")
    #expect(result.nodeCount == 3)
    #expect(!result.wasTruncated)
}

@Test("accessibility traversal stops below the maximum depth")
func accessibilityTraversalHonorsMaximumDepth() {
    let children = [
        1: [2],
        2: [3],
        3: [4],
        4: []
    ]
    let traversal = AccessibilityTreeTraversal<Int>(
        maximumDepth: 1,
        maximumNodeCount: 10,
        describe: { "node \($0)" },
        children: { children[$0, default: []] }
    )

    let result = traversal.render(root: 1)

    #expect(result.text == "node 1\n  node 2")
    #expect(result.nodeCount == 2)
    #expect(result.wasTruncated)
}

@Test("accessibility traversal stops at the maximum node count")
func accessibilityTraversalHonorsMaximumNodeCount() {
    let children = [
        1: [2, 3, 4],
        2: [],
        3: [],
        4: []
    ]
    let traversal = AccessibilityTreeTraversal<Int>(
        maximumDepth: 10,
        maximumNodeCount: 2,
        describe: { "node \($0)" },
        children: { children[$0, default: []] }
    )

    let result = traversal.render(root: 1)

    #expect(result.text == "node 1\n  node 2")
    #expect(result.nodeCount == 2)
    #expect(result.wasTruncated)
}

@Test("accessibility traversal loads one snapshot per unique element")
func accessibilityTraversalLoadsEachSnapshotOnce() {
    let children = [
        1: [2],
        2: [1, 3],
        3: []
    ]
    var loadCounts: [Int: Int] = [:]
    let traversal = AccessibilityTreeTraversal<Int>(
        maximumDepth: 10,
        maximumNodeCount: 10,
        snapshot: { element in
            loadCounts[element, default: 0] += 1
            return AccessibilityTreeNode(
                description: "node \(element)",
                children: children[element, default: []]
            )
        }
    )

    let result = traversal.render(root: 1)

    #expect(result.nodeCount == 3)
    #expect(loadCounts == [1: 1, 2: 1, 3: 1])
}
