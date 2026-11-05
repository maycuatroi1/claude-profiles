import XCTest

@testable import ClaudeProfiles

final class SessionWatcherTests: XCTestCase {
    private let cli = "6f1c2a90-1111-4111-8111-111111111111"

    private func assistant(_ stop: String?, tools: [String] = []) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": "hi"]]
        content += tools.map { ["type": "tool_use", "name": $0, "id": "t", "input": [:] as [String: Any]] }
        var message: [String: Any] = ["role": "assistant", "content": content]
        message["stop_reason"] = stop
        return ["type": "assistant", "message": message]
    }

    private let prompt: [String: Any] = ["type": "user", "message": ["role": "user", "content": "do it"]]
    private let toolResult: [String: Any] = [
        "type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t"]]],
    ]
    private let hookSummary: [String: Any] = ["type": "system", "subtype": "stop_hook_summary"]

    private func write(_ entries: [[String: Any]], to url: URL) throws {
        let lines = try entries.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: false, encoding: .utf8)
    }

    func testStateOfEntries() {
        XCTAssertEqual(SessionWatcher.state(of: assistant("end_turn")), .idle)
        XCTAssertEqual(SessionWatcher.state(of: assistant("stop_sequence")), .idle)
        XCTAssertEqual(SessionWatcher.state(of: assistant("tool_use", tools: ["Bash"])), .working)
        XCTAssertEqual(SessionWatcher.state(of: assistant("tool_use", tools: ["AskUserQuestion"])), .asking)
        XCTAssertEqual(SessionWatcher.state(of: prompt), .working)
        XCTAssertEqual(SessionWatcher.state(of: toolResult), .working)
        XCTAssertNil(SessionWatcher.state(of: hookSummary))
        XCTAssertNil(SessionWatcher.state(of: ["type": "user", "isMeta": true, "message": ["content": "x"]]))
        var subagent = assistant("end_turn")
        subagent["isSidechain"] = true
        XCTAssertNil(SessionWatcher.state(of: subagent))
    }

    func testTailSkipsTrailingBookkeepingAndReadsPastTheFirstPiece() throws {
        let sandbox = try Sandbox()
        let url = sandbox.root.appendingPathComponent("t.jsonl")
        // A finished turn, then more than 64 KB of entries that do not count.
        let filler: [String: Any] = ["type": "attachment", "text": String(repeating: "x", count: 1000)]
        try write([prompt, assistant("end_turn"), hookSummary] + Array(repeating: filler, count: 100), to: url)

        XCTAssertEqual(SessionWatcher.tailState(url), .idle)
    }

    func testReportsAFinishedTurnOnceItSettles() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.root.appendingPathComponent("projects/-tmp-app", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(cli).jsonl")
        let watcher = SessionWatcher(projectsDir: sandbox.root.appendingPathComponent("projects"), settle: 4)
        let session = RunningSession(
            id: "local_a", profileID: "work", pid: 1, title: "Fix login", cwd: "/tmp/app", lastActivity: nil,
            cliSessionID: cli)
        let open = ["work": [session]]
        let start = Date(timeIntervalSince1970: 1_000)

        try write([prompt, assistant("tool_use", tools: ["Bash"])], to: url)
        XCTAssertEqual(watcher.poll(open, now: start), [], "the first sight only records the state")

        try write([prompt, assistant("tool_use", tools: ["Bash"]), toolResult, assistant("end_turn"), hookSummary], to: url)
        XCTAssertEqual(watcher.poll(open, now: start.addingTimeInterval(3)), [], "not settled yet")
        XCTAssertEqual(
            watcher.poll(open, now: start.addingTimeInterval(8)), [SessionWatcher.Event(kind: .finished, session: session)])
        XCTAssertEqual(watcher.poll(open, now: start.addingTimeInterval(20)), [], "reported once")

        // A Stop hook that sends the turn back to work before it settles.
        try write([prompt, assistant("end_turn"), prompt], to: url)
        _ = watcher.poll(open, now: start.addingTimeInterval(30))
        try write([prompt, assistant("end_turn"), prompt, assistant("tool_use", tools: ["AskUserQuestion"])], to: url)
        XCTAssertEqual(watcher.poll(open, now: start.addingTimeInterval(32)), [])
        XCTAssertEqual(
            watcher.poll(open, now: start.addingTimeInterval(40)), [SessionWatcher.Event(kind: .asking, session: session)])
    }

    func testIdleSessionSeenFirstIsNotReported() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.root.appendingPathComponent("projects/-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write([prompt, assistant("end_turn")], to: folder.appendingPathComponent("\(cli).jsonl"))
        let watcher = SessionWatcher(projectsDir: sandbox.root.appendingPathComponent("projects"), settle: 0)
        let session = RunningSession(
            id: "local_a", profileID: "work", pid: 1, title: "t", cwd: nil, lastActivity: nil, cliSessionID: cli)

        XCTAssertEqual(watcher.poll(["work": [session]]), [])
        XCTAssertEqual(watcher.poll(["work": [session]]), [])
    }

    func testSessionOpenInTwoProfilesIsReportedOnceForTheLatest() throws {
        let sandbox = try Sandbox()
        let folder = sandbox.root.appendingPathComponent("projects/-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(cli).jsonl")
        let watcher = SessionWatcher(projectsDir: sandbox.root.appendingPathComponent("projects"), settle: 0)
        func copy(_ profile: String, _ activity: Double) -> RunningSession {
            RunningSession(
                id: "local_a", profileID: profile, pid: 1, title: "t", cwd: nil,
                lastActivity: Date(timeIntervalSince1970: activity), cliSessionID: cli)
        }
        let open = ["home": [copy("home", 10)], "work": [copy("work", 20)]]

        try write([prompt], to: url)
        _ = watcher.poll(open)
        try write([prompt, assistant("end_turn")], to: url)
        let events = watcher.poll(open)

        XCTAssertEqual(events.map(\.session.profileID), ["work"])
    }
}
