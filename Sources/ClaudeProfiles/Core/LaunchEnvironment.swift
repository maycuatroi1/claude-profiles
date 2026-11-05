import Foundation

/// The variables a Claude Code session sets for the commands it runs. Started
/// from such a session (`make install` in the Code tab), this app inherits
/// them, and so does every Claude it launches: the Code sessions of every
/// profile then carry one old session's socket, account and host session id.
enum LaunchEnvironment {
    static let prefixes = ["CLAUDE", "ANTHROPIC_", "OTEL_", "MCP_"]
    static let names: Set<String> = [
        "AI_AGENT", "API_TIMEOUT_MS", "BAGGAGE", "BETA_TRACING_ENDPOINT", "COREPACK_ENABLE_AUTO_PIN",
        "DISABLE_AUTOUPDATER", "DISABLE_MICROCOMPACT", "ENABLE_BETA_TRACING_DETAILED", "GIT_EDITOR",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "NODE_USE_SYSTEM_CA", "PYTHONDONTWRITEBYTECODE",
        "USE_LOCAL_OAUTH", "USE_STAGING_OAUTH",
    ]

    /// The names to drop: none unless the environment comes from Claude
    /// Code, and never this app's own CLAUDE_PROFILES_* overrides.
    static func inherited(_ env: [String: String]) -> [String] {
        guard env["CLAUDECODE"] != nil || env["CLAUDE_CODE_ENTRYPOINT"] != nil else { return [] }
        return env.keys.filter { name in
            !name.hasPrefix("CLAUDE_PROFILES_") && (names.contains(name) || prefixes.contains { name.hasPrefix($0) })
        }.sorted()
    }

    /// NSWorkspace hands this process's current environment to the apps it
    /// opens, so unsetting here keeps it out of every Claude started later.
    static func scrub() {
        for name in inherited(ProcessInfo.processInfo.environment) { unsetenv(name) }
    }
}
