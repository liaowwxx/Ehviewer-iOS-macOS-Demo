import SwiftUI
import WebKit
import EHDomain

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCookieSheet = false
    @State private var showingWebLogin = false
    @State private var showingPasswordLogin = false
    @State private var newFilter = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("站点") {
                Picker("画廊站点", selection: $model.site) {
                    ForEach(SiteMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: model.site) { _, _ in model.persistSettings() }
                HStack {
                    Label(
                        model.isGuestMode ? "游客浏览" : "已登录",
                        systemImage: model.isGuestMode ? "person" : "person.crop.circle.badge.checkmark"
                    )
                    Spacer()
                    Text(model.isGuestMode ? "公开内容" : "账户会话")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("session-status")
                .accessibilityLabel("会话状态")
                .accessibilityValue(model.isGuestMode ? "游客浏览" : "已登录")
            }
            Section("登录") {
                Button("用户名和密码登录", systemImage: "person.badge.key") { showingPasswordLogin = true }
                Button("通过网页登录", systemImage: "safari") { showingWebLogin = true }
                Button("通过 Cookie 登录", systemImage: "key") { showingCookieSheet = true }
                Button("清除会话 Cookie", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.clearSession() }
                }
                Text("密码只在网页登录页面中使用；会话 Cookie 由 Keychain 管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("隐私") {
                Button(model.appLockEnabled ? "关闭应用锁" : "启用应用锁", systemImage: model.appLockEnabled ? "lock.open" : "lock") {
                    Task { await model.setAppLockEnabled(model.appLockEnabled == false) }
                }
                Text("启用后，应用进入后台再回来时需要 Face ID、Touch ID 或设备密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("版本", value: "0.1 基线")
                Text("游客模式仅访问站点公开内容；登录会话 Cookie 由 Keychain 管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("过滤规则") {
                ForEach(model.filterRules, id: \.pattern) { rule in
                    Toggle(rule.pattern, isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in Task { await model.setFilterRule(pattern: rule.pattern, isEnabled: enabled) } }
                    ))
                }
                HStack {
                    TextField("添加标题或标签关键词", text: $newFilter)
                    Button("添加") {
                        let pattern = newFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard pattern.isEmpty == false else { return }
                        newFilter = ""
                        Task { await model.setFilterRule(pattern: pattern, isEnabled: true) }
                    }
                    .disabled(newFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings_title")
        .sheet(isPresented: $showingCookieSheet) { CookieLoginSheet() }
        .sheet(isPresented: $showingWebLogin) { WebLoginSheet() }
        .sheet(isPresented: $showingPasswordLogin) { PasswordLoginSheet() }
        .task { await model.loadFilterRules() }
    }
}

private struct PasswordLoginSheet: View {
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
                        #endif
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
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

private struct CookieLoginSheet: View {
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
                    Text("只粘贴 Cookie，不要输入密码。提交前请确认来源可信。")
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

private struct WebLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?

    var body: some View {
        NavigationStack {
            SiteWebView(url: URL(string: "https://\(model.site.host)/login.php")!) { webView in
                self.webView = webView
                Task { @MainActor in
                    let cookieHeader = try? await model.sessionVault.loadCookieHeader()
                    await CookieWebViewSupport.apply(cookieHeader, to: webView.configuration.websiteDataStore.httpCookieStore, host: model.site.host)
                    webView.load(URLRequest(url: URL(string: "https://\(model.site.host)/login.php")!))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("网页登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") { saveCookies() }
                        .disabled(webView == nil)
                }
            }
        }
    }

    private func saveCookies() {
        guard let webView else { return }
        let host = model.site.host
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let cookieHeader = cookies
                .filter { cookie in
                    cookie.domain == host || cookie.domain.hasSuffix(".\(host)")
                }
                .sorted { $0.name < $1.name }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            Task { @MainActor in
                if await model.saveCookie(cookieHeader) { dismiss() }
            }
        }
    }
}

private enum CookieWebViewSupport {
    @MainActor
    static func apply(_ header: String?, to store: WKHTTPCookieStore, host: String) async {
        guard let header else { return }
        for pair in header.split(separator: ";") {
            let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { continue }
            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cookie = HTTPCookie(properties: [
                .domain: ".\(host)",
                .path: "/",
                .name: name,
                .value: value
            ]) else { continue }
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }
}

#if os(iOS)
private struct SiteWebView: UIViewRepresentable {
    let url: URL
    let onReady: (WKWebView) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.allowsBackForwardNavigationGestures = true
        onReady(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#else
private struct SiteWebView: NSViewRepresentable {
    let url: URL
    let onReady: (WKWebView) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        onReady(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
#endif
