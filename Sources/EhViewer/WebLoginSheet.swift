/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import WebKit

struct WebLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?
    @State private var isCompleting = false
    @State private var isEstablishingSession = false
    @State private var exHentaiRetryCount = 0
    @State private var loginTask: Task<Void, Never>?
    @State private var isActive = true
    @State private var loginError: String?

    private let loginURL = URL(string: "https://forums.e-hentai.org/index.php?act=Login&CODE=00")!
    private let eHentaiURL = URL(string: "https://e-hentai.org/")!
    private let exHentaiURL = URL(string: "https://exhentai.org/")!

    var body: some View {
        NavigationStack {
            SiteWebView(
                url: loginURL,
                onReady: { webView = $0 },
                onNavigationFinished: { inspectLoginState(in: $0, reportMissingCookies: false) },
                onNavigationFailed: { error in
                    guard isActive, (error as? URLError)?.code != .cancelled else { return }
                    loginTask?.cancel()
                    isCompleting = false
                    isEstablishingSession = false
                    loginError = error.localizedDescription
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(isEstablishingSession ? "正在连接 ExHentai" : "网页登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { cancelLogin(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCompleting {
                        ProgressView()
                    } else {
                        Button("完成登录") {
                            guard let webView else { return }
                            inspectLoginState(in: webView, reportMissingCookies: true)
                        }
                        .disabled(webView == nil)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let loginError {
                    Text(loginError).font(.callout).padding().frame(maxWidth: .infinity)
                        .background(.regularMaterial)
                }
            }
        }
        .onDisappear { cancelLogin() }
    }

    private func cancelLogin() {
        isActive = false
        loginTask?.cancel()
        webView?.stopLoading()
    }

    private func inspectLoginState(in webView: WKWebView, reportMissingCookies: Bool) {
        guard isActive, isCompleting == false else { return }
        loginError = nil
        isCompleting = true
        loginTask = Task { @MainActor in
            if let cookieHeader = await WebLoginCookieSupport.exHentaiAuthenticationHeader(from: webView) {
                guard isActive, !Task.isCancelled else { return }
                let saved = await model.saveCookie(cookieHeader)
                isCompleting = false
                if saved { dismiss() }
                return
            }

            guard await WebLoginCookieSupport.copyBaseAuthenticationCookies(from: webView) else {
                isCompleting = false
                if reportMissingCookies {
                    loginError = String(localized: "网页登录尚未完成，请先在网页中成功登录。")
                }
                return
            }
            guard isActive, !Task.isCancelled else { return }

            isEstablishingSession = true
            let host = webView.url?.host?.lowercased()
            if host == "exhentai.org" {
                if exHentaiRetryCount < 3 {
                    exHentaiRetryCount += 1
                    do {
                        try await Task.sleep(for: .milliseconds(exHentaiRetryCount == 1 ? 1_000 : 1_500))
                    } catch { return }
                    guard isActive, !Task.isCancelled else { return }
                    isCompleting = false
                    webView.load(URLRequest(url: exHentaiURL))
                } else {
                    isCompleting = false
                    if let baseHeader = await WebLoginCookieSupport.baseAuthenticationHeader(from: webView) {
                        guard isActive, !Task.isCancelled else { return }
                        if await model.saveCookie(baseHeader) {
                            model.errorMessage = String(localized: "E-Hentai 登录成功，ExHentai 会话尚未建立；访问 ExHentai 时会再次尝试连接。")
                            dismiss()
                        }
                    } else {
                        loginError = String(localized: "登录 Cookie 已取得，但 ExHentai 没有签发有效的 igneous。请确认账号具备 ExHentai 权限后重试。")
                    }
                }
            } else if host == "e-hentai.org" {
                isCompleting = false
                webView.load(URLRequest(url: exHentaiURL))
            } else {
                isCompleting = false
                webView.load(URLRequest(url: eHentaiURL))
            }
        }
    }
}
