import XCTest

@testable import ClaudeProfiles

final class ProfileStoreTests: XCTestCase {
    func testSlugFoldsVietnameseAndPunctuation() {
        XCTAssertEqual(ProfileStore.slug("Công ty"), "cong-ty")
        XCTAssertEqual(ProfileStore.slug("Đội Ngũ #2"), "doi-ngu-2")
        XCTAssertEqual(ProfileStore.slug("!!!"), "profile")
    }

    func testPrettyNameDropsTheClaudePrefix() {
        XCTAssertEqual(ProfileStore.prettyName("ClaudeCompany", fallback: "x"), "Company")
        XCTAssertEqual(ProfileStore.prettyName("Claude-Work", fallback: "x"), "Work")
        XCTAssertEqual(ProfileStore.prettyName("Claude", fallback: "Profile 2"), "Profile 2")
        XCTAssertEqual(ProfileStore.prettyName("Side", fallback: "x"), "Side")
    }

    func testUniqueIDCountsUp() {
        XCTAssertEqual(ProfileStore.uniqueID("work", taken: []), "work")
        XCTAssertEqual(ProfileStore.uniqueID("work", taken: ["work", "work-2"]), "work-3")
    }
}

final class AccountInfoTests: XCTestCase {
    func testReadsAccountAndMostRecentlyUpdatedOrg() throws {
        let sandbox = try Sandbox()
        let profile = try sandbox.profile(
            "work", account: accountB, orgs: [oldOrg: "2025-01-01T00:00:00Z", orgB: "2026-10-05T07:00:00Z"])

        let info = AccountInfo.read(profile.dataURL)

        XCTAssertEqual(info.accountUUID, accountB)
        XCTAssertEqual(info.orgUUID, orgB)
        XCTAssertEqual(info.short, "33333333")
    }

    func testExistingSessionFolderWinsOverConfigKeys() throws {
        let sandbox = try Sandbox()
        let profile = try sandbox.profile("work", account: accountB, orgs: [orgB: "2026-10-05T07:00:00Z"])
        try FileManager.default.createDirectory(
            at: sandbox.sessionsDir("work", account: accountB, org: oldOrg), withIntermediateDirectories: true)

        XCTAssertEqual(AccountInfo.read(profile.dataURL).orgUUID, oldOrg)
    }

    func testSignedOutWithoutAnAccount() throws {
        let sandbox = try Sandbox()
        XCTAssertFalse(AccountInfo.read(try sandbox.profile("fresh", account: nil).dataURL).signedIn)
        XCTAssertFalse(AccountInfo.read(try sandbox.profile("odd", account: "../../etc").dataURL).signedIn)
        XCTAssertFalse(AccountInfo.read(sandbox.dataDir("missing")).signedIn)
    }
}

final class ClaudeInstancesTests: XCTestCase {
    func testUserDataDirInBothSpellings() {
        XCTAssertEqual(ClaudeInstances.userDataDir(["Claude", "--user-data-dir=/a b"]), "/a b")
        XCTAssertEqual(ClaudeInstances.userDataDir(["Claude", "--user-data-dir", "/c"]), "/c")
        XCTAssertNil(ClaudeInstances.userDataDir(["Claude", "--user-data-dir"]))
        XCTAssertNil(ClaudeInstances.userDataDir(["Claude"]))
    }

    func testReadsArgumentsOfARunningProcess() {
        let args = ClaudeInstances.processArguments(getpid())
        XCTAssertEqual(args, CommandLine.arguments)
    }
}

final class IconRendererTests: XCTestCase {
    func testWritesEveryIconSize() throws {
        let sandbox = try Sandbox()
        let iconset = sandbox.root.appendingPathComponent("AppIcon.iconset")

        try IconRenderer.writeIconset(to: iconset)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: iconset.path).count, IconRenderer.sizes.count)
        XCTAssertEqual(IconRenderer.render(64).pixelsWide, 64)
    }
}
