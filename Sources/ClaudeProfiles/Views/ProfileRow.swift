import AppKit
import SwiftUI

struct ProfileRow: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let index: Int
    @State private var hovering = false
    @State private var renaming = false
    @State private var draft = ""

    private var isRunning: Bool { model.running[profile.id] != nil }
    private var tint: Color { palette[profile.color % palette.count] }

    var body: some View {
        HStack(spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("Tên profile", text: $draft, onCommit: commitRename)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                } else {
                    HStack(spacing: 6) {
                        Text(profile.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if model.isFront(profile) {
                            Text("đang dùng")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(tint.opacity(0.18)))
                                .foregroundStyle(tint)
                        }
                    }
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.busy.contains(profile.id) {
                ProgressView().controlSize(.small).frame(width: 70)
            } else {
                Button(isRunning ? "Chuyển tới" : "Mở") { model.open(profile) }
                    .controlSize(.small)
                    .modifier(QuickSwitchShortcut(index: index))
            }
            actionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !renaming { model.open(profile) } }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(isRunning ? tint : tint.opacity(0.18))
            Text(initials(profile.name))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isRunning ? Color.white : tint)
        }
        .frame(width: 30, height: 30)
        .overlay(alignment: .bottomTrailing) {
            if isRunning {
                Circle().fill(Color.green).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [isRunning ? "Đang chạy" : "Đã tắt"]
        let account = model.accounts[profile.id]
        if account?.signedIn != true {
            parts.append("chưa đăng nhập")
        } else {
            parts.append("\(model.sessionCounts[profile.id] ?? 0) phiên Code")
        }
        if !profile.shareSessions { parts.append("không chia sẻ") }
        return parts.joined(separator: ", ")
    }

    private var actionsMenu: some View {
        Menu {
            Button("Đổi tên…") {
                draft = profile.name
                renaming = true
            }
            Menu("Màu") {
                ForEach(palette.indices, id: \.self) { colorIndex in
                    Button(colorNames[colorIndex]) { model.update(profile) { $0.color = colorIndex } }
                }
            }
            Toggle(
                "Chia sẻ lịch sử phiên Code",
                isOn: Binding(
                    get: { profile.shareSessions },
                    set: { value in model.update(profile) { $0.shareSessions = value } }))
            Divider()
            if isRunning {
                Button("Khởi động lại") { model.restart(profile) }
                Button("Thoát profile này") { model.quit(profile) }
            }
            Button("Mở thư mục dữ liệu") { model.reveal(profile) }
            Divider()
            Button("Đưa lên") { model.move(profile, by: -1) }.disabled(index == 0)
            Button("Đưa xuống") { model.move(profile, by: 1) }.disabled(index == model.profiles.count - 1)
            if !profile.isDefault {
                Divider()
                Button("Gỡ khỏi danh sách (giữ dữ liệu)") { model.remove(profile) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func commitRename() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { model.update(profile) { $0.name = name } }
        renaming = false
    }
}

func initials(_ name: String) -> String {
    let words = name.split(separator: " ").prefix(2)
    let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
    return letters.isEmpty ? "?" : letters
}

struct QuickSwitchShortcut: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        } else {
            content
        }
    }
}
