import Foundation

struct Profile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// nil means Claude's default data folder.
    var dataDir: String?
    var color: Int
    var shareSessions: Bool

    var isDefault: Bool { dataDir == nil }
    var dataURL: URL {
        guard let dataDir else { return Paths.defaultDataDir }
        return URL(fileURLWithPath: expandTilde(dataDir), isDirectory: true)
    }
}

struct ProfileSettings: Codable {
    var profiles: [Profile]
    var closeOthersOnSwitch: Bool?
}

enum ProfileStore {
    static func load() -> ProfileSettings {
        if let data = try? Data(contentsOf: Paths.configFile),
            let settings = try? JSONDecoder().decode(ProfileSettings.self, from: data),
            !settings.profiles.isEmpty
        {
            return settings
        }
        let seeded = ProfileSettings(profiles: discover(), closeOthersOnSwitch: false)
        try? save(seeded)
        return seeded
    }

    static func save(_ settings: ProfileSettings) throws {
        try makePrivateDirectory(Paths.supportDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(settings).write(to: Paths.configFile, options: .atomic)
    }

    /// First run: the default profile plus any Claude data folder already in
    /// use, from running instances or folders like ~/ClaudeWork.
    static func discover() -> [Profile] {
        var profiles = [Profile(id: "default", name: "Cá nhân", dataDir: nil, color: 0, shareSessions: true)]
        var seen: Set<String> = [canonicalPath(Paths.defaultDataDir.path), canonicalPath(Paths.claudeDataDir.path)]
        var candidates: [String] = ClaudeInstances.list().compactMap { $0.dataDir }
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: Paths.home.path) {
            for item in items.sorted() where item.hasPrefix("Claude") {
                let path = Paths.home.appendingPathComponent(item).path
                if fm.fileExists(atPath: path + "/config.json") { candidates.append(path) }
            }
        }
        for path in candidates {
            let key = canonicalPath(path)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let name = prettyName(URL(fileURLWithPath: key).lastPathComponent, fallback: "Profile \(profiles.count + 1)")
            profiles.append(
                Profile(
                    id: uniqueID(slug(name), taken: profiles.map(\.id)), name: name,
                    dataDir: abbreviateHome(key), color: profiles.count % palette.count, shareSessions: true))
        }
        return profiles
    }

    static func prettyName(_ folder: String, fallback: String) -> String {
        var name = folder
        if name.hasPrefix("Claude") { name.removeFirst("Claude".count) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
        return name.isEmpty ? fallback : name
    }

    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "đ", with: "d")
        let parts = folded.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let joined = parts.joined(separator: "-")
        return joined.isEmpty ? "profile" : joined
    }

    static func uniqueID(_ base: String, taken: [String]) -> String {
        var candidate = base
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }
}
