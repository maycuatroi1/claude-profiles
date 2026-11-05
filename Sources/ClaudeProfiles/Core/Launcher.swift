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
    ///
    /// The other running profiles stay, hide or quit as the settings say.
    /// When they hide, the profile you switch to takes the window frame of
    /// `previous`, the Claude you switch away from, so one window seems to
    /// change account.
    static func switchTo(_ profile: Profile, settings: ProfileSettings, from previous: NSRunningApplication? = nil)
        async throws
    {
        let mode = settings.others
        let instances = ClaudeInstances.list()
        let others = settings.profiles.filter { $0.id != profile.id }.compactMap { ClaudeInstances.find($0, in: instances) }
        let frame = mode == .hide ? previous.flatMap { $0.isTerminated ? nil : WindowFrames.frame(of: $0) } : nil
        if let app = ClaudeInstances.find(profile, in: instances) {
            if let frame, app != previous { WindowFrames.setFrame(frame, of: app) }
            bringToFront(app)
            if mode == .hide { hide(others) }
            return
        }
        if mode == .quit {
            for app in others { _ = await terminate(app) }
        }
        _ = SessionSync().run(settings.profiles, running: ClaudeInstances.runningIDs(settings.profiles))
        let app = try await launch(profile)
        if mode == .hide {
            if let frame { await WindowFrames.place(app, at: frame) }
            hide(others)
        }
    }

    static func hide(_ apps: [NSRunningApplication]) {
        for app in apps where !app.isHidden && !app.isTerminated { app.hide() }
    }

    @discardableResult
    static func launch(_ profile: Profile) async throws -> NSRunningApplication {
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
        return try await NSWorkspace.shared.openApplication(at: claude, configuration: config)
    }

    static func bringToFront(_ app: NSRunningApplication) {
        app.unhide()
        app.activate(options: [.activateAllWindows])
        // A reopen event is what a Dock click sends; it makes Claude show its
        // window again when the window was closed but the app kept running.
        send(appleEvent(AEEventClass(kCoreEventClass), AEEventID(kAEReopenApplication), to: app))
    }

    /// Opens one Code session in this instance through the claude:// link
    /// Claude registers, sent to this process only: Launch Services would
    /// hand the link to whichever Claude it picks.
    static func showSession(_ sessionID: String, in app: NSRunningApplication) {
        guard sessionID.hasPrefix("local_"), var link = URLComponents(string: "claude://code/continue") else { return }
        link.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        guard let url = link.string else { return }
        let event = appleEvent(AEEventClass(kInternetEventClass), AEEventID(kAEGetURL), to: app)
        event.setParam(NSAppleEventDescriptor(string: url), forKeyword: AEKeyword(keyDirectObject))
        send(event)
    }

    private static func appleEvent(_ eventClass: AEEventClass, _ id: AEEventID, to app: NSRunningApplication)
        -> NSAppleEventDescriptor
    {
        NSAppleEventDescriptor(
            eventClass: eventClass, eventID: id,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: app.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    private static func send(_ event: NSAppleEventDescriptor) {
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
