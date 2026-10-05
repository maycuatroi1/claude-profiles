import AppKit
import SwiftUI

enum CLI {
    static let commands: Set<String> = [
        "--help", "-h", "--version", "--list", "--open", "--sync", "--render-icon", "--snapshot",
    ]

    static let usage = """
        Claude Profiles: run Claude Desktop under several accounts.

        Usage:
          ClaudeProfiles                     start the menu bar app
          ClaudeProfiles --list [--json]     list profiles and their state
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

    static func open(_ query: String) -> Int32 {
        let settings = ProfileStore.load()
        let needle = query.lowercased()
        guard
            let profile = settings.profiles.first(where: { $0.id == needle })
                ?? settings.profiles.first(where: { $0.name.lowercased() == needle })
        else { return fail("no profile named \(query); see --list") }
        do {
            try runBlocking { try await Launcher.switchTo(profile, settings: settings) }
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
        // The menu bar window draws its own material; offscreen there is none.
        let view = ContentView().environmentObject(AppModel(live: false))
            .background(Color(nsColor: .windowBackgroundColor))
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
