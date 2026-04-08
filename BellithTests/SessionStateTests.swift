import XCTest
@testable import Bellith

final class SessionStateTests: XCTestCase {
    func testLeafEncodeDecode() throws {
        let leaf = SplitNodeState.leaf(cwd: "/Users/test/projects")
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .leaf(let cwd) = decoded {
            XCTAssertEqual(cwd, "/Users/test/projects")
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testLeafWithNilCwd() throws {
        let leaf = SplitNodeState.leaf(cwd: nil)
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .leaf(let cwd) = decoded {
            XCTAssertNil(cwd)
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testBranchEncodeDecode() throws {
        let branch = SplitNodeState.branch(
            orientation: "horizontal",
            ratio: 0.5,
            first: .leaf(cwd: "/tmp"),
            second: .leaf(cwd: "/home")
        )
        let data = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .branch(let orientation, let ratio, let first, let second) = decoded {
            XCTAssertEqual(orientation, "horizontal")
            XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
            if case .leaf(let cwd1) = first { XCTAssertEqual(cwd1, "/tmp") }
            else { XCTFail("Expected leaf for first child") }
            if case .leaf(let cwd2) = second { XCTAssertEqual(cwd2, "/home") }
            else { XCTFail("Expected leaf for second child") }
        } else {
            XCTFail("Expected branch node")
        }
    }

    func testNestedBranchEncodeDecode() throws {
        let tree = SplitNodeState.branch(
            orientation: "vertical",
            ratio: 0.6,
            first: .branch(
                orientation: "horizontal",
                ratio: 0.5,
                first: .leaf(cwd: "/a"),
                second: .leaf(cwd: "/b")
            ),
            second: .leaf(cwd: "/c")
        )
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .branch(_, _, let first, _) = decoded {
            if case .branch(_, _, let innerFirst, _) = first {
                if case .leaf(let cwd) = innerFirst {
                    XCTAssertEqual(cwd, "/a")
                } else { XCTFail("Expected leaf") }
            } else { XCTFail("Expected nested branch") }
        } else { XCTFail("Expected branch") }
    }

    func testSessionStateMultiTabRoundtrip() throws {
        let context = TerminalContext(
            source: .sshProfile,
            host: "prod.example.com",
            user: "deploy",
            environmentTag: "prod",
            isSensitive: true,
            sshProfileID: UUID()
        )
        let state = SessionState(
            tabs: [
                SessionState.TabState(title: "Tab 1", splitTree: .leaf(cwd: "/home"), terminalContext: context, sshProfileID: context.sshProfileID),
                SessionState.TabState(title: "Inspector", smartPanelID: "performance"),
                SessionState.TabState(title: "Tab 2", splitTree: .branch(
                    orientation: "horizontal", ratio: 0.5,
                    first: .leaf(cwd: "/tmp"), second: .leaf(cwd: nil)
                )),
            ],
            selectedTabIndex: 1
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        XCTAssertEqual(decoded.tabs.count, 3)
        XCTAssertEqual(decoded.selectedTabIndex, 1)
        XCTAssertEqual(decoded.tabs[0].title, "Tab 1")
        XCTAssertEqual(decoded.tabs[0].terminalContext, context)
        XCTAssertEqual(decoded.tabs[0].sshProfileID, context.sshProfileID)
        XCTAssertEqual(decoded.tabs[1].title, "Inspector")
        XCTAssertEqual(decoded.tabs[1].kind, .smart)
        XCTAssertEqual(decoded.tabs[1].smartPanelID, "performance")
        XCTAssertEqual(decoded.tabs[2].title, "Tab 2")
    }

    func testWindowSessionStateRoundtrip() throws {
        let windowState = WindowSessionState(
            session: SessionState(
                tabs: [SessionState.TabState(title: "Tab 1", splitTree: .leaf(cwd: "/tmp"))],
                selectedTabIndex: 0
            ),
            frameDescriptor: "{{10, 20}, {900, 600}}"
        )

        let data = try JSONEncoder().encode(windowState)
        let decoded = try JSONDecoder().decode(WindowSessionState.self, from: data)

        XCTAssertEqual(decoded.session.tabs.count, 1)
        XCTAssertEqual(decoded.frameDescriptor, "{{10, 20}, {900, 600}}")
    }
}
