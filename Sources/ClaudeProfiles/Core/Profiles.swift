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

/// What happens to the other running profiles when you switch to one.
enum OthersOnSwitch: String, Codable, CaseIterable {
    case keep, hide, quit

    /// A value from a newer version reads as `keep` instead of failing the
    /// whole settings file.
    init(from decoder: Decoder) throws {
        self = OthersOnSwitch(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .keep
    }
}

struct ProfileSettings: Codable {
    var profiles: [Profile]
    /// Before 0.2 the only choice; true meant quit. Kept in step with
    /// `othersOnSwitch` so an older version still reads it.
    var closeOthersOnSwitch: Bool?
    var othersOnSwitch: OthersOnSwitch?
    /// ⌃⌥⇥ rotates through the profiles; on unless turned off.
    var cycleHotKey: Bool?

    var others: OthersOnSwitch { othersOnSwitch ?? (closeOthersOnSwitch == true ? .quit : .keep) }
}

enum ProfileCycle {
    /// The profile after `current`: among the running ones when two or more
    /// run, otherwise among all of them, so a single running profile rotates
    /// to the next one in the list.
    static func next(_ profiles: [Profile], running: Set<String>, current: String?) -> Profile? {
        let live = profiles.filter { running.contains($0.id) }
        let pool = live.count > 1 ? live : profiles
        guard !pool.isEmpty else { return nil }
        let index = pool.firstIndex { $0.id == current } ?? -1
        return pool[(index + 1) % pool.count]
    }
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
        var profiles = [Profile(id: "default", name: "Personal", dataDir: nil, color: 0, shareSessions: true)]
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
