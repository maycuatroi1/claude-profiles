import AppKit
import SwiftUI

/// The profile you just switched to, shown for a moment in the middle of the
/// screen after ⌃⌥⇥: every profile is the same Claude app, so the Dock and
/// ⌘⇥ cannot tell them apart.
@MainActor
enum SwitchHUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ profile: Profile, detail: String?) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: HUDView(profile: profile, detail: detail))
        panel.contentView = host
        let size = host.fittingSize
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrame(
                NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height),
                display: true)
        }
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct HUDView: View {
    let profile: Profile
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            ProfileAvatar(profile: profile, size: 56)
            Text(profile.name).font(.system(size: 15, weight: .semibold))
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(minWidth: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
