import AppKit
import SwiftUI
import UserNotifications

enum CLI {
    static let commands: Set<String> = [
        "--help", "-h", "--version", "--list", "--sessions", "--watch", "--notify-test", "--open", "--sync", "--render-icon", "--snapshot",
    ]

    static let usage = """
        Claude Profiles: run Claude Desktop under several accounts.

        Usage:
          ClaudeProfiles                     start the menu bar app
          ClaudeProfiles --list [--json]     list profiles and their state
          ClaudeProfiles --sessions [--json] Code sessions open in each running profile
          ClaudeProfiles --watch             print when an open session finishes or asks a question
          ClaudeProfiles --notify-test       post a test notification and print the permission
          ClaudeProfiles --open <profile>    switch to a profile (id or name)
          ClaudeProfiles --sync [--dry-run]  copy Code session records between profiles
          ClaudeProfiles --render-icon DIR   write the app iconset (used by the installer)
          ClaudeProfiles --snapshot PNG [--dark]  draw the menu window to a PNG, to check the layout
        """

    static func run(_ args: [String]) -> Int32 {
        switch args[0] {
        case "--version":
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
        case "--list":
            list(json: args.contains("--json"))
        case "--sessions":
            sessions(json: args.contains("--json"))
        case "--watch":
            watch()
        case "--notify-test":
            return notifyTest()
        case "--open":
            guard args.count > 1 else { return fail("--open needs a profile id or name") }
            return open(args.dropFirst().joined(separator: " "))
        case "--sync":
            sync(dryRun: args.contains("--dry-run"))
        case "--render-icon":
            guard args.count > 1 else { return fail("--render-icon needs a folder") }
            do { try IconRenderer.writeIconset(to: URL(fileURLWithPath: args[1], isDirectory: true)) } catch {
                return fail("could not render the icon: \(error.localizedDescription)")
            }
        case "--snapshot":
            guard args.count > 1 else { return fail("--snapshot needs a .png path") }
            return MainActor.assumeIsolated {
                snapshot(to: URL(fileURLWithPath: args[1]), dark: args.contains("--dark"))
            }
        default:
            print(usage)
        }
        return 0
    }

    static func list(json: Bool) {
        let settings = ProfileStore.load()
        let instances = ClaudeInstances.list()
        let rows: [[String: Any]] = settings.profiles.map { profile in
            let account = AccountInfo.read(profile.dataURL)
            let count = SessionSync.sessionDir(profile).map { SessionSync.sessionFiles($0).count } ?? 0
            return [
                "id": profile.id, "name": profile.name, "dataDir": abbreviateHome(profile.dataURL.path),
                "running": ClaudeInstances.find(profile, in: instances) != nil,
                "account": account.accountUUID ?? NSNull(), "codeSessions": count,
                "shareSessions": profile.shareSessions,
            ]
        }
        if json {
            let data = try? JSONSerialization.data(
                withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data ?? Data(), as: UTF8.self))
            return
        }
        for row in rows {
            let mark = (row["running"] as? Bool) == true ? "*" : " "
            let account = (row["account"] as? String).map { String($0.prefix(8)) } ?? "signed out"
            let share = (row["shareSessions"] as? Bool) == true ? "shared" : "not shared"
            print(
                "\(mark) \(row["id"]!)  \(row["name"]!)  [\(account)]  \(row["codeSessions"]!) Code sessions, \(share)  \(row["dataDir"]!)"
            )
        }
    }

    static func sessions(json: Bool) {
        let settings = ProfileStore.load()
        let open = RunningSessions.list(settings.profiles, instances: ClaudeInstances.list())
        if json {
            let dates = ISO8601DateFormatter()
            let rows: [[String: Any]] = settings.profiles.flatMap { profile in
                (open[profile.id] ?? []).map { session in
                    [
                        "profile": profile.id, "session": session.id, "title": session.title,
                        "cwd": session.cwd ?? NSNull(), "pid": Int(session.pid),
                        "lastActivity": session.lastActivity.map { dates.string(from: $0) } ?? NSNull(),
                        "alsoOpenIn": session.alsoOpenIn,
                    ]
                }
            }
            let data = try? JSONSerialization.data(
                withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            print(String(decoding: data ?? Data(), as: UTF8.self))
            return
        }
        var any = false
        for profile in settings.profiles {
            guard let sessions = open[profile.id], !sessions.isEmpty else { continue }
            any = true
            print("\(profile.name) (\(profile.id))")
            for session in sessions {
                let age = shortAge(session.lastActivity)
                let place = session.cwd.map(abbreviateHome) ?? ""
                let warning = session.alsoOpenIn.isEmpty ? "" : "  also open in \(session.alsoOpenIn.joined(separator: ", "))"
                print("  \(age.padding(toLength: 4, withPad: " ", startingAt: 0)) \(session.title)  \(place)\(warning)")
            }
        }
        if !any { print("no Code session is open in a running profile") }
    }

    /// What the notifications would say, as it happens, until interrupted.
    static func watch() {
        let settings = ProfileStore.load()
        let names = Dictionary(uniqueKeysWithValues: settings.profiles.map { ($0.id, $0.name) })
        let watcher = SessionWatcher()
        setvbuf(stdout, nil, _IOLBF, 0)
        var first = true
        while true {
            let open = RunningSessions.list(settings.profiles, instances: ClaudeInstances.list())
            let events = watcher.poll(open)
            if first {
                first = false
                for session in open.values.flatMap({ $0 }) {
                    let state = watcher.state(of: session).map { "\($0)" } ?? "no transcript"
                    print("\(names[session.profileID] ?? session.profileID)  \(state)  \(session.title)")
                }
                print("watching; ctrl-c stops")
            }
            for event in events {
                let time = Date().formatted(date: .omitted, time: .standard)
                let kind = event.kind == .finished ? "finished" : "asks"
                print("\(time)  \(names[event.session.profileID] ?? event.session.profileID)  \(kind)  \(event.session.title)")
            }
            // Spinning the run loop keeps NSWorkspace's list of apps current.
            RunLoop.main.run(until: Date().addingTimeInterval(2))
        }
    }

    /// Asks for the notification permission, posts one notification and
    /// says whether macOS lets them through. Run from the installed app.
    static func notifyTest() -> Int32 {
        guard Bundle.main.bundleIdentifier != nil else { return fail("run the binary inside Claude Profiles.app") }
        let center = UNUserNotificationCenter.current()
        var answer: (granted: Bool, error: Error?)?
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in answer = (granted, error) }
        while answer == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let error = answer?.error { return fail("notifications refused: \(error.localizedDescription)") }
        guard answer?.granted == true else {
            return fail("notifications are off for Claude Profiles; turn them on in System Settings, Notifications")
        }
        let content = UNMutableNotificationContent()
        content.title = "Claude Profiles"
        content.body = "Notifications work."
        var posted: Error??
        center.add(UNNotificationRequest(identifier: "test", content: content, trigger: nil)) { posted = .some($0) }
        while posted == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        if let error = posted ?? nil { return fail(error.localizedDescription) }
        print("posted a test notification")
        return 0
    }

    static func open(_ query: String) -> Int32 {
        let settings = ProfileStore.load()
        let needle = query.lowercased()
        guard
            let profile = settings.profiles.first(where: { $0.id == needle })
                ?? settings.profiles.first(where: { $0.name.lowercased() == needle })
        else { return fail("no profile named \(query); see --list") }
        do {
            let front = NSWorkspace.shared.frontmostApplication
            let previous = front?.bundleIdentifier == claudeBundleID ? front : nil
            try runBlocking { try await Launcher.switchTo(profile, settings: settings, from: previous) }
        } catch {
            return fail(error.localizedDescription)
        }
        print("opened \(profile.name)")
        return 0
    }

    static func sync(dryRun: Bool) {
        let settings = ProfileStore.load()
        let report = SessionSync(dryRun: dryRun)
            .run(settings.profiles, running: ClaudeInstances.runningIDs(settings.profiles))
        print("\(dryRun ? "dry run: " : "")added \(report.added), updated \(report.updated), profiles \(report.participants)")
        for problem in report.problems { FileHandle.standardError.write(Data("problem: \(problem)\n".utf8)) }
    }

    /// Draw the menu window offscreen, with the real profiles, into a PNG.
    @MainActor
    static func snapshot(to url: URL, dark: Bool) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // The menu bar window draws its own material and frame; offscreen there
        // is neither, so draw a rounded panel with a soft shadow around it.
        let view = ContentView().environmentObject(AppModel(live: false))
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            .padding(32)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return fail("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return fail("no png") }
        do { try png.write(to: url) } catch { return fail(error.localizedDescription) }
        print(url.path)
        return 0
    }

    static func fail(_ text: String) -> Int32 {
        FileHandle.standardError.write(Data("error: \(text)\n".utf8))
        return 1
    }

    /// Run async work from the synchronous CLI path, spinning the main run loop
    /// so AppKit callbacks can still arrive.
    static func runBlocking(_ work: @escaping () async throws -> Void) throws {
        final class Box: @unchecked Sendable {
            var result: Result<Void, Error>?
        }
        let box = Box()
        Task {
            do {
                try await work()
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
        }
        while box.result == nil { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
        try box.result?.get()
    }
}
