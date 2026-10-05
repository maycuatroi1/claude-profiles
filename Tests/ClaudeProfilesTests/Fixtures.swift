import Foundation
import XCTest

@testable import ClaudeProfiles

let accountA = "11111111-1111-4111-8111-111111111111"
let orgA = "22222222-2222-4222-8222-222222222222"
let accountB = "33333333-3333-4333-8333-333333333333"
let orgB = "44444444-4444-4444-8444-444444444444"
let oldOrg = "55555555-5555-4555-8555-555555555555"

/// A temporary folder holding fake Claude data folders, one per profile.
final class Sandbox {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-profiles-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    var stateFile: URL { root.appendingPathComponent("sync-state.json") }

    func dataDir(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    func sessionsDir(_ name: String, account: String, org: String) -> URL {
        dataDir(name).appendingPathComponent("claude-code-sessions/\(account)/\(org)", isDirectory: true)
    }

    /// Writes the config.json Claude keeps: the account it last signed in
    /// with, and the dxt allowlist keys that name its organizations.
    @discardableResult
    func profile(_ name: String, account: String?, orgs: [String: String] = [:], share: Bool = true) throws -> Profile {
        let folder = dataDir(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var config: [String: Any] = [:]
        if let account { config["lastKnownAccountUuid"] = account }
        for (org, updated) in orgs { config["dxt:allowlistLastUpdated:\(org)"] = updated }
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("config.json"))
        return Profile(id: name, name: name, dataDir: folder.path, color: 0, shareSessions: share)
    }

    @discardableResult
    func session(_ n: Int, in dir: URL, activity: Double, extra: [String: Any] = [:]) throws -> String {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = sessionName(n)
        var record: [String: Any] = ["sessionId": String(name.dropLast(5)), "createdAt": 1, "lastActivityAt": activity]
        record.merge(extra) { _, new in new }
        try JSONSerialization.data(withJSONObject: record).write(to: dir.appendingPathComponent(name))
        return name
    }

    func record(_ name: String, in dir: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: dir.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func files(in dir: URL) -> [String] { SessionSync.sessionFiles(dir) }
}

func sessionName(_ n: Int) -> String {
    String(format: "local_aaaaaaaa-0000-4000-8000-%012d.json", n)
}
