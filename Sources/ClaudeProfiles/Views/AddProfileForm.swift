import SwiftUI

struct AddProfileForm: View {
    @EnvironmentObject var model: AppModel
    var onClose: () -> Void
    @State private var name = ""
    @State private var share = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile mới").font(.system(size: 12, weight: .semibold))
            TextField("Tên, ví dụ: Công ty", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Toggle("Chia sẻ lịch sử phiên Code với các profile khác", isOn: $share)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Text("Claude sẽ mở một cửa sổ mới. Đăng nhập tài khoản cho profile này ở đó.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Dùng thư mục có sẵn…") {
                    onClose()
                    model.pickExistingFolder()
                }
                .controlSize(.small)
                Spacer()
                Button("Huỷ", action: onClose).controlSize(.small)
                Button("Tạo và mở", action: create)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func create() {
        model.addProfile(name: name, share: share)
        onClose()
    }
}
