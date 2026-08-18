/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI
import WebKit

#if os(iOS)
struct DocumentationWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL?
    let onExternalURL: @MainActor (URL) -> Void
    let onDocumentLink: @MainActor (DocumentationDocument) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExternalURL: onExternalURL, onDocumentLink: onDocumentLink)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.load(html: html, into: webView, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html: html, into: webView, baseURL: baseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onExternalURL: @MainActor (URL) -> Void
        private let onDocumentLink: @MainActor (DocumentationDocument) -> Void
        private var loadedHTML = ""

        init(
            onExternalURL: @escaping @MainActor (URL) -> Void,
            onDocumentLink: @escaping @MainActor (DocumentationDocument) -> Void
        ) {
            self.onExternalURL = onExternalURL
            self.onDocumentLink = onDocumentLink
        }

        func load(html: String, into webView: WKWebView, baseURL: URL?) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme?.caseInsensitiveCompare("ehviewer-doc") == .orderedSame,
               let host = url.host,
               let document = DocumentationDocument(rawValue: host.uppercased()) {
                onDocumentLink(document)
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) {
                onExternalURL(url)
                decisionHandler(.cancel)
                return
            }

            if url.isFileURL || url.scheme == "about" || url.scheme == nil {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
#else
struct DocumentationWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let onExternalURL: @MainActor (URL) -> Void
    let onDocumentLink: @MainActor (DocumentationDocument) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExternalURL: onExternalURL, onDocumentLink: onDocumentLink)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.load(html: html, into: webView, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(html: html, into: webView, baseURL: baseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onExternalURL: @MainActor (URL) -> Void
        private let onDocumentLink: @MainActor (DocumentationDocument) -> Void
        private var loadedHTML = ""

        init(
            onExternalURL: @escaping @MainActor (URL) -> Void,
            onDocumentLink: @escaping @MainActor (DocumentationDocument) -> Void
        ) {
            self.onExternalURL = onExternalURL
            self.onDocumentLink = onDocumentLink
        }

        func load(html: String, into webView: WKWebView, baseURL: URL?) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme?.caseInsensitiveCompare("ehviewer-doc") == .orderedSame,
               let host = url.host,
               let document = DocumentationDocument(rawValue: host.uppercased()) {
                onDocumentLink(document)
                decisionHandler(.cancel)
                return
            }

            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) {
                onExternalURL(url)
                decisionHandler(.cancel)
                return
            }

            if url.isFileURL || url.scheme == "about" || url.scheme == nil {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
#endif
