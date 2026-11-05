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

    static func processArguments(_ pid: pid_t) -> [String] { processStrings(pid).args }

    /// argv and environment of another process of this user via
    /// KERN_PROCARGS2: argc, exec path, padding, argv, then the environment.
    /// When a name appears twice the first one wins, as with getenv.
    static func processStrings(_ pid: pid_t) -> (args: [String], env: [String: String]) {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return ([], [:]) }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return ([], [:]) }
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size && buffer[index] != 0 { index += 1 }
        while index < size && buffer[index] == 0 { index += 1 }
        var args: [String] = []
        var env: [String: String] = [:]
        var start = index
        while index < size {
            if buffer[index] == 0 {
                // An empty string after argv ends the environment.
                if index == start && args.count == argc { break }
                let text = String(decoding: buffer[start..<index], as: UTF8.self)
                if args.count < argc {
                    args.append(text)
                } else if let equals = text.firstIndex(of: "=") {
                    let name = String(text[..<equals])
                    if env[name] == nil { env[name] = String(text[text.index(after: equals)...]) }
                }
                start = index + 1
            }
            index += 1
        }
        return (args, env)
    }

    struct ProcessEntry {
        let pid: pid_t
        let parent: pid_t
        /// The short command name the kernel keeps (p_comm), at most 16 bytes.
        let name: String
    }

    static func processTable() -> [ProcessEntry] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        // Room for processes started between the two calls.
        size += size / 8
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / stride).map { proc in
            var comm = proc.kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return ProcessEntry(pid: proc.kp_proc.p_pid, parent: proc.kp_eproc.e_ppid, name: name)
        }
    }
}
