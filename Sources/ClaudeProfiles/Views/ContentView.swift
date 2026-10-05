import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(spacing: 2) {
                ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                    ProfileRow(profile: profile, index: index)
                }
            }
            .padding(6)
            if adding {
                Divider()
                AddProfileForm(onClose: { adding = false })
            } else {
                Button {
                    adding = true
                } label: {
                    Label("Add profile", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RowButtonStyle())
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            if let message = model.message {
                MessageBanner(text: message) { model.message = nil }
            }
            Divider()
            SyncSection()
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(palette[0])
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Profiles").font(.system(size: 13, weight: .semibold))
                Text("One Claude account per profile").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Quit other profiles when switching", isOn: $model.closeOthersOnSwitch)
            Toggle("Open at login", isOn: $model.launchAtLogin)
            HStack {
                Text("⌘1 to ⌘9 switch profiles").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
