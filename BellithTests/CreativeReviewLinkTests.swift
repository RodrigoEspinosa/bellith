import XCTest
@testable import Bellith

final class CreativeReviewLinkTests: XCTestCase {
    func testRoundTripSupportsOnlyNativeReviewDestinations() {
        for tool in [CreativeReviewLink.Tool.resolve, .logic, .logicTrack] {
            let link = CreativeReviewLink(tool: tool, proposalID: UUID())
            XCTAssertEqual(CreativeReviewLink(url: link.url), link)
        }
    }

    func testUnknownRepeatedOrExecutableArgumentsAreRejected() {
        let id = UUID().uuidString
        for value in [
            "bellith://review?tool=logic&proposal=\(id)&cmd=play",
            "bellith://review?tool=logic&proposal=\(id)&tool=resolve",
            "bellith://review?tool=logic&proposal=\(id)&proposal=\(id)",
            "bellith://review?tool=unknown&proposal=\(id)",
            "bellith://review?tool=logic&proposal=invalid",
            "bellith://review?tool=logic", "bellith://review?proposal=\(id)",
            "bellith://review/path?tool=logic&proposal=\(id)",
            "bellith://review?tool=logic&proposal=\(id)#execute",
            "bellith://user@review?tool=logic&proposal=\(id)",
            "bellith://review:123?tool=logic&proposal=\(id)",
            "https://review?tool=logic&proposal=\(id)",
        ] {
            XCTAssertNil(CreativeReviewLink(url: URL(string: value)!), value)
        }
    }

    @MainActor func testRepeatedReviewRequestsRemainNavigationOnly() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        let logic = LogicTransportModel(operationsEnabled: false, file: file)
        let id = UUID()
        logic.requestProposalReview(id)
        let first = logic.proposalReviewRequest
        logic.requestProposalReview(id)
        XCTAssertNotEqual(first?.id, logic.proposalReviewRequest?.id)
        XCTAssertEqual(logic.proposalReviewRequest?.proposalID, id)
        XCTAssertNil(logic.reviewedProposal)
        XCTAssertNil(logic.snapshot)
        XCTAssertFalse(logic.busy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let resolve = ResolveHarnessModel(storage: file.deletingLastPathComponent(), hostOperationsEnabled: false)
        let session = resolve.session
        resolve.requestProposalReview(id)
        XCTAssertEqual(resolve.session.id, session.id)
        XCTAssertNil(resolve.session.plan)
        XCTAssertFalse(resolve.busy)
    }
}
