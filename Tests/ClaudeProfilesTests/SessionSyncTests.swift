import XCTest

@testable import ClaudeProfiles

final class SessionSyncTests: XCTestCase {
    var sandbox: Sandbox!
    var personal: Profile!
    var work: Profile!
    var personalDir: URL!
    var workDir: URL!

    override func setUpWithError() throws {
        sandbox = try Sandbox()
        personal = try sandbox.profile("personal", account: accountA, orgs: [orgA: "2026-10-05T07:00:00Z"])
        work = try sandbox.profile(
            "work", account: accountB, orgs: [orgB: "2026-10-05T07:00:00Z", oldOrg: "2025-01-01T00:00:00Z"])
        personalDir = sandbox.sessionsDir("personal", account: accountA, org: orgA)
        workDir = sandbox.sessionsDir("work", account: accountB, org: orgB)
    }

    private func sync(running: Set<String> = [], dryRun: Bool = false, profiles: [Profile]? = nil) -> SyncReport {
        SessionSync(dryRun: dryRun, stateFile: sandbox.stateFile).run(profiles ?? [personal, work], running: running)
    }

    func testCopiesSessionsIntoTheOtherAccount() throws {
        let one = try sandbox.session(1, in: personalDir, activity: 100, extra: ["bridgeSessionIds": ["b"], "title": "one"])
        let two = try sandbox.session(2, in: personalDir, activity: 200)
        try Data(#"{"sessionId": "local_broken"}"#.utf8).write(to: personalDir.appendingPathComponent("local_broken.json"))

        let report = sync()

        XCTAssertEqual(report.added, 2)
        XCTAssertEqual(report.participants, 2)
        XCTAssertEqual(sandbox.files(in: workDir), [one, two])
        let copied = try sandbox.record(one, in: workDir)
        XCTAssertEqual(copied["title"] as? String, "one")
        XCTAssertNil(copied["bridgeSessionIds"], "Remote Control links belong to the other account")

        let attributes = try FileManager.default.attributesOfItem(atPath: workDir.appendingPathComponent(one).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
    }

    func testSessionsFlowBothWays() throws {
        let mine = try sandbox.session(1, in: personalDir, activity: 100)
        let theirs = try sandbox.session(2, in: workDir, activity: 100)

        XCTAssertEqual(sync().added, 2)
        XCTAssertEqual(sandbox.files(in: personalDir), [mine, theirs])
        XCTAssertEqual(sandbox.files(in: workDir), [mine, theirs])
    }

    func testDryRunChangesNothing() throws {
        try sandbox.session(1, in: personalDir, activity: 100)

        XCTAssertEqual(sync(dryRun: true).added, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.stateFile.path))
    }

    func testRemovedSessionStaysRemoved() throws {
        let one = try sandbox.session(1, in: personalDir, activity: 100)
        _ = sync()
        try FileManager.default.removeItem(at: workDir.appendingPathComponent(one))

        for _ in 0..<3 { _ = sync() }

        XCTAssertEqual(sandbox.files(in: workDir), [])
        XCTAssertEqual(sandbox.files(in: personalDir), [one])
    }

    func testNewerRecordReplacesOlderInAClosedProfile() throws {
        let two = try sandbox.session(2, in: personalDir, activity: 200, extra: ["title": "old"])
        _ = sync()
        try sandbox.session(2, in: workDir, activity: 900, extra: ["title": "continued in work"])

        XCTAssertEqual(sync().updated, 1)
        XCTAssertEqual(try sandbox.record(two, in: personalDir)["title"] as? String, "continued in work")
        let again = sync()
        XCTAssertEqual(again.added + again.updated, 0)
    }

    func testRunningProfileOnlyReceivesNewSessions() throws {
        let two = try sandbox.session(2, in: personalDir, activity: 200, extra: ["title": "old"])
        _ = sync()
        try sandbox.session(2, in: workDir, activity: 900, extra: ["title": "continued in work"])
        let three = try sandbox.session(3, in: workDir, activity: 300)

        let report = sync(running: [personal.id])

        XCTAssertEqual(report.updated, 0, "a running Claude would write its in-memory copy back")
        XCTAssertEqual(report.added, 1)
        XCTAssertEqual(try sandbox.record(two, in: personalDir)["title"] as? String, "old")
        XCTAssertTrue(sandbox.files(in: personalDir).contains(three))
    }

    func testSameAccountKeepsRemoteControlLinks() throws {
        let twin = try sandbox.profile("twin", account: accountA, orgs: [orgA: "2026-10-05T07:00:00Z"])
        let one = try sandbox.session(1, in: personalDir, activity: 100, extra: ["bridgeSessionIds": ["b"]])

        _ = sync(profiles: [personal, twin])

        let twinDir = sandbox.sessionsDir("twin", account: accountA, org: orgA)
        XCTAssertEqual(try sandbox.record(one, in: twinDir)["bridgeSessionIds"] as? [String], ["b"])
    }

    func testProfileWithoutSharingIsLeftAlone() throws {
        work.shareSessions = false
        try sandbox.session(1, in: personalDir, activity: 100)

        let report = sync()

        XCTAssertEqual(report.participants, 1)
        XCTAssertEqual(report.added, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDir.path))
    }

    func testSignedOutProfileIsSkipped() throws {
        let fresh = try sandbox.profile("fresh", account: nil)
        try sandbox.session(1, in: personalDir, activity: 100)

        XCTAssertEqual(sync(profiles: [personal, fresh]).participants, 1)
    }
}
