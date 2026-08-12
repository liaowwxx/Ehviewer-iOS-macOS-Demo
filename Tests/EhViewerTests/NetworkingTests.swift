import Foundation
import Testing
import EHDomain
import EHNetworking

struct NetworkingTests {
    @Test("Original tag database format decodes English and localized suggestions")
    func tagSuggestionDatabase() throws {
        let translation = Data("画师测试".utf8).base64EncodedString()
        let payload = Data("a:test artist\r\(translation)\nf:sample\rbnVsbA==\n".utf8)
        let length = UInt32(payload.count).bigEndian
        var data = withUnsafeBytes(of: length) { Data($0) }
        data.append(payload)

        let decoded = try TagSuggestionProvider.decodeDatabase(data)

        #expect(decoded.first == SearchTagSuggestion(english: "artist:test artist", localizedText: "画师测试"))
        #expect(decoded.last == SearchTagSuggestion(english: "female:sample", localizedText: nil))
    }

    @Test("HTML list parser extracts gallery keys and cursor")
    func listParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
        let data = try Data(contentsOf: fixtureURL)
        let page = try GalleryHTMLParser().parseList(data: data, query: GalleryListQuery())
        #expect(page.items.count == 2)
        #expect(page.items.first?.key == GalleryKey(gid: 100, token: "alpha"))
        #expect(page.cursor?.nextPageURL?.absoluteString == "https://e-hentai.org/?page=1")
    }

    @Test("Search cursor accepts bottom navigation and JavaScript fallback")
    func searchCursorVariants() throws {
        let query = GalleryListQuery(site: .eHentai, kind: .search, searchText: "blue archive")
        let bottomNavigation = """
        <html><body>
        <div class="searchnav"><a id="dnext" href="/?f_search=blue+archive&amp;next=4113797">Next</a></div>
        </body></html>
        """
        let bottomPage = try GalleryHTMLParser().parseList(data: Data(bottomNavigation.utf8), query: query)
        #expect(bottomPage.cursor?.nextPageURL?.absoluteString == "https://e-hentai.org/?f_search=blue+archive&next=4113797")

        let scriptFallback = """
        <html><body><script>var nexturl="https:\\/\\/e-hentai.org\\/?f_search=blue+archive\\u0026next=4113700";</script></body></html>
        """
        let scriptPage = try GalleryHTMLParser().parseList(data: Data(scriptFallback.utf8), query: query)
        #expect(scriptPage.cursor?.nextPageURL?.absoluteString == "https://e-hentai.org/?f_search=blue+archive&next=4113700")
    }

    @Test("Gallery list parser handles the Android compact table layout")
    func compactListParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list-real", withExtension: "html"))
        let page = try GalleryHTMLParser().parseList(
            data: Data(contentsOf: fixtureURL),
            query: GalleryListQuery()
        )
        #expect(page.items.count == 1)
        #expect(page.items.first?.key == GalleryKey(gid: 1_366_222, token: "7e7a4305a4"))
        #expect(page.items.first?.pageCount == 26)
        #expect(page.items.first?.rating == 4)
        #expect(page.items.first?.tags == ["language:english"])
        #expect(page.items.first?.thumbnailURL?.absoluteString == "https://ehgt.org/t/7e/7a/430636-250.jpg")
    }

    @Test("Gallery detail parser extracts metadata and ordered page descriptors")
    func detailParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "detail", withExtension: "html"))
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")
        let detail = try GalleryHTMLParser().parseDetail(
            data: Data(contentsOf: fixtureURL),
            key: key,
            site: .eHentai
        )

        #expect(detail.summary.title == "Valentines 2019")
        #expect(detail.summary.secondaryTitle == "バレンタイン 2019")
        #expect(detail.summary.category == "Manga")
        #expect(detail.summary.pageCount == 838)
        #expect(detail.summary.rating == 4.46)
        #expect(detail.tags == ["artist:sample", "language:english"])
        #expect(detail.pages.map(\.index) == [0, 1])
        #expect(detail.pages.first?.previewURL?.absoluteString == "https://ehgt.org/7e/7a/430636/1366222-1.jpg")
    }

    @Test("Gallery page parser handles HTML response metadata")
    func pageHTMLParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "page", withExtension: "html"))
        let descriptor = GalleryPageDescriptor(
            galleryKey: GalleryKey(gid: 1_366_222, token: "sample-token"),
            index: 2,
            pageURL: URL(string: "https://e-hentai.org/s/sample/1366222-3")!
        )
        let image = try GalleryPageParser().parse(
            data: Data(contentsOf: fixtureURL),
            descriptor: descriptor,
            site: .eHentai
        )

        #expect(image.index == 2)
        #expect(image.imageURL.absoluteString == "http://69.30.203.46:8080/7e/7a/430636/15151-3/Valentines_2019_002.jpg")
        #expect(image.originImageURL?.absoluteString == "https://e-hentai.org/fullimg.php?gid=1366222&page=3&key=puxxvyg98a4")
        #expect(image.fileName == "Valentines_2019_002.jpg")
        #expect(image.width == 1280)
        #expect(image.height == 960)
        #expect(image.byteCount == 183_091)
        #expect(image.skipHathKey == "26664-430636")
        #expect(image.showKey == "ghz0e5m98a4")
    }

    @Test("Gallery page parser handles JSON response metadata")
    func pageJSONParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "page", withExtension: "json"))
        let descriptor = GalleryPageDescriptor(
            galleryKey: GalleryKey(gid: 1_366_222, token: "sample-token"),
            index: 2,
            pageURL: URL(string: "https://e-hentai.org/s/sample/1366222-3")!
        )
        let image = try GalleryPageParser().parse(
            data: Data(contentsOf: fixtureURL),
            descriptor: descriptor,
            site: .eHentai
        )

        #expect(image.imageURL.path.hasSuffix("Valentines_2019_002.jpg"))
        #expect(image.originImageURL?.absoluteString.contains("fullimg.php?gid=1366222&page=3") == true)
        #expect(image.width == 1280)
        #expect(image.height == 960)
        #expect(image.skipHathKey == "15151-430636")
    }

    @Test("List request maps subscriptions to the watched endpoint")
    func listKinds() throws {
        let request = try SiteRequestBuilder(site: .exHentai).galleryListRequest(
            query: GalleryListQuery(site: .exHentai, kind: .subscriptions)
        )
        #expect(request.url?.path == "/watched")
        #expect(request.url?.host == "exhentai.org")
    }

    @Test("HTTP client maps authentication status into a domain error")
    func clientStatusMapping() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://e-hentai.org/")!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        ))
        let client = EHClient(transport: StubTransport(data: Data(), response: response))
        do {
            _ = try await client.list(query: GalleryListQuery())
            Issue.record("expected authentication error")
        } catch let error as EHError {
            #expect(error == .authenticationRequired)
        }
    }

    @Test("Password login posts the reference form and persists response cookies")
    func passwordLogin() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://forums.e-hentai.org/index.php?act=Login&CODE=01")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "ipb_member_id=42; Path=/, ipb_pass_hash=secret; Path=/"]
        ))
        let vault = SessionVault(service: "EhViewerTests-\(UUID().uuidString)")
        let transport = StubTransport(
            data: Data("<p>You are now logged in as: test-user</p>".utf8),
            response: response
        )
        let client = EHClient(transport: transport, sessionVault: vault)
        let result = try await client.login(username: "test-user", password: "not-persisted")
        #expect(result.displayName == "test-user")
        #expect(try await vault.loadCookieHeader()?.contains("ipb_member_id=42") == true)
        #expect(try await vault.loadCookieHeader()?.contains("ipb_pass_hash=secret") == true)
        try? await vault.clear()
    }

    @Test("Password login does not succeed without persisted authentication cookies")
    func passwordLoginWithoutCookies() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://forums.e-hentai.org/index.php?act=Login&CODE=01")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let vault = SessionVault(service: "EhViewerMissingLoginCookieTests-\(UUID().uuidString)")
        let client = EHClient(
            transport: StubTransport(
                data: Data("<p>You are now logged in as: test-user</p>".utf8),
                response: response
            ),
            sessionVault: vault
        )

        do {
            _ = try await client.login(username: "test-user", password: "not-persisted")
            Issue.record("expected invalid cookie error")
        } catch let error as EHError {
            #expect(error == .invalidCookie)
        }
        #expect(try await vault.hasAuthenticatedSession() == false)
        try? await vault.clear()
    }

    @Test("ExHentai rebuilds the E-Hentai to ExHentai cookie chain after a rejected igneous")
    func exHentaiCookieBootstrap() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
        let listData = try Data(contentsOf: fixtureURL)
        let firstResponse = try #require(HTTPURLResponse(
            url: URL(string: "https://exhentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "igneous=mystery; Domain=.exhentai.org; Path=/"]
        ))
        let eHentaiResponse = try #require(HTTPURLResponse(
            url: URL(string: "https://e-hentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let issuedResponse = try #require(HTTPURLResponse(
            url: URL(string: "https://exhentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "igneous=real-session; Domain=.exhentai.org; Path=/"]
        ))
        let finalResponse = try #require(HTTPURLResponse(
            url: URL(string: "https://exhentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = SequenceTransport(responses: [
            (Data(), firstResponse),
            (Data("<html>e-hentai session</html>".utf8), eHentaiResponse),
            (Data(), issuedResponse),
            (listData, finalResponse)
        ])
        let vault = SessionVault(service: "EhViewerExHCookieTests-\(UUID().uuidString)")
        try await vault.clear()
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(transport: transport, sessionVault: vault)

        let page = try await client.list(query: GalleryListQuery(site: .exHentai))
        let cookieHeaders = await transport.cookieHeaders()

        #expect(page.items.isEmpty == false)
        #expect(cookieHeaders.count == 4)
        #expect(cookieHeaders[0]?.contains("igneous=") == false)
        #expect(cookieHeaders[1]?.contains("igneous=") == false)
        #expect(cookieHeaders[2]?.contains("igneous=") == false)
        #expect(cookieHeaders[3]?.contains("igneous=real-session") == true)
        #expect(try await vault.loadAuthenticatedCookieHeader()?.contains("igneous=real-session") == true)
        try await vault.clear()
    }

    @Test("ExHentai blank responses are access errors instead of empty result pages")
    func exHentaiBlankResponse() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://exhentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Set-Cookie": "igneous=mystery; Domain=.exhentai.org; Path=/"]
        ))
        let vault = SessionVault(service: "EhViewerExHBlankTests-\(UUID().uuidString)")
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")
        let client = EHClient(
            transport: SequenceTransport(responses: Array(repeating: (Data(), response), count: 5)),
            sessionVault: vault
        )

        do {
            _ = try await client.list(query: GalleryListQuery(site: .exHentai))
            Issue.record("expected ExHentai access denial")
        } catch let error as EHError {
            #expect(error == .exHentaiAccessDenied)
        }
        try await vault.clear()
    }

    @Test("Sad Panda is reported as ExHentai access denial")
    func sadPandaResponse() async throws {
        let response = try #require(HTTPURLResponse(
            url: URL(string: "https://exhentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Disposition": "inline; filename=\"sadpanda.jpg\"",
                "Content-Type": "image/gif",
                "Content-Length": "9615"
            ]
        ))
        let client = EHClient(transport: StubTransport(data: Data(repeating: 0, count: 9_615), response: response))

        do {
            _ = try await client.list(query: GalleryListQuery(site: .exHentai))
            Issue.record("expected ExHentai access denial")
        } catch let error as EHError {
            #expect(error == .exHentaiAccessDenied)
        }
    }

    @Test("Guest list requests work without a session cookie")
    func guestListRequest() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
        let recording = RecordingTransport(data: try Data(contentsOf: fixtureURL))
        let vault = SessionVault(service: "EhViewerGuestTests-\(UUID().uuidString)")
        let client = EHClient(transport: recording, sessionVault: vault)
        let page = try await client.list(query: GalleryListQuery(site: .eHentai, kind: .home))
        #expect(page.items.isEmpty == false)
        let request = try #require(await recording.lastRequest())
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Guest pagination follows the exact server cursor URL")
    func guestPaginationCursorRequest() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
        let recording = RecordingTransport(data: try Data(contentsOf: fixtureURL))
        let vault = SessionVault(service: "EhViewerGuestPaginationTests-\(UUID().uuidString)")
        let client = EHClient(transport: recording, sessionVault: vault)
        let cursorURL = try #require(URL(string: "https://e-hentai.org/?next=1366222&f_search=blue%20archive"))

        _ = try await client.list(
            query: GalleryListQuery(site: .eHentai, kind: .search, searchText: "blue archive", page: 1),
            pageURL: cursorURL
        )

        let request = try #require(await recording.lastRequest())
        #expect(request.url == cursorURL)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test("Image pipeline deduplicates fetches and survives memory eviction via disk")
    func imagePipelineDeduplication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ehviewer-image-cache-\(UUID().uuidString)")
        let pipeline = ImagePipeline(byteLimit: 1, diskRoot: root)
        let url = URL(string: "https://example.invalid/image.jpg")!
        let counter = FetchCounter()
        let first = try await pipeline.data(for: url) {
            await counter.increment()
            return Data("image".utf8)
        }
        let second = try await pipeline.data(for: url) {
            await counter.increment()
            return Data("different".utf8)
        }
        #expect(first == second)
        #expect(await counter.value == 1)
        await pipeline.removeAll()
    }

    @Test("Reference-shaped advanced HTML parses comments, Torrent, archive and watched tags")
    func advancedParsers() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "advanced", withExtension: "html"))
        let data = try Data(contentsOf: fixtureURL)
        let key = GalleryKey(gid: 1_366_222, token: "7e7a4305a4")
        let detail = try GalleryHTMLParser().parseDetail(data: data, key: key, site: .eHentai)
        #expect(detail.apiUID == 42)
        #expect(detail.apiKey == "abcdef")
        #expect(detail.ratingCount == 12)
        #expect(detail.comments.first?.author == "alice")
        #expect(detail.comments.first?.score == 7)
        #expect(detail.torrentCount == 1)
        #expect(detail.archiveURL?.absoluteString.contains("archiver.php") == true)

        let parser = AdvancedHTMLParser()
        #expect(try parser.parseTorrents(data: data, site: .eHentai).first?.name == "sample.torrent")
        #expect(try parser.parseArchiveOptions(data: data).map(\.resolution) == ["org", "res_1280"])
        #expect(try parser.parseWatchedTags(data: data).first?.name == "artist:sample")
        #expect(try parser.parseWatchedTags(data: data).first?.isWatched == true)
    }

    @Test("Comment parser renders escaped links and line breaks as readable text")
    func commentFormatting() throws {
        let html = """
        <div id="cdiv">
          <div class="c1">
            <div class="c3"><a>reader</a></div>
            <div class="c6">RAW: &lt;a href=\"https://example.com/g/1/\"&gt;https://example.com/g/1/&lt;/a&gt;&lt;br /&gt;翻译：中文</div>
          </div>
          <div class="c1">
            <div class="c3"><a>translator</a></div>
            <div class="c6"><a href="https://example.com/g/2/">第二个链接</a><br><br><strong>校对：</strong>完成</div>
          </div>
        </div>
        """
        let key = GalleryKey(gid: 1, token: "sample")
        let detail = try GalleryHTMLParser().parseDetail(data: Data(html.utf8), key: key, site: .eHentai)
        #expect(detail.comments.first?.body == "RAW: https://example.com/g/1/\n翻译：中文")
        #expect(detail.comments.last?.body == "第二个链接\n\n校对：完成")
    }

    @Test("Remote mutation requests use the reference endpoints and form/API payloads")
    func advancedRequests() async throws {
        let key = GalleryKey(gid: 1_366_222, token: "7e7a4305a4")
        let recording = RecordingTransport(data: Data(#"{"rating_avg":4.25,"rating_cnt":8}"#.utf8))
        let client = EHClient(transport: recording)

        try await client.setFavorite(for: key, site: .eHentai, category: 3, note: "keep")
        let favoriteRequest = try #require(await recording.lastRequest())
        #expect(favoriteRequest.url?.path == "/gallerypopups.php")
        #expect(String(decoding: try #require(favoriteRequest.httpBody), as: UTF8.self).contains("favcat=3"))

        _ = try await client.rateGallery(for: key, site: .eHentai, rating: 4.25, apiUID: 42, apiKey: "abcdef")
        let ratingRequest = try #require(await recording.lastRequest())
        #expect(ratingRequest.url?.path == "/api.php")
        #expect(String(decoding: try #require(ratingRequest.httpBody), as: UTF8.self).contains("rategallery"))
        #expect(String(decoding: try #require(ratingRequest.httpBody), as: UTF8.self).contains("\"rating\":9"))
    }

    @Test("Image search uploads the expected multipart fields and parses results")
    func imageSearchRequest() async throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "list", withExtension: "html"))
        let recording = RecordingTransport(data: try Data(contentsOf: fixtureURL))
        let client = EHClient(transport: recording)
        let result = try await client.imageSearch(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            fileName: "cover.jpg",
            site: .eHentai,
            options: ImageSearchOptions(similar: true, covers: true, expanded: true)
        )
        #expect(result.items.count == 2)
        let request = try #require(await recording.lastRequest())
        #expect(request.url?.absoluteString == "https://upld.e-hentai.org/image_lookup.php")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("name=\"sfile\"; filename=\"cover.jpg\""))
        #expect(body.contains("name=\"fs_similar\""))
        #expect(body.contains("name=\"fs_covers\""))
        #expect(body.contains("name=\"fs_exp\""))
        #expect(body.contains("name=\"f_sfile\""))
    }

    @Test("Image quota parser handles the original home page wording")
    func imageQuotaParser() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "home", withExtension: "html"))
        let quota = try AdvancedHTMLParser().parseImageQuota(data: Data(contentsOf: fixtureURL))
        #expect(quota.used == 4_672)
        #expect(quota.total == 5_000)
        #expect(quota.resetCost == 9_344)
    }
}

private struct StubTransport: HTTPTransport {
    let data: Data
    let response: HTTPURLResponse

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (data, response)
    }
}

private actor FetchCounter {
    private var count = 0

    func increment() { count += 1 }
    var value: Int { count }
}

private actor RecordingTransport: HTTPTransport {
    private let data: Data
    private var requests: [URLRequest] = []

    init(data: Data) {
        self.data = data
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = try #require(HTTPURLResponse(
            url: request.url ?? URL(string: "https://e-hentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        return (data, response)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}

private actor SequenceTransport: HTTPTransport {
    private let responses: [(Data, HTTPURLResponse)]
    private var requests: [URLRequest] = []

    init(responses: [(Data, HTTPURLResponse)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let index = min(requests.count - 1, responses.count - 1)
        return responses[index]
    }

    func cookieHeaders() -> [String?] {
        requests.map { $0.value(forHTTPHeaderField: "Cookie") }
    }
}
