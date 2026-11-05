import Foundation

/// A Code session whose `claude` process is alive under a running profile.
struct RunningSession: Identifiable, Equatable {
    /// The record's sessionId, `local_<uuid>`.
    let id: String
    let profileID: String
    let pid: pid_t
    var title: String
    var cwd: String?
    var lastActivity: Date?
    /// When the profile last showed this session; the newest is the one on screen.
    var lastFocused: Date?
    /// Claude Code's own id, which names the transcript.
    var cliSessionID: String?
    /// Names of other profiles that have this session open at the same time.
    var alsoOpenIn: [String] = []
}

enum RunningSessions {
    static let hostSessionKey = "CLAUDE_CODE_HOST_SESSION_ID"

    /// The Code sessions open in each running profile, by profile id, the
    /// most recently active first.
    static func list(_ profiles: [Profile], instances: [ClaudeInstance]) -> [String: [RunningSession]] {
        let table = ClaudeInstances.processTable()
        var result: [String: [RunningSession]] = [:]
        for profile in profiles {
            guard let app = ClaudeInstances.find(profile, in: instances) else { continue }
            let open = hostSessions(under: app.processIdentifier, table: table) { ClaudeInstances.processStrings($0).env }
            let dir = SessionSync.sessionDir(profile)
            result[profile.id] = open.map { id, pid in session(id, pid: pid, profileID: profile.id, dir: dir) }
                .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        }
        let holders = Dictionary(grouping: result.values.flatMap { $0 }, by: \.id).mapValues { $0.map(\.profileID) }
        let names = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })
        for (profileID, sessions) in result {
            result[profileID] = sessions.map { session in
                var session = session
                session.alsoOpenIn = (holders[session.id] ?? []).filter { $0 != profileID }.compactMap { names[$0] }
                return session
            }
        }
        return result
    }

    /// Code sessions below a Claude instance. Claude starts each one as a
    /// `claude` process, through its `disclaimer` helper, and names the
    /// session in CLAUDE_CODE_HOST_SESSION_ID. Only two levels down: a
    /// `claude` typed in a terminal inside Claude sits deeper and inherits
    /// the variable, and so do the children of a session's own process.
    static func hostSessions(
        under root: pid_t, table: [ClaudeInstances.ProcessEntry], environment: (pid_t) -> [String: String]
    ) -> [String: pid_t] {
        let children = Dictionary(grouping: table, by: \.parent)
        var found: [String: pid_t] = [:]
        var frontier = [root]
        for _ in 0..<2 {
            frontier = frontier.flatMap { children[$0] ?? [] }.compactMap { child in
                guard child.name == "claude" else { return child.pid }
                if let id = environment(child.pid)[hostSessionKey], id.hasPrefix("local_") { found[id] = child.pid }
                return nil
            }
        }
        return found
    }

    static func session(_ id: String, pid: pid_t, profileID: String, dir: URL?) -> RunningSession {
        let record = dir.flatMap { readJSONObject($0.appendingPathComponent("\(id).json")) } ?? [:]
        let cwd = (record["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let title = (record["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Untitled session"
        func date(_ key: String) -> Date? {
            (record[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        return RunningSession(
            id: id, profileID: profileID, pid: pid, title: title, cwd: cwd, lastActivity: date("lastActivityAt"),
            lastFocused: date("lastFocusedAt"), cliSessionID: record["cliSessionId"] as? String)
    }
}

/// "now", "5m", "3h", "2d": how long ago, short enough for a menu row.
func shortAge(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(seconds / 60)m"
    case ..<86400: return "\(seconds / 3600)h"
    default: return "\(seconds / 86400)d"
    }
}
