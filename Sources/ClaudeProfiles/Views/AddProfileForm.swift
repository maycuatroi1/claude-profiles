import SwiftUI

struct AddProfileForm: View {
    @EnvironmentObject var model: AppModel
    var onClose: () -> Void
    @State private var name = ""
    @State private var share = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New profile").font(.system(size: 12, weight: .semibold))
            TextField("Name, for example Work", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            Toggle("Share Code sessions with other profiles", isOn: $share)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Text("Claude opens a new window. Sign in there with this profile's account.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use Existing Folder…") {
                    onClose()
                    model.pickExistingFolder()
                }
                .controlSize(.small)
                Spacer()
                Button("Cancel", action: onClose).controlSize(.small)
                Button("Create and Open", action: create)
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
