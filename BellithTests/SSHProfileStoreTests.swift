import XCTest
@testable import Bellith

final class SSHProfileStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SSHProfileStore!

    override func setUp() {
        super.setUp()
        suiteName = "SSHProfileStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SSHProfileStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testProfilesDefaultToEmpty() {
        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testRoundtripProfileSave() {
        let profile = SSHProfile(
            name: "Prod",
            host: "prod.example.com",
            user: "deploy",
            transport: .mosh,
            environmentTag: "prod",
            isSensitive: true
        )
        store.save([profile])

        let loaded = store.profiles
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.displayName, "Prod")
        XCTAssertEqual(loaded.first?.host, "prod.example.com")
        XCTAssertEqual(loaded.first?.transport, .mosh)
        XCTAssertTrue(loaded.first?.isSensitive ?? false)
    }

    func testUpsertUpdatesExistingProfile() {
        var profile = SSHProfile(name: "Ops", host: "ops.example.com")
        store.upsert(profile)

        profile.user = "root"
        store.upsert(profile)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.user, "root")
    }

    func testRoundtripProxyJumpProfileIDs() throws {
        let bastion = SSHProfile(name: "Bastion", host: "bastion.example.com")
        let profile = SSHProfile(
            name: "Prod",
            host: "prod.example.com",
            proxyJump: "bastion.example.com",
            proxyJumpProfileIDs: [bastion.id]
        )

        store.save([bastion, profile])

        let loadedProfile = try XCTUnwrap(store.profiles.first(where: { $0.id == profile.id }))
        XCTAssertEqual(loadedProfile.proxyJumpProfileIDs, [bastion.id])
        XCTAssertEqual(loadedProfile.proxyJump, "bastion.example.com")
    }

    func testDeleteProfileRemovesStoredItem() {
        let profile = SSHProfile(name: "Logs", host: "logs.example.com")
        store.save([profile])

        store.deleteProfile(id: profile.id)

        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testCorruptedDataFallsBackToEmpty() {
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: "sshProfiles")
        XCTAssertTrue(store.profiles.isEmpty)
    }

    func testLegacyTmuxSessionMigratesToSessionBootstrap() throws {
        let object: [[String: Any]] = [[
            "id": UUID().uuidString,
            "name": "Prod",
            "host": "prod.example.com",
            "tmuxSession": "prod"
        ]]
        let data = try JSONSerialization.data(withJSONObject: object)
        defaults.set(data, forKey: "sshProfiles")

        let loaded = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(loaded.sessionBootstrap, .tmux)
        XCTAssertEqual(loaded.sessionName, "prod")
    }

    func testLegacyProfilesDefaultTransportToSSH() throws {
        let object: [[String: Any]] = [[
            "id": UUID().uuidString,
            "name": "Prod",
            "host": "prod.example.com"
        ]]
        let data = try JSONSerialization.data(withJSONObject: object)
        defaults.set(data, forKey: "sshProfiles")

        let loaded = try XCTUnwrap(store.profiles.first)
        XCTAssertEqual(loaded.transport, .ssh)
    }
}
