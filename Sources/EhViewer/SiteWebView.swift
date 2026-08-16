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

#if os(iOS)
struct SiteWebView: UIViewRepresentable {
    let url: URL
    let onReady: @MainActor (WKWebView) -> Void
    let onNavigationFinished: @MainActor (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFinished: onNavigationFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        onReady(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationFinished: @MainActor (WKWebView) -> Void

        init(onNavigationFinished: @escaping @MainActor (WKWebView) -> Void) {
            self.onNavigationFinished = onNavigationFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            onNavigationFinished(webView)
        }
    }
}
#else
struct SiteWebView: NSViewRepresentable {
    let url: URL
    let onReady: @MainActor (WKWebView) -> Void
    let onNavigationFinished: @MainActor (WKWebView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationFinished: onNavigationFinished)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        onReady(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigationFinished: @MainActor (WKWebView) -> Void

        init(onNavigationFinished: @escaping @MainActor (WKWebView) -> Void) {
            self.onNavigationFinished = onNavigationFinished
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            onNavigationFinished(webView)
        }
    }
}
#endif
