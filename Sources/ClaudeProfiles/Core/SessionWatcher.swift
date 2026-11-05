import Foundation

/// Notices when an open Code session finishes its turn or asks a question,
/// from the transcript Claude Code writes to ~/.claude/projects: the last
/// assistant entry of a finished turn has a stop_reason such as end_turn.
///
/// The record a profile keeps has no running flag, and Claude's own
/// notification log is not written to disk, so the transcript is the signal.
/// A tool waiting for permission looks like a tool still running and is not
/// reported.
final class SessionWatcher {
    enum State: Equatable {
        case working, idle, asking
    }

    struct Event: Equatable {
        enum Kind: Equatable {
            case finished, asking
        }
        let kind: Kind
        let session: RunningSession
    }

    private struct Track {
        var state: State
        var observed: State
        var since: Date
        var size: UInt64
        var modified: Date
    }

    let projectsDir: URL
    /// How long a new state must hold before it counts: a Stop hook can send
    /// a finished turn back to work.
    var settle: TimeInterval
    private var tracks: [URL: Track] = [:]
    private var transcripts: [String: URL] = [:]
    private let fm = FileManager.default

    init(projectsDir: URL = Paths.home.appendingPathComponent(".claude/projects", isDirectory: true), settle: TimeInterval = 4) {
        self.projectsDir = projectsDir
        self.settle = settle
    }

    /// The events since the last call. The first sight of a session only
    /// records where it stands.
    func poll(_ open: [String: [RunningSession]], now: Date = Date()) -> [Event] {
        // A session open in two profiles shares one transcript; report it
        // once, for the profile that touched it last.
        var newest: [String: RunningSession] = [:]
        for session in open.values.flatMap({ $0 }) {
            guard let cli = session.cliSessionID else { continue }
            if let other = newest[cli], (other.lastActivity ?? .distantPast) >= (session.lastActivity ?? .distantPast) {
                continue
            }
            newest[cli] = session
        }
        var events: [Event] = []
        var seen: Set<URL> = []
        for (cli, session) in newest {
            guard let url = transcript(cli) else { continue }
            seen.insert(url)
            // Not URL.resourceValues: a URL keeps the values it read first.
            guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { continue }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            guard var track = tracks[url] else {
                let state = Self.tailState(url) ?? .working
                tracks[url] = Track(state: state, observed: state, since: now, size: size, modified: modified)
                continue
            }
            if size != track.size || modified != track.modified {
                track.size = size
                track.modified = modified
                if let state = Self.tailState(url), state != track.observed {
                    track.observed = state
                    track.since = now
                }
            }
            if track.observed != track.state && now.timeIntervalSince(track.since) >= settle {
                let before = track.state
                track.state = track.observed
                if track.state == .idle && before == .working { events.append(Event(kind: .finished, session: session)) }
                if track.state == .asking { events.append(Event(kind: .asking, session: session)) }
            }
            tracks[url] = track
        }
        tracks = tracks.filter { seen.contains($0.key) }
        return events
    }

    /// Where a session stood at the last poll; nil before its first one.
    func state(of session: RunningSession) -> State? {
        session.cliSessionID.flatMap(transcript).flatMap { tracks[$0]?.state }
    }

    /// ~/.claude/projects/<folder>/<cliSessionId>.jsonl, remembered once found.
    private func transcript(_ cli: String) -> URL? {
        if let url = transcripts[cli], fm.fileExists(atPath: url.path) { return url }
        guard isUUID(cli), let folders = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil)
        else { return nil }
        let url = folders.map { $0.appendingPathComponent("\(cli).jsonl") }.first { fm.fileExists(atPath: $0.path) }
        transcripts[cli] = url
        return url
    }

    /// Where the transcript stands, from its last entry that says so. Reads
    /// from the end, a larger piece each time, up to 4 MB.
    static func tailState(_ url: URL) -> State? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var length: UInt64 = 64 * 1024
        while true {
            let start = size > length ? size - length : 0
            guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }
            var lines = data.split(separator: UInt8(ascii: "\n"))
            // The first piece starts mid-line unless it starts the file.
            if start > 0, !lines.isEmpty { lines.removeFirst() }
            for line in lines.reversed() {
                guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
                if let state = state(of: entry) { return state }
            }
            if start == 0 || length >= 4 * 1024 * 1024 { return nil }
            length *= 4
        }
    }

    /// nil for entries that say nothing about the turn: hooks, titles,
    /// attachments, subagent work.
    static func state(of entry: [String: Any]) -> State? {
        if entry["isSidechain"] as? Bool == true { return nil }
        let message = entry["message"] as? [String: Any]
        switch entry["type"] as? String {
        case "assistant":
            let content = message?["content"] as? [[String: Any]] ?? []
            if content.contains(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == "AskUserQuestion" }) {
                return .asking
            }
            switch message?["stop_reason"] as? String {
            case "end_turn", "stop_sequence", "max_tokens", "refusal": return .idle
            default: return .working
            }
        case "user":
            return entry["isMeta"] as? Bool == true ? nil : .working
        default:
            return nil
        }
    }
}
