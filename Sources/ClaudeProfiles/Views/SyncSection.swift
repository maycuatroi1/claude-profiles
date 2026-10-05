import SwiftUI

struct SyncSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lịch sử phiên Code").font(.system(size: 12, weight: .semibold))
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.syncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Đồng bộ") { model.sync() }.controlSize(.small)
                }
            }
            Text(
                "Phiên mới được chép sang ngay. Bản cập nhật của phiên đã có chỉ chép sang khi profile nhận đang tắt, "
                    + "nên hãy khởi động lại profile đó để thấy. Lịch sử tab Chat nằm trên máy chủ của từng tài khoản, "
                    + "không chia sẻ được."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var status: String {
        guard let last = model.lastSync else { return "Chưa đồng bộ" }
        let time = last.date.formatted(date: .omitted, time: .shortened)
        return "\(time): \(last.report.summary)"
    }
}
