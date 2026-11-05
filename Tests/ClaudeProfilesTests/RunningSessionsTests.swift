import XCTest

@testable import ClaudeProfiles

final class RunningSessionsTests: XCTestCase {
    typealias Entry = ClaudeInstances.ProcessEntry

    func testFindsSessionsStartedThroughTheHelperOnly() {
        let table = [
            Entry(pid: 100, parent: 1, name: "Claude"),
            Entry(pid: 101, parent: 100, name: "disclaimer"),
            Entry(pid: 102, parent: 101, name: "claude"),
            // The session's own children inherit its variable.
            Entry(pid: 103, parent: 102, name: "zsh"),
            Entry(pid: 104, parent: 103, name: "claude"),
            // A claude typed in a terminal inside Claude sits three levels down.
            Entry(pid: 110, parent: 100, name: "Claude Helper"),
            Entry(pid: 111, parent: 110, name: "zsh"),
            Entry(pid: 112, parent: 111, name: "claude"),
            // A claude without a session id, and one of another instance.
            Entry(pid: 120, parent: 100, name: "claude"),
            Entry(pid: 200, parent: 1, name: "Claude"),
            Entry(pid: 201, parent: 200, name: "disclaimer"),
            Entry(pid: 202, parent: 201, name: "claude"),
        ]
        let env: [pid_t: [String: String]] = [
            102: [RunningSessions.hostSessionKey: "local_a"],
            104: [RunningSessions.hostSessionKey: "local_a"],
            112: [RunningSessions.hostSessionKey: "local_b"],
            120: [:],
            202: [RunningSessions.hostSessionKey: "local_c"],
        ]

        let found = RunningSessions.hostSessions(under: 100, table: table) { env[$0] ?? [:] }

        XCTAssertEqual(found, ["local_a": 102])
    }

    func testReadsTitleFolderAndActivityFromTheRecord() throws {
        let sandbox = try Sandbox()
        let dir = sandbox.sessionsDir("work", account: accountA, org: orgA)
        let named = try sandbox.session(
            1, in: dir, activity: 1_700_000_000_000, extra: ["title": "Fix login", "cwd": "/tmp/app"])
        let untitled = try sandbox.session(2, in: dir, activity: 1, extra: ["title": "", "cwd": "/tmp/site"])

        let first = RunningSessions.session(String(named.dropLast(5)), pid: 9, profileID: "work", dir: dir)
        let second = RunningSessions.session(String(untitled.dropLast(5)), pid: 9, profileID: "work", dir: dir)
        let missing = RunningSessions.session("local_gone", pid: 9, profileID: "work", dir: dir)

        XCTAssertEqual(first.title, "Fix login")
        XCTAssertEqual(first.cwd, "/tmp/app")
        XCTAssertEqual(first.lastActivity, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(second.title, "site")
        XCTAssertEqual(missing.title, "Untitled session")
        XCTAssertNil(missing.lastActivity)
    }

    func testShortAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(shortAge(nil, now: now), "")
        XCTAssertEqual(shortAge(now.addingTimeInterval(5), now: now), "now")
        XCTAssertEqual(shortAge(now.addingTimeInterval(-59), now: now), "now")
        XCTAssertEqual(shortAge(now.addingTimeInterval(-125), now: now), "2m")
        XCTAssertEqual(shortAge(now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(shortAge(now.addingTimeInterval(-3 * 86400), now: now), "3d")
    }

    func testReadsTheEnvironmentOfARunningProcess() {
        let env = ClaudeInstances.processStrings(getpid()).env
        XCTAssertEqual(env["PATH"], ProcessInfo.processInfo.environment["PATH"])
        XCTAssertEqual(env["HOME"], ProcessInfo.processInfo.environment["HOME"])
    }
}

final class LaunchEnvironmentTests: XCTestCase {
    func testDropsWhatClaudeCodeSetsAndKeepsTheRest() {
        let env = [
            "CLAUDECODE": "1", "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/x.sock", "CLAUDE_PID": "5",
            "ANTHROPIC_BASE_URL": "http://localhost", "AI_AGENT": "claude", "OTEL_LOGS_EXPORTER": "otlp",
            "DISABLE_AUTOUPDATER": "1", "CLAUDE_PROFILES_HOME": "/tmp/p", "PATH": "/usr/bin", "HOME": "/Users/x",
            "LANG": "en_US.UTF-8",
        ]

        XCTAssertEqual(
            LaunchEnvironment.inherited(env),
            [
                "AI_AGENT", "ANTHROPIC_BASE_URL", "CLAUDECODE", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_PID",
                "DISABLE_AUTOUPDATER", "OTEL_LOGS_EXPORTER",
            ])
    }

    func testLeavesAnEnvironmentAloneWhenNotStartedFromClaudeCode() {
        XCTAssertEqual(LaunchEnvironment.inherited(["ANTHROPIC_BASE_URL": "http://proxy", "HTTPS_PROXY": "x"]), [])
    }
}

final class SwitchSettingsTests: XCTestCase {
    private func decode(_ json: String) throws -> ProfileSettings {
        try JSONDecoder().decode(ProfileSettings.self, from: Data(json.utf8))
    }

    func testOlderQuitSettingStillQuits() throws {
        XCTAssertEqual(try decode(#"{"profiles":[],"closeOthersOnSwitch":true}"#).others, .quit)
        XCTAssertEqual(try decode(#"{"profiles":[],"closeOthersOnSwitch":false}"#).others, .keep)
        XCTAssertEqual(try decode(#"{"profiles":[]}"#).others, .keep)
        XCTAssertEqual(try decode(#"{"profiles":[],"othersOnSwitch":"hide","closeOthersOnSwitch":false}"#).others, .hide)
    }

    func testUnknownModeFromANewerVersionDoesNotLoseTheProfiles() throws {
        let settings = try decode(
            #"{"profiles":[{"id":"a","name":"A","color":0,"shareSessions":true}],"othersOnSwitch":"minimize"}"#)
        XCTAssertEqual(settings.profiles.map(\.id), ["a"])
        XCTAssertEqual(settings.others, .keep)
    }

    func testCycleGoesThroughRunningProfilesOrAllOfThem() {
        let profiles = ["a", "b", "c", "d"].map { Profile(id: $0, name: $0, dataDir: nil, color: 0, shareSessions: true) }
        func next(_ running: Set<String>, _ current: String?) -> String? {
            ProfileCycle.next(profiles, running: running, current: current)?.id
        }

        XCTAssertEqual(next(["a", "c"], "a"), "c")
        XCTAssertEqual(next(["a", "c"], "c"), "a")
        XCTAssertEqual(next(["a", "c"], nil), "a")
        XCTAssertEqual(next(["b"], "b"), "c")
        XCTAssertEqual(next([], nil), "a")
        XCTAssertEqual(next([], "d"), "a")
        XCTAssertNil(ProfileCycle.next([], running: [], current: nil))
    }
}
