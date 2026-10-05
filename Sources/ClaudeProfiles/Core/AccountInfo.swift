import Foundation

struct AccountInfo {
    var accountUUID: String?
    var orgUUID: String?

    var signedIn: Bool { accountUUID != nil }
    var short: String? { accountUUID.map { String($0.prefix(8)) } }

    /// Reads the account Claude last signed in with, and the organization whose
    /// session folder it uses: an existing folder when there is one, otherwise
    /// the org named by the most recent `dxt:allowlistLastUpdated:<org>` key.
    static func read(_ dataDir: URL) -> AccountInfo {
        guard let config = readJSONObject(dataDir.appendingPathComponent("config.json")),
            let account = config["lastKnownAccountUuid"] as? String, isUUID(account)
        else { return AccountInfo() }
        let base = dataDir.appendingPathComponent(sessionsFolder).appendingPathComponent(account)
        if let org = newestOrgFolder(base) { return AccountInfo(accountUUID: account, orgUUID: org) }
        let prefix = "dxt:allowlistLastUpdated:"
        let org = config.compactMap { key, value -> (String, String)? in
            guard key.hasPrefix(prefix) else { return nil }
            let uuid = String(key.dropFirst(prefix.count))
            return isUUID(uuid) ? (uuid, value as? String ?? "") : nil
        }.max { $0.1 < $1.1 }?.0
        return AccountInfo(accountUUID: account, orgUUID: org)
    }

    private static func newestOrgFolder(_ base: URL) -> String? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: keys)
        else { return nil }
        return items.compactMap { url -> (String, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
                values.isSymbolicLink != true, isUUID(url.lastPathComponent)
            else { return nil }
            return (url.lastPathComponent, values.contentModificationDate ?? .distantPast)
        }.max { $0.1 < $1.1 }?.0
    }
}
