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
    @Published var busy: Set<String> = []
    @Published var lastSync: (date: Date, report: SyncReport)?
    @Published var syncing = false
    @Published var message: String?

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// `live: false` builds a still model for `--snapshot`: no sync, no timers.
    init(live: Bool = true) {
        settings = ProfileStore.load()
        refresh()
        guard live else { return }
        sync()
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
        frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
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
                if let problem = report.problems.first { self.message = "Đồng bộ lỗi: \(problem)" }
                self.refresh()
            }
        }
    }

    func open(_ profile: Profile) {
        guard !busy.contains(profile.id) else { return }
        busy.insert(profile.id)
        let settings = self.settings
        Task {
            do { try await Launcher.switchTo(profile, settings: settings) } catch { message = error.localizedDescription }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            busy.remove(profile.id)
            refresh()
        }
    }

    func quit(_ profile: Profile) {
        guard let app = running[profile.id] else { return }
        busy.insert(profile.id)
        Task {
            if !(await Launcher.terminate(app)) { message = "\(profile.name) chưa thoát. Hãy thử đóng từ cửa sổ Claude." }
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
                message = "\(profile.name) chưa thoát nên chưa khởi động lại được."
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
            message = "Thư mục này đã thuộc một profile khác."
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
        panel.title = "Chọn thư mục dữ liệu Claude có sẵn"
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

    var closeOthersOnSwitch: Bool {
        get { settings.closeOthersOnSwitch ?? false }
        set {
            settings.closeOthersOnSwitch = newValue
            persist()
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                message = "Không đổi được mục khởi động: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    private func persist() {
        do { try ProfileStore.save(settings) } catch { message = "Không lưu được cấu hình: \(error.localizedDescription)" }
    }
}
