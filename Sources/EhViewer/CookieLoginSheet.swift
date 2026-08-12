import SwiftUI

struct CookieLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var cookie = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Cookie") {
                    TextField("ipb_member_id=…; ipb_pass_hash=…", text: $cookie, axis: .vertical)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    Text("必须包含 ipb_member_id 和 ipb_pass_hash；访问 ExHentai 还需要有效的 igneous（不能是 mystery/null）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cookie 登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await model.saveCookie(cookie) { dismiss() }
                        }
                    }
                    .disabled(cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
