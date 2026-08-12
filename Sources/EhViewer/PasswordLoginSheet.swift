import SwiftUI

struct PasswordLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    TextField("用户名", text: $username)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        #if os(iOS)
                        .textContentType(.password)
                        #endif
                }
                Text("密码仅用于本次登录请求，不会写入本地存储；成功后只保存站点会话 Cookie。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("密码登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isPasswordLoginInProgress {
                        ProgressView()
                    } else {
                        Button("登录") {
                            Task {
                                if await model.login(username: username, password: password) { dismiss() }
                            }
                        }
                        .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
