// Claude Profiles: a menu bar switcher that runs Claude Desktop under several
// accounts side by side. Each profile is its own Electron user-data folder
// (`--user-data-dir`); the default profile is Claude's own folder.
//
// Code tab history is shared by copying session records
// (claude-code-sessions/<account>/<org>/local_*.json) between profiles; see
// SessionSync.swift. Chat tab history is stored server side per account and
// cannot be shared.
//
// The same binary also answers a few terminal commands; see CLI.swift.

import AppKit
import SwiftUI

struct ClaudeProfilesApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            Image(systemName: "person.2.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum Entry {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, CLI.commands.contains(first) {
            exit(CLI.run(args))
        }
        // One menu bar icon is enough: a second launch hands over and leaves.
        if let bundleID = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
                $0.processIdentifier != getpid() && !$0.isTerminated
            })
        {
            exit(0)
        }
        ClaudeProfilesApp.main()
    }
}
