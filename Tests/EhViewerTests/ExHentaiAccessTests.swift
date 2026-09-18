import Foundation
import Testing
import EHDomain
import EHDownloads
@testable import EHNetworking
@testable import EhViewerPreview
import WebKit

struct ExHentaiAccessTests {
    @Test("External redirects strip cookies and write-preserving redirects are stopped")
    func redirectPolicy() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let delegate = SiteRedirectDelegate()
        var original = URLRequest(url: URL(string: "https://exhentai.org/")!)
        original.httpMethod = "GET"
        original.setValue("ipb_member_id=42; ipb_pass_hash=secret", forHTTPHeaderField: "Cookie")
        var external = original
        external.url = URL(string: "https://external.invalid/image.jpg")!
        let redirected: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: session.dataTask(with: original), willPerformHTTPRedirection: response(status: 302), newRequest: external) {
                continuation.resume(returning: $0)
            }
        }
        #expect(redirected?.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(redirected?.url == external.url)
        original.httpMethod = "POST"
        let writeRedirect: URLRequest? = await withCheckedContinuation { continuation in
            delegate.urlSession(session, task: session.dataTask(with: original), willPerformHTTPRedirection: response(status: 307), newRequest: original) {
                continuation.resume(returning: $0)
            }
        }
        #expect(writeRedirect == nil)
    }

    @Test("Late rejected igneous does not erase a refreshed cookie")
    func lateRejectedCookie() async throws {
        let vault = SessionVault(service: "EX-late-cookie-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let snapshot = try await vault.snapshot()
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret; igneous=valid", ifCurrent: snapshot)
        try await vault.saveSetCookieHeaders(["igneous=mystery; Domain=.exhentai.org; Path=/"], url: URL(string: "https://exhentai.org/")!, ifCurrent: snapshot)
        #expect(try await vault.hasExHentaiSession())
        await vault.invalidatePendingRequests()
        #expect(await vault.isCurrent(snapshot) == false)
        #expect(try await vault.hasAuthenticatedSession())
        try await vault.clear()
    }

    @Test("EX access denial places downloads in the authentication state", .timeLimit(.minutes(1)))
    func downloadAuthenticationState() async throws {
        let coordinator = DownloadCoordinator(pageLoader: { _ in throw EHError.exHentaiAccessDenied })
        let events = await coordinator.events()
        let key = GalleryKey(gid: 1, token: "download-auth")
        let page = GalleryPageDescriptor(galleryKey: key, index: 0, pageURL: URL(string: "https://exhentai.org/s/token/1-1")!)
        await coordinator.enqueue(key: key, title: "Test", pages: [page])
        for await event in events {
            if case .changed(let job) = event, job.state != .queued && job.state != .running {
                #expect(job.state == .authenticationRequired)
                break
            }
        }
    }

    @Test("Cookie fields accept values and matching name prefixes")
    func cookieFields() {
        let values = CookieLoginValues(memberID: " 42 ", passwordHash: "ipb_pass_hash=abc==", igneous: "igneous=valid")
        #expect(values.cookieHeader == "igneous=valid; ipb_member_id=42; ipb_pass_hash=abc==")
        #expect(CookieLoginValues(memberID: "42", passwordHash: "secret").cookieHeader == "ipb_member_id=42; ipb_pass_hash=secret")
        #expect(CookieLoginValues(memberID: "", passwordHash: "secret").cookieHeader == nil)
        #expect(CookieLoginValues(memberID: "42", passwordHash: " ").cookieHeader == nil)
    }

    @Test("Cookie fields reject placeholders and pasted headers", arguments: ["mystery", " NULL ", "abc; other=value", "abc\n", "ipb_pass_hash=abc"])
    func invalidCookieField(_ input: String) {
        let values = CookieLoginValues(memberID: "42", passwordHash: "secret", igneous: input)
        #expect(values.error(for: CookieHeader.igneousName) != nil)
        #expect(values.cookieHeader == nil)
    }

    @Test("Old response cookies and refresh results cannot restore an exited account")
    func conditionalCookieWrites() async throws {
        let vault = SessionVault(service: "EX-conditional-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=old")
        let old = try await vault.snapshot()
        try await vault.clear()
        #expect(try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=old; igneous=valid", ifCurrent: old) == false)
        #expect(try await vault.saveSetCookieHeaders(["ipb_member_id=42; Path=/", "ipb_pass_hash=old; Path=/"], url: URL(string: "https://exhentai.org/")!, ifCurrent: old) == false)
        #expect(try await vault.loadCookieHeader() == nil)
        try await vault.saveCookieHeader("ipb_member_id=99; ipb_pass_hash=new")
        #expect(try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=old", ifCurrent: old) == false)
        #expect(try await vault.loadCookieHeader() == "ipb_member_id=99; ipb_pass_hash=new")
        try await vault.clear()
    }

    @Test("Blank HTTP errors retain their status and do not bootstrap", arguments: [429, 509, 503])
    func blankHTTPError(_ status: Int) async throws {
        let transport = AccessSequence([(Data(), response(status: status))])
        let vault = SessionVault(service: "EX-status-\(UUID())")
        let client = EHClient(transport: transport, sessionVault: vault)
        let expected: EHError = status == 429 ? .rateLimited : status == 509 ? .bandwidthLimited : .httpStatus(status)
        await #expect(throws: expected) { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        #expect(await transport.requests().allSatisfy { $0.url?.host == "exhentai.org" })
    }

    @Test("Read-only gdata POST is replayed with the original body")
    func gdataRecovery() async throws {
        let payload = Data(#"{"gmetadata":[{"gid":100,"token":"alpha","title":"Test","category":"Manga","filecount":"1","filesize":100,"expunged":false,"rating":"4","posted":"1700000000","tags":[]}]}"#.utf8)
        let transport = AccessSequence([
            (Data(), response()),
            (Data("<html>EH</html>".utf8), response(host: "e-hentai.org")),
            (Data(), response(headers: ["Set-Cookie": "igneous=valid; Domain=.exhentai.org; Path=/"])),
            (payload, response(path: "/api.php"))
        ])
        let vault = SessionVault(service: "EX-gdata-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)
        let result = try await client.gallerySummaryBatch(for: [GalleryKey(gid: 100, token: "alpha")], site: .exHentai)
        #expect(result.responses.count == 1)
        let requests = await transport.requests()
        #expect(requests.count == 4)
        #expect(requests.first?.httpBody == requests.last?.httpBody)
        #expect(requests.last?.value(forHTTPHeaderField: "Cookie")?.contains("igneous=valid") == true)
        try await vault.clear()
    }

    @Test("Writes are not retried or refreshed", arguments: [200, 403, 503])
    func writeDoesNotReplay(_ status: Int) async throws {
        let transport = AccessSequence([(Data(), response(status: status))])
        let vault = SessionVault(service: "EX-write-\(UUID())")
        let client = EHClient(transport: transport, sessionVault: vault)
        let expected: EHError = status == 503 ? .httpStatus(503) : .exHentaiAccessDenied
        await #expect(throws: expected) { try await client.resetImageQuota(site: .exHentai) }
        #expect(await transport.requests().count == 1)
    }

    @Test("Site restriction pages and unexpected redirects are classified")
    func restrictedResponses() async throws {
        let vault = SessionVault(service: "EX-restricted-\(UUID())")
        let limited = EHClient(transport: AccessSequence([(Data("<img src='https://exhentai.org/img/kokomade.jpg'>".utf8), response())]), sessionVault: vault)
        await #expect(throws: EHError.siteAccessLimited) { try await limited.list(query: GalleryListQuery(site: .exHentai)) }
        let redirected = EHClient(transport: AccessSequence([(Data("<html>external</html>".utf8), response(host: "example.org"))]), sessionVault: vault)
        await #expect(throws: EHError.invalidResponse) { try await redirected.list(query: GalleryListQuery(site: .exHentai)) }
    }

    @Test("A failed production cookie refresh does not run a second bootstrap")
    func failedProductionRefresh() async throws {
        let transport = EmptyAccessRefresher()
        let vault = SessionVault(service: "EX-empty-refresh-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)
        await #expect(throws: EHError.exHentaiAccessDenied) { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        #expect(await transport.sendCount == 1)
        #expect(await transport.refreshCount == 1)
        try await vault.clear()
    }

    @Test("A login redirect triggers recovery while an empty media response does not")
    func loginRedirectAndEmptyMedia() async throws {
        let vault = SessionVault(service: "EX-redirect-\(UUID())")
        let redirect = AccessSequence([(Data("<html>Login</html>".utf8), response(host: "forums.e-hentai.org", path: "/index.php?act=Login&CODE=00"))])
        let client = EHClient(transport: redirect, sessionVault: vault)
        await #expect(throws: EHError.exHentaiAccessDenied) { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        let transport = AccessSequence([(Data(), response(path: "/t/image.jpg"))])
        let media = EHClient(transport: transport, sessionVault: vault)
        let image = GalleryPageImage(galleryKey: GalleryKey(gid: 1, token: "a"), index: 0, imageURL: URL(string: "https://exhentai.org/t/image.jpg")!)
        await #expect(throws: EHError.invalidResponse) { try await media.imageData(for: image, resolution: .original) }
        #expect(await transport.requests().count == 1)
    }

    @Test("External media never receives authentication cookies")
    func externalMediaCookies() async throws {
        let url = URL(string: "https://external.invalid/image.jpg")!
        let transport = AccessSequence([(Data([1, 2, 3]), response(host: "external.invalid", path: "/image.jpg"))])
        let vault = SessionVault(service: "EX-media-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret; igneous=valid")
        let client = EHClient(transport: transport, sessionVault: vault)
        _ = try await client.imageData(for: GalleryPageImage(galleryKey: GalleryKey(gid: 1, token: "a"), index: 0, imageURL: url), resolution: .original)
        #expect(await transport.requests().first?.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(!CookieHeader.isTrustedURL(URL(string: "https://exhentai.org.evil.invalid/")!))
        #expect(!CookieHeader.isTrustedURL(URL(string: "http://exhentai.org/")!))
        try await vault.clear()
    }

    @Test("Web login chooses a complete forum account without mixing domains")
    func webCookieAccountPair() throws {
        func cookie(_ name: String, _ value: String, _ domain: String) throws -> HTTPCookie {
            try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"]))
        }
        let cookies = try [
            cookie("ipb_member_id", "99", ".exhentai.org"), cookie("ipb_pass_hash", "ex", ".exhentai.org"), cookie("igneous", "ex-igneous", ".exhentai.org"),
            cookie("ipb_member_id", "42", "forums.e-hentai.org"), cookie("ipb_pass_hash", "forum", "forums.e-hentai.org")
        ]
        let values = WebLoginCookieSupport.authenticationValues(from: cookies)
        #expect(values == ["ipb_member_id": "42", "ipb_pass_hash": "forum"])
        #expect(WebLoginCookieSupport.authenticationValues(from: [cookies[0], cookies[4]]).isEmpty)
    }

    @Test("Concurrent EX failures share a production refresh")
    func concurrentRefresh() async throws {
        let latch = AccessLatch()
        let transport = RefreshingAccessTransport(latch: latch)
        let vault = SessionVault(service: "EX-concurrent-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)
        let first = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await latch.waitStarted()
        let second = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await transport.waitInitialRequests(2)
        await latch.release()
        _ = try await first.value
        _ = try await second.value
        #expect(await transport.refreshCount == 1)
        try await vault.clear()
    }

    @Test("Cancellation prevents replay without cancelling the shared refresh")
    func cancelledRefreshCaller() async throws {
        let latch = AccessLatch()
        let transport = RefreshingAccessTransport(latch: latch)
        let vault = SessionVault(service: "EX-cancel-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)
        let request = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await latch.waitStarted()
        request.cancel()
        await latch.release()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(await transport.replayCount == 0)
        #expect(try await vault.hasExHentaiSession())
        try await vault.clear()
    }

    @Test("An in-flight refresh cannot restore a logged-out session")
    func logoutDuringRefresh() async throws {
        let latch = AccessLatch()
        let transport = RefreshingAccessTransport(latch: latch)
        let vault = SessionVault(service: "EX-logout-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)
        let request = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await latch.waitStarted()
        try await vault.clear()
        await latch.release()
        await #expect(throws: CancellationError.self) { try await request.value }
        #expect(try await vault.loadCookieHeader() == nil)
        #expect(await transport.replayCount == 0)
    }

    @Test("A new account can refresh before the old account refresh finishes", .timeLimit(.minutes(1)))
    func accountSwitchDuringRefresh() async throws {
        let oldLatch = AccessLatch()
        let newLatch = AccessLatch()
        let transport = SwitchingAccessTransport(oldLatch: oldLatch, newLatch: newLatch)
        let vault = SessionVault(service: "EX-switch-\(UUID())")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=old")
        let client = EHClient(transport: transport, sessionVault: vault)
        let oldRequest = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await oldLatch.waitStarted()
        try await vault.saveCookieHeader("ipb_member_id=99; ipb_pass_hash=new")
        let newRequest = Task { try await client.list(query: GalleryListQuery(site: .exHentai)) }
        await newLatch.waitStarted()
        await newLatch.release()
        _ = try await newRequest.value
        await oldLatch.release()
        await #expect(throws: CancellationError.self) { try await oldRequest.value }
        #expect(try await vault.loadCookieHeader() == "igneous=new-valid; ipb_member_id=99; ipb_pass_hash=new")
        try await vault.clear()
    }
}

private actor EmptyAccessRefresher: HTTPTransport, ExHentaiCookieRefreshing {
    private(set) var sendCount = 0
    private(set) var refreshCount = 0
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sendCount += 1
        return (Data(), response())
    }
    func refreshExHentaiCookie(authenticationHeader: String) async throws -> String? {
        refreshCount += 1
        return nil
    }
}

private actor SwitchingAccessTransport: HTTPTransport, ExHentaiCookieRefreshing {
    let oldLatch: AccessLatch
    let newLatch: AccessLatch
    init(oldLatch: AccessLatch, newLatch: AccessLatch) {
        self.oldLatch = oldLatch
        self.newLatch = newLatch
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.value(forHTTPHeaderField: "Cookie")?.contains("igneous=new-valid") == true {
            let url = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
            return (try Data(contentsOf: url), response())
        }
        return (Data(), response())
    }
    func refreshExHentaiCookie(authenticationHeader: String) async throws -> String? {
        if authenticationHeader.contains("ipb_member_id=42") {
            await oldLatch.begin()
            return "old-valid"
        }
        await newLatch.begin()
        return "new-valid"
    }
}

private func response(host: String = "exhentai.org", path: String = "/", status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://\(host)\(path)")!, statusCode: status, httpVersion: nil, headerFields: headers)!
}

private actor AccessSequence: HTTPTransport {
    let responses: [(Data, HTTPURLResponse)]
    private var recorded: [URLRequest] = []
    init(_ responses: [(Data, HTTPURLResponse)]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        return responses[min(recorded.count - 1, responses.count - 1)]
    }
    func requests() -> [URLRequest] { recorded }
}

private actor AccessLatch {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    func waitStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func begin() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }
    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor RefreshingAccessTransport: HTTPTransport, ExHentaiCookieRefreshing {
    let latch: AccessLatch
    private(set) var refreshCount = 0
    private(set) var replayCount = 0
    private var initialCount = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(latch: AccessLatch) { self.latch = latch }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.value(forHTTPHeaderField: "Cookie")?.contains("igneous=valid") == true {
            replayCount += 1
            let url = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
            return (try Data(contentsOf: url), response())
        }
        initialCount += 1
        let ready = waiters.filter { initialCount >= $0.0 }
        waiters.removeAll { initialCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        return (Data(), response())
    }
    func waitInitialRequests(_ count: Int) async {
        if initialCount >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func refreshExHentaiCookie(authenticationHeader: String) async throws -> String? {
        refreshCount += 1
        await latch.begin()
        return "valid"
    }
}
