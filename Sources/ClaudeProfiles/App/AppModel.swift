import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: ProfileSettings
    @Published var running: [String: NSRunningApplication] = [:]
    @Published var frontPID: pid_t = 0
    @Published var accounts: [String: AccountInfo] = [:]
    @Published var sessionCounts: [String: Int] = [:]
    /// Code sessions open right now, by profile id.
    @Published var sessions: [String: [RunningSession]] = [:]
    /// The Claude instance that was frontmost last; 0 when none runs.
    @Published var lastClaudePID: pid_t = 0
    @Published var canMoveWindows = WindowFrames.allowed
    @Published var notificationsAllowed = true
    @Published var busy: Set<String> = []
    @Published var lastSync: (date: Date, report: SyncReport)?
    @Published var syncing = false
    @Published var message: String?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var hotKey: HotKey?
    private var watchTimer: Timer?
    private let watcher = SessionWatcher()
    private let notifier = Notifier()

    /// `live: false` builds a still model for `--snapshot`: no sync, no timers.
    init(live: Bool = true) {
        settings = ProfileStore.load()
        refresh()
        guard live else {
            // A still picture shows what a sync would do now, without doing it.
            lastSync = (Date(), SessionSync(dryRun: true).run(profiles, running: Set(running.keys)))
            return
        }
        sync()
        updateHotKey()
        notifier.onOpen = { [weak self] profileID, sessionID in
            guard let profile = self?.profiles.first(where: { $0.id == profileID }) else { return }
            self?.open(profile, session: sessionID)
        }
        updateWatching()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.sync()
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let isClaude = app?.bundleIdentifier == claudeBundleID
                    Task { @MainActor in
                        guard let self else { return }
                        if name == NSWorkspace.didActivateApplicationNotification {
                            self.frontPID = app?.processIdentifier ?? 0
                            if isClaude { self.lastClaudePID = self.frontPID }
                        } else if isClaude {
                            self.refresh()
                            // A profile that just quit can now take updated records.
                            if name == NSWorkspace.didTerminateApplicationNotification { self.sync() }
                        }
                    }
                })
        }
    }

    var profiles: [Profile] { settings.profiles }

    func refresh() {
        let instances = ClaudeInstances.list()
        var map: [String: NSRunningApplication] = [:]
        for profile in profiles {
            if let app = ClaudeInstances.find(profile, in: instances) { map[profile.id] = app }
            accounts[profile.id] = AccountInfo.read(profile.dataURL)
            sessionCounts[profile.id] = SessionSync.sessionDir(profile).map { SessionSync.sessionFiles($0).count } ?? 0
        }
        running = map
        sessions = RunningSessions.list(profiles, instances: instances)
        let front = NSWorkspace.shared.frontmostApplication
        frontPID = front?.processIdentifier ?? 0
        if front?.bundleIdentifier == claudeBundleID {
            lastClaudePID = frontPID
        } else if !map.values.contains(where: { $0.processIdentifier == lastClaudePID }) {
            lastClaudePID = 0
        }
        canMoveWindows = WindowFrames.allowed
        if watchTimer != nil { notifier.checkPermission { [weak self] in self?.notificationsAllowed = $0 } }
    }

    /// The profile of the Claude used last, which the menu bar icon shows.
    var lastClaudeProfile: Profile? {
        guard lastClaudePID != 0 else { return nil }
        return profiles.first { running[$0.id]?.processIdentifier == lastClaudePID }
    }

    func isFront(_ profile: Profile) -> Bool {
        guard let app = running[profile.id] else { return false }
        return app.processIdentifier == frontPID
    }

    func sync() {
        guard !syncing else { return }
        syncing = true
        let profiles = self.profiles
        let runningIDs = Set(running.keys)
        Task.detached(priority: .utility) {
            let report = SessionSync().run(profiles, running: runningIDs)
            await MainActor.run {
                self.lastSync = (Date(), report)
                self.syncing = false
                if let problem = report.problems.first { self.message = "Sync problem: \(problem)" }
                self.refresh()
            }
        }
    }

    /// Every few seconds: which sessions are open, and which of them just
    /// finished or asked something.
    private func watchSessions() {
        let instances = ClaudeInstances.list()
        let open = RunningSessions.list(profiles, instances: instances)
        if open != sessions { sessions = open }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for event in watcher.poll(open) {
            guard let profile = profiles.first(where: { $0.id == event.session.profileID }) else { continue }
            // The session on screen in the Claude in front needs no notification.
            let onScreen = open[profile.id]?.max { ($0.lastFocused ?? .distantPast) < ($1.lastFocused ?? .distantPast) }
            if ClaudeInstances.find(profile, in: instances)?.processIdentifier == front, onScreen?.id == event.session.id {
                continue
            }
            notifier.post(event, profile: profile)
        }
    }

    private func updateWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        guard notifySessions else { return }
        notifier.start()
        notifier.checkPermission { [weak self] in self?.notificationsAllowed = $0 }
        watchSessions()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchSessions() }
        }
    }

    /// Switches to the profile; with `session`, also opens that Code session in it.
    func open(_ profile: Profile, session: String? = nil) {
        guard !busy.contains(profile.id) else { return }
        busy.insert(profile.id)
        let settings = self.settings
        let previous = running.values.first { $0.processIdentifier == lastClaudePID }
        Task {
            do {
                try await Launcher.switchTo(profile, settings: settings, from: previous)
                if let session, let app = ClaudeInstances.find(profile) { Launcher.showSession(session, in: app) }
            } catch {
                message = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            busy.remove(profile.id)
            refresh()
        }
    }

    /// ⌃⌥⇥: the next profile, with its name shown in the middle of the screen.
    func cycle() {
        let current = lastClaudeProfile?.id
        guard let next = ProfileCycle.next(profiles, running: Set(running.keys), current: current) else { return }
        SwitchHUD.show(next, detail: running[next.id] == nil ? "Starting…" : nil)
        open(next)
        // Count a quick second press from the new profile, before macOS
        // reports it frontmost.
        if let app = running[next.id] { lastClaudePID = app.processIdentifier }
    }

    func quit(_ profile: Profile) {
        guard let app = running[profile.id] else { return }
        busy.insert(profile.id)
        Task {
            if !(await Launcher.terminate(app)) { message = "\(profile.name) did not quit. Quit it from its Claude window." }
            busy.remove(profile.id)
            refresh()
        }
    }

    func restart(_ profile: Profile) {
        guard let app = running[profile.id] else { return open(profile) }
        busy.insert(profile.id)
        let settings = self.settings
        Task {
            if await Launcher.terminate(app) {
                do { try await Launcher.switchTo(profile, settings: settings) } catch { message = error.localizedDescription }
            } else {
                message = "\(profile.name) did not quit, so it was not restarted."
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            busy.remove(profile.id)
            refresh()
        }
    }

    func addProfile(name: String, share: Bool, existingFolder: URL? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? "Profile \(profiles.count + 1)" : trimmed
        let id = ProfileStore.uniqueID(ProfileStore.slug(display), taken: profiles.map(\.id))
        let folder = existingFolder ?? Paths.newProfilesDir.appendingPathComponent(id, isDirectory: true)
        if profiles.contains(where: { canonicalPath($0.dataURL.path) == canonicalPath(folder.path) }) {
            message = "That folder already belongs to another profile."
            return
        }
        let profile = Profile(
            id: id, name: display, dataDir: abbreviateHome(folder.path), color: profiles.count % palette.count,
            shareSessions: share)
        settings.profiles.append(profile)
        persist()
        refresh()
        open(profile)
    }

    func pickExistingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an existing Claude data folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = Paths.home
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = ProfileStore.prettyName(url.lastPathComponent, fallback: "Profile \(profiles.count + 1)")
        addProfile(name: name, share: true, existingFolder: url)
    }

    func update(_ profile: Profile, _ change: (inout Profile) -> Void) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        change(&settings.profiles[index])
        persist()
        refresh()
    }

    func remove(_ profile: Profile) {
        guard !profile.isDefault else { return }
        settings.profiles.removeAll { $0.id == profile.id }
        persist()
        refresh()
    }

    func move(_ profile: Profile, by offset: Int) {
        guard let index = settings.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let target = index + offset
        guard settings.profiles.indices.contains(target) else { return }
        settings.profiles.swapAt(index, target)
        persist()
    }

    func reveal(_ profile: Profile) {
        NSWorkspace.shared.activateFileViewerSelecting([profile.dataURL])
    }

    var othersOnSwitch: OthersOnSwitch {
        get { settings.others }
        set {
            settings.othersOnSwitch = newValue
            settings.closeOthersOnSwitch = newValue == .quit
            persist()
            if newValue == .hide && !WindowFrames.allowed { WindowFrames.askForAccess() }
        }
    }

    var notifySessions: Bool {
        get { settings.notifySessions ?? true }
        set {
            settings.notifySessions = newValue
            persist()
            updateWatching()
        }
    }

    var cycleHotKey: Bool {
        get { settings.cycleHotKey ?? true }
        set {
            settings.cycleHotKey = newValue
            persist()
            updateHotKey()
        }
    }

    private func updateHotKey() {
        guard cycleHotKey else {
            hotKey = nil
            return
        }
        guard hotKey == nil else { return }
        hotKey = HotKey.cycleProfiles { [weak self] in
            Task { @MainActor in self?.cycle() }
        }
        if hotKey == nil { message = "Another app already uses ⌃⌥⇥, so it cannot rotate profiles." }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                message = "Could not change the login item: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    private func persist() {
        do { try ProfileStore.save(settings) } catch { message = "Could not save settings: \(error.localizedDescription)" }
    }
}
