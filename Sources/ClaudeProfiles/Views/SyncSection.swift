import SwiftUI

struct SyncSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Code session history").font(.system(size: 12, weight: .semibold))
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.syncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Sync") { model.sync() }.controlSize(.small)
                }
            }
            Text(
                "New sessions are copied right away. A profile gets changes to sessions it already has "
                    + "only while it is closed, so restart it to see them. Chat tab history lives on "
                    + "Anthropic's servers per account and is not shared."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var status: String {
        guard let last = model.lastSync else { return "Not synced yet" }
        let time = last.date.formatted(date: .omitted, time: .shortened)
        return "\(time): \(last.report.summary)"
    }
}
