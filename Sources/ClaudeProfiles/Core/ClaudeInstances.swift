import AppKit
import Darwin

struct ClaudeInstance {
    let app: NSRunningApplication
    /// Canonical user-data folder, nil when the process arguments were unreadable.
    let dataDir: String?
}

enum ClaudeInstances {
    static func list() -> [ClaudeInstance] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == claudeBundleID && !$0.isTerminated }
            .map { app in
                let args = processArguments(app.processIdentifier)
                guard !args.isEmpty else { return ClaudeInstance(app: app, dataDir: nil) }
                let dir = userDataDir(args).map(canonicalPath) ?? canonicalPath(Paths.claudeDataDir.path)
                return ClaudeInstance(app: app, dataDir: dir)
            }
    }

    static func find(_ profile: Profile, in instances: [ClaudeInstance]? = nil) -> NSRunningApplication? {
        let key = canonicalPath(profile.dataURL.path)
        return (instances ?? list()).first { $0.dataDir == key }?.app
    }

    static func runningIDs(_ profiles: [Profile]) -> Set<String> {
        let instances = list()
        return Set(profiles.filter { find($0, in: instances) != nil }.map(\.id))
    }

    static func userDataDir(_ args: [String]) -> String? {
        for (index, arg) in args.enumerated() {
            if arg.hasPrefix("--user-data-dir=") { return String(arg.dropFirst("--user-data-dir=".count)) }
            if arg == "--user-data-dir", index + 1 < args.count { return args[index + 1] }
        }
        return nil
    }

    /// argv of another process via KERN_PROCARGS2: argc, exec path, padding, argv.
    static func processArguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        var args: [String] = []
        var start = index
        while index < size && args.count < argc {
            if buffer[index] == 0 {
                args.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return args
    }
}
