import AppKit
import XCTest
@testable import Bellith

final class SplitPaneViewTests: XCTestCase {
    func testSplitCreatesBranchWithTwoLeaves() {
        let firstView = NSView()
        let secondView = NSView()
        let root = SplitPaneView(content: firstView)

        let newLeaf = root.split(orientation: .vertical, newContent: secondView)

        XCTAssertFalse(root.isLeaf)
        XCTAssertEqual(root.allLeaves.count, 2)
        XCTAssertTrue(root.allLeaves.contains { $0 === firstView })
        XCTAssertTrue(root.allLeaves.contains { $0 === secondView })
        XCTAssertTrue(newLeaf.contentView === secondView)
    }

    func testRemoveChildCollapsesBranchBackToLeaf() {
        let firstView = NSView()
        let secondView = NSView()
        let root = SplitPaneView(content: firstView)
        _ = root.split(orientation: .vertical, newContent: secondView)

        guard let secondLeaf = root.leaf(containing: secondView) else {
            return XCTFail("Expected to find the second split leaf")
        }

        root.removeChild(secondLeaf)

        XCTAssertTrue(root.isLeaf)
        XCTAssertTrue(root.contentView === firstView)
        XCTAssertEqual(root.allLeaves.count, 1)
    }

    func testAdjacentLeafFindsSiblingAcrossVerticalSplit() {
        let leftView = NSView()
        let rightView = NSView()
        let root = SplitPaneView(content: leftView)
        _ = root.split(orientation: .vertical, newContent: rightView)

        XCTAssertTrue(root.adjacentLeaf(from: leftView, direction: .right) === rightView)
        XCTAssertTrue(root.adjacentLeaf(from: rightView, direction: .left) === leftView)
    }

    func testAdjustRatioClampsToBounds() {
        let root = SplitPaneView(content: NSView())
        _ = root.split(orientation: .horizontal, newContent: NSView())

        root.adjustRatio(by: 10)
        XCTAssertEqual(root.currentRatio, 0.85, accuracy: 0.0001)

        root.adjustRatio(by: -10)
        XCTAssertEqual(root.currentRatio, 0.15, accuracy: 0.0001)
    }

    func testSerializeProducesNestedBranchState() {
        let firstView = NSView()
        let secondView = NSView()
        let thirdView = NSView()
        let root = SplitPaneView(content: firstView)
        let secondLeaf = root.split(orientation: .vertical, newContent: secondView)
        _ = secondLeaf.split(orientation: .horizontal, newContent: thirdView)

        let serialized = root.serialize { view in
            if view === firstView { return "/one" }
            if view === secondView { return "/two" }
            if view === thirdView { return "/three" }
            return nil
        }

        guard case .branch(let orientation, _, let first, let second) = serialized else {
            return XCTFail("Expected a branch root state")
        }
        XCTAssertEqual(orientation, "vertical")

        guard case .leaf(let firstCwd) = first else {
            return XCTFail("Expected first child leaf")
        }
        XCTAssertEqual(firstCwd, "/one")

        guard case .branch(let nestedOrientation, _, let nestedFirst, let nestedSecond) = second else {
            return XCTFail("Expected nested branch")
        }
        XCTAssertEqual(nestedOrientation, "horizontal")

        guard case .leaf(let nestedFirstCwd) = nestedFirst else {
            return XCTFail("Expected nested first leaf")
        }
        XCTAssertEqual(nestedFirstCwd, "/two")

        guard case .leaf(let nestedSecondCwd) = nestedSecond else {
            return XCTFail("Expected nested second leaf")
        }
        XCTAssertEqual(nestedSecondCwd, "/three")
    }
}
