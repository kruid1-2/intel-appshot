import Foundation

struct AccessibilityTreeTraversalResult {
    let text: String
    let nodeCount: Int
    let wasTruncated: Bool
}

struct AccessibilityTreeNode<Element> {
    let description: String
    let children: [Element]
}

struct AccessibilityTreeTraversal<Element: Hashable> {
    let maximumDepth: Int
    let maximumNodeCount: Int
    let snapshot: (Element) -> AccessibilityTreeNode<Element>

    init(
        maximumDepth: Int,
        maximumNodeCount: Int,
        describe: @escaping (Element) -> String,
        children: @escaping (Element) -> [Element]
    ) {
        self.init(
            maximumDepth: maximumDepth,
            maximumNodeCount: maximumNodeCount,
            snapshot: { element in
                AccessibilityTreeNode(
                    description: describe(element),
                    children: children(element)
                )
            }
        )
    }

    init(
        maximumDepth: Int,
        maximumNodeCount: Int,
        snapshot: @escaping (Element) -> AccessibilityTreeNode<Element>
    ) {
        self.maximumDepth = maximumDepth
        self.maximumNodeCount = maximumNodeCount
        self.snapshot = snapshot
    }

    func render(root: Element) -> AccessibilityTreeTraversalResult {
        var visited: Set<Element> = []
        var lines: [String] = []
        var wasTruncated = false

        func visit(_ element: Element, depth: Int) {
            guard !visited.contains(element) else { return }
            guard visited.count < maximumNodeCount else {
                wasTruncated = true
                return
            }
            visited.insert(element)
            let elementSnapshot = snapshot(element)
            lines.append(
                String(repeating: "  ", count: depth) + elementSnapshot.description
            )
            let childElements = elementSnapshot.children
            guard depth < maximumDepth else {
                if !childElements.isEmpty {
                    wasTruncated = true
                }
                return
            }
            for child in childElements {
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return AccessibilityTreeTraversalResult(
            text: lines.joined(separator: "\n"),
            nodeCount: visited.count,
            wasTruncated: wasTruncated
        )
    }
}
