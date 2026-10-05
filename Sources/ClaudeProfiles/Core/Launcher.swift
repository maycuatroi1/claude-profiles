import AppKit

enum LaunchError: LocalizedError {
    case claudeMissing

    var errorDescription: String? {
        switch self {
        case .claudeMissing: return "Claude.app was not found. Install Claude Desktop first."
        }
    }
}

enum Launcher {
    static func claudeAppURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeBundleID) { return url }
        let fallback = URL(fileURLWithPath: "/Applications/Claude.app")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    /// Bring a running profile forward, or start it. Starting pulls the shared
    /// Code sessions in first, while that profile is still closed.
    static func switchTo(_ profile: Profile, settings: ProfileSettings) async throws {
        if let app = ClaudeInstances.find(profile) {
            bringToFront(app)
            return
        }
        if settings.closeOthersOnSwitch == true {
            for other in settings.profiles where other.id != profile.id {
                if let app = ClaudeInstances.find(other) { _ = await terminate(app) }
            }
        }
        _ = SessionSync().run(settings.profiles, running: ClaudeInstances.runningIDs(settings.profiles))
        try await launch(profile)
    }

    static func launch(_ profile: Profile) async throws {
        guard let claude = claudeAppURL() else { throw LaunchError.claudeMissing }
        let config = NSWorkspace.OpenConfiguration()
        // Always a new instance: without it Launch Services would just
        // activate whichever Claude instance is already running.
        config.createsNewApplicationInstance = true
        config.activates = true
        if !profile.isDefault {
            try makePrivateDirectory(profile.dataURL)
            config.arguments = ["--user-data-dir=\(profile.dataURL.path)"]
        }
        _ = try await NSWorkspace.shared.openApplication(at: claude, configuration: config)
    }

    static func bringToFront(_ app: NSRunningApplication) {
        app.unhide()
        app.activate(options: [.activateAllWindows])
        // A reopen event is what a Dock click sends; it makes Claude show its
        // window again when the window was closed but the app kept running.
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        _ = try? event.sendEvent(options: [.noReply], timeout: 2)
    }

    /// Ask the instance to quit and wait for it, up to `timeout` seconds.
    static func terminate(_ app: NSRunningApplication, timeout: TimeInterval = 20) async -> Bool {
        guard app.terminate() || app.isTerminated else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return app.isTerminated
    }
}
