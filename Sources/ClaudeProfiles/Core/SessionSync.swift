import Darwin
import Foundation

struct SyncReport {
    var added = 0
    var updated = 0
    var participants = 0
    var problems: [String] = []

    var summary: String {
        if participants < 2 { return "Turn on sharing in two or more profiles" }
        if added == 0 && updated == 0 { return "In sync" }
        var parts: [String] = []
        if added > 0 { parts.append("+\(added) new") }
        if updated > 0 { parts.append("\(updated) updated") }
        return parts.joined(separator: ", ")
    }
}

/// Copies Code session records between the profiles that share them.
///
/// - A record missing from a profile is added, unless that profile had it at
///   the last sync and the user removed it there since.
/// - A record present on both sides is replaced by the copy with the newer
///   `lastActivityAt`, but only while the receiving profile is closed: a
///   running Claude keeps its sessions in memory and would write over it.
/// - `bridgeSessionIds` (Remote Control links) belong to one account and are
///   dropped when a record crosses to a different account.
struct SessionSync {
    var dryRun = false
    /// Which records each profile has held, so a removal there sticks.
    var stateFile = Paths.stateFile
    private let fm = FileManager.default

    struct Endpoint {
        let profile: Profile
        let account: String
        let dir: URL
    }

    static func sessionDir(_ profile: Profile) -> URL? {
        let info = AccountInfo.read(profile.dataURL)
        guard let account = info.accountUUID, let org = info.orgUUID else { return nil }
        return profile.dataURL.appendingPathComponent(sessionsFolder)
            .appendingPathComponent(account).appendingPathComponent(org)
    }

    static func sessionFiles(_ dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("local_") && $0.hasSuffix(".json") }.sorted()
    }

    func run(_ profiles: [Profile], running: Set<String>) -> SyncReport {
        var report = SyncReport()
        let endpoints = profiles.filter(\.shareSessions).compactMap(endpoint)
        report.participants = endpoints.count
        guard endpoints.count > 1 else { return report }

        var state = loadState()
        let everywhere = Set(endpoints.flatMap { Self.sessionFiles($0.dir) })
        for target in endpoints {
            if !dryRun {
                do { try makePrivateDirectory(target.dir) } catch {
                    report.problems.append("\(target.profile.name): \(error.localizedDescription)")
                    continue
                }
            }
            let targetRunning = running.contains(target.profile.id)
            let known = Set(state[target.profile.id] ?? [])
            for source in endpoints where source.profile.id != target.profile.id {
                for name in Self.sessionFiles(source.dir) {
                    let destination = target.dir.appendingPathComponent(name)
                    let exists = fm.fileExists(atPath: destination.path)
                    if !exists && known.contains(name) { continue }
                    if exists && targetRunning { continue }
                    guard let record = readRecord(source.dir.appendingPathComponent(name), name: name) else { continue }
                    if exists {
                        guard let current = readRecord(destination, name: name),
                            activity(record.object) > activity(current.object)
                        else { continue }
                    }
                    do {
                        try write(record, crossing: source.account != target.account, to: destination)
                        if exists { report.updated += 1 } else { report.added += 1 }
                    } catch {
                        report.problems.append("\(name): \(error.localizedDescription)")
                    }
                }
            }
            // Remember every record this profile has held, so one removed here
            // stays removed; forget names no profile holds any more.
            if !dryRun {
                state[target.profile.id] = known.union(Self.sessionFiles(target.dir)).intersection(everywhere).sorted()
            }
        }
        if !dryRun { saveState(state) }
        return report
    }

    private func endpoint(_ profile: Profile) -> Endpoint? {
        let info = AccountInfo.read(profile.dataURL)
        guard let account = info.accountUUID, let dir = Self.sessionDir(profile) else { return nil }
        return Endpoint(profile: profile, account: account, dir: dir)
    }

    private struct Record {
        let data: Data
        let object: [String: Any]
    }

    /// A record Claude would accept: a regular file whose sessionId matches its
    /// name and that carries createdAt and lastActivityAt.
    private func readRecord(_ url: URL, name: String) -> Record? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
            values.isRegularFile == true, values.isSymbolicLink != true,
            let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let sessionID = object["sessionId"] as? String, "\(sessionID).json" == name,
            object["createdAt"] is NSNumber, object["lastActivityAt"] is NSNumber
        else { return nil }
        return Record(data: data, object: object)
    }

    private func activity(_ object: [String: Any]) -> Double {
        (object["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0
    }

    private func write(_ record: Record, crossing: Bool, to destination: URL) throws {
        guard !dryRun else { return }
        var data = record.data
        if crossing, record.object["bridgeSessionIds"] != nil {
            var object = record.object
            object.removeValue(forKey: "bridgeSessionIds")
            data = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        }
        // Write beside the target under a dot name Claude ignores, then rename
        // over it so Claude never reads half a file.
        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(getpid()).tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temp.path, destination.path) != 0 {
            let code = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func loadState() -> [String: [String]] {
        guard let data = try? Data(contentsOf: stateFile),
            let state = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return state
    }

    private func saveState(_ state: [String: [String]]) {
        try? makePrivateDirectory(stateFile.deletingLastPathComponent())
        try? JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
    }
}
