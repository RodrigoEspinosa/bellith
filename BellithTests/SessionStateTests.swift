import XCTest
@testable import Bellith

final class SessionStateTests: XCTestCase {
    func testTerminalSnapshotRoundtrip() throws {
        let snapshot = SessionState.TerminalSnapshot(
            cwd: "/Users/test/projects",
            hadScrollback: true,
            localSessionBootstrap: .tmux,
            localSessionName: "bellith-restore",
            scrollbackText: "$ echo hello\nhello"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionState.TerminalSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testLeafEncodeDecode() throws {
        let leaf = SplitNodeState.leaf(cwd: "/Users/test/projects", scrollbackText: nil)
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .leaf(let cwd, _) = decoded {
            XCTAssertEqual(cwd, "/Users/test/projects")
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testLeafWithNilCwd() throws {
        let leaf = SplitNodeState.leaf(cwd: nil, scrollbackText: nil)
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .leaf(let cwd, _) = decoded {
            XCTAssertNil(cwd)
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testLeafWithScrollbackText() throws {
        let leaf = SplitNodeState.leaf(cwd: "/tmp", scrollbackText: "$ ls\nfile1.txt\nfile2.txt\n$")
        let data = try JSONEncoder().encode(leaf)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .leaf(let cwd, let scrollbackText) = decoded {
            XCTAssertEqual(cwd, "/tmp")
            XCTAssertEqual(scrollbackText, "$ ls\nfile1.txt\nfile2.txt\n$")
        } else {
            XCTFail("Expected leaf node")
        }
    }

    func testBranchEncodeDecode() throws {
        let branch = SplitNodeState.branch(
            orientation: "horizontal",
            ratio: 0.5,
            first: .leaf(cwd: "/tmp", scrollbackText: nil),
            second: .leaf(cwd: "/home", scrollbackText: nil)
        )
        let data = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .branch(let orientation, let ratio, let first, let second) = decoded {
            XCTAssertEqual(orientation, "horizontal")
            XCTAssertEqual(ratio, 0.5, accuracy: 0.001)
            if case .leaf(let cwd1, _) = first { XCTAssertEqual(cwd1, "/tmp") }
            else { XCTFail("Expected leaf for first child") }
            if case .leaf(let cwd2, _) = second { XCTAssertEqual(cwd2, "/home") }
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
                first: .leaf(cwd: "/a", scrollbackText: nil),
                second: .leaf(cwd: "/b", scrollbackText: nil)
            ),
            second: .leaf(cwd: "/c", scrollbackText: nil)
        )
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        if case .branch(_, _, let first, _) = decoded {
            if case .branch(_, _, let innerFirst, _) = first {
                if case .leaf(let cwd, _) = innerFirst {
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
                SessionState.TabState(
                    title: "Tab 1",
                    terminalSnapshot: .init(cwd: "/home", hadScrollback: false),
                    terminalContext: context,
                    sshProfileID: context.sshProfileID
                ),
                SessionState.TabState(title: "Inspector", smartPanelID: "performance"),
                SessionState.TabState(
                    title: "Tab 2",
                    terminalSnapshot: .init(
                        cwd: "/tmp",
                        hadScrollback: true,
                        localSessionBootstrap: .zellij,
                        localSessionName: "bellith-tab-2",
                        scrollbackText: "restored transcript"
                    )
                ),
            ],
            selectedTabIndex: 1,
            sidebarExpanded: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)

        XCTAssertEqual(decoded.tabs.count, 3)
        XCTAssertEqual(decoded.selectedTabIndex, 1)
        XCTAssertEqual(decoded.sidebarExpanded, true)
        XCTAssertEqual(decoded.tabs[0].title, "Tab 1")
        XCTAssertEqual(decoded.tabs[0].terminalContext, context)
        XCTAssertEqual(decoded.tabs[0].sshProfileID, context.sshProfileID)
        XCTAssertEqual(decoded.tabs[0].terminalSnapshot, .init(cwd: "/home", hadScrollback: false))
        XCTAssertEqual(decoded.tabs[1].title, "Inspector")
        XCTAssertEqual(decoded.tabs[1].kind, .smart)
        XCTAssertEqual(decoded.tabs[1].smartPanelID, "performance")
        XCTAssertEqual(decoded.tabs[2].title, "Tab 2")
        XCTAssertEqual(
            decoded.tabs[2].terminalSnapshot,
            .init(
                cwd: "/tmp",
                hadScrollback: true,
                localSessionBootstrap: .zellij,
                localSessionName: "bellith-tab-2",
                scrollbackText: "restored transcript"
            )
        )
    }

    func testWindowSessionStateRoundtrip() throws {
        let windowState = WindowSessionState(
            session: SessionState(
                tabs: [SessionState.TabState(title: "Tab 1", terminalSnapshot: .init(cwd: "/tmp", hadScrollback: false))],
                selectedTabIndex: 0,
                sidebarExpanded: nil
            ),
            frameDescriptor: "{{10, 20}, {900, 600}}"
        )

        let data = try JSONEncoder().encode(windowState)
        let decoded = try JSONDecoder().decode(WindowSessionState.self, from: data)

        XCTAssertEqual(decoded.session.tabs.count, 1)
        XCTAssertEqual(decoded.frameDescriptor, "{{10, 20}, {900, 600}}")
    }

    func testTabDragPayloadRoundtrip() throws {
        let payload = TabDragPayload(sourceWindowID: UUID(), tabID: UUID())
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TabDragPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
    }

    func testLegacySplitTreeDecodesIntoFlattenedTerminalSnapshot() throws {
        let json = """
        {
          "tabs": [
            {
              "title": "Legacy",
              "kind": "terminal",
              "splitTree": {
                "type": "branch",
                "orientation": "horizontal",
                "ratio": 0.5,
                "first": {
                  "type": "leaf",
                  "cwd": "/tmp",
                  "scrollbackText": "hello"
                },
                "second": {
                  "type": "leaf",
                  "cwd": "/home",
                  "scrollbackText": null
                }
              }
            }
          ],
          "selectedTabIndex": 0
        }
        """

        let decoded = try JSONDecoder().decode(SessionState.self, from: Data(json.utf8))

        XCTAssertEqual(
            decoded.tabs.first?.terminalSnapshot,
            .init(cwd: "/tmp", hadScrollback: true, scrollbackText: "hello")
        )
    }
}
