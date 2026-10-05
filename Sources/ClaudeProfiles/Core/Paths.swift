import Foundation

let claudeBundleID = "com.anthropic.claudefordesktop"
let sessionsFolder = "claude-code-sessions"

enum Paths {
    static let env = ProcessInfo.processInfo.environment
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Where this app keeps profiles.json and the sync state. Not named
    /// "Claude..." so Claude's own sibling-install scan never looks at it.
    static var supportDir: URL {
        if let override = env["CLAUDE_PROFILES_HOME"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return home.appendingPathComponent("Library/Application Support/tech.omelet.ClaudeProfiles", isDirectory: true)
    }

    static var configFile: URL { supportDir.appendingPathComponent("profiles.json") }
    static var stateFile: URL { supportDir.appendingPathComponent("sync-state.json") }
    static var newProfilesDir: URL { supportDir.appendingPathComponent("Profiles", isDirectory: true) }

    /// Claude's own data folder: what a Claude started without
    /// `--user-data-dir` uses, whatever the overrides say.
    static var claudeDataDir: URL {
        home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    }

    /// The default profile's folder; tests point it elsewhere.
    static var defaultDataDir: URL {
        if let override = env["CLAUDE_PROFILES_DEFAULT_DATA"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return claudeDataDir
    }
}

func expandTilde(_ path: String) -> String { (path as NSString).expandingTildeInPath }

func abbreviateHome(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: expandTilde(path)).standardizedFileURL.resolvingSymlinksInPath().path
}

func isUUID(_ text: String) -> Bool { UUID(uuidString: text) != nil }

func readJSONObject(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

func makePrivateDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
}
