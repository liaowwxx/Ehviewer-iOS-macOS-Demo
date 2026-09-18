import Foundation

/// Explicit Cookie headers must never follow a redirect to an external host.
final class SiteRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = request
        if request.url.map(CookieHeader.isTrustedURL) != true {
            redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        // A redirect must not implicitly replay a write request (307/308).
        if task.originalRequest?.httpMethod?.uppercased() == "POST",
           request.httpMethod?.uppercased() == "POST" {
            completionHandler(nil)
        } else {
            completionHandler(redirected)
        }
    }
}
