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
