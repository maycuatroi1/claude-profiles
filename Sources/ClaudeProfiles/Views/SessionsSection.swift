import SwiftUI

/// The Code sessions open right now in each running profile. Clicking one
/// opens it in its profile.
struct SessionsSection: View {
    @EnvironmentObject var model: AppModel

    private static let rowHeight: CGFloat = 40
    private static let headerHeight: CGFloat = 22
    private static let maxHeight: CGFloat = 300

    private var groups: [(profile: Profile, sessions: [RunningSession])] {
        model.profiles.compactMap { profile in
            guard let sessions = model.sessions[profile.id], !sessions.isEmpty else { return nil }
            return (profile, sessions)
        }
    }

    var body: some View {
        let groups = self.groups
        let count = groups.reduce(0) { $0 + $1.sessions.count }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("Open Code sessions").font(.system(size: 12, weight: .semibold))
                Spacer()
                if count > 0 { Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8)
            if groups.isEmpty {
                Text("No Code session is open in a running profile.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            } else if CGFloat(groups.count) * Self.headerHeight + CGFloat(count) * Self.rowHeight > Self.maxHeight {
                ScrollView { list(groups) }.frame(height: Self.maxHeight)
            } else {
                list(groups)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private func list(_ groups: [(profile: Profile, sessions: [RunningSession])]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups, id: \.profile.id) { group in
                HStack(spacing: 6) {
                    Circle().fill(palette[group.profile.color % palette.count]).frame(width: 7, height: 7)
                    Text(group.profile.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(height: Self.headerHeight)
                ForEach(group.sessions) { session in
                    Button {
                        model.open(group.profile, session: session.id)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(RowButtonStyle())
                    .help("Open in \(group.profile.name)")
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: RunningSession

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.system(size: 12)).lineLimit(1)
                if let cwd = session.cwd {
                    Text(abbreviateHome(cwd))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if !session.alsoOpenIn.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Also open in \(session.alsoOpenIn.joined(separator: ", ")). Close it in one of them.")
            }
            Text(shortAge(session.lastActivity))
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
