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

        #expect(decoded.first == SearchTagSuggestion(english: "artist:test artist", localizedText: "画师测试", rawKey: "a:test artist"))
        #expect(decoded.last == SearchTagSuggestion(english: "female:sample", localizedText: nil, rawKey: "f:sample"))
    }

    @Test("Tag suggestions use a cached original-project database before networking")
    func cachedTagSuggestions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-tags-\(UUID().uuidString)")
        let cacheURL = root.appendingPathComponent("tag-translations-zh-rCN")
        defer { try? FileManager.default.removeItem(at: root) }

        let translation = Data("蓝色档案".utf8).base64EncodedString()
        let payload = Data("g:blue archive\r\(translation)\nf:sample\rbnVsbA==\n".utf8)
        var data = withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) }
        data.append(payload)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)

        let provider = TagSuggestionProvider(
            sourceURLs: [URL(string: "https://example.invalid/tags")!],
            cacheURL: cacheURL
        )
        let suggestions = try await provider.suggestions(for: "blue archive")

        #expect(suggestions == [SearchTagSuggestion(english: "group:blue archive", localizedText: "蓝色档案", rawKey: "g:blue archive")])
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

    @Test("Gallery list parser keeps the site's full title string like the reference client")
    func listParserKeepsFullTitle() throws {
        let html = """
        <html><body><table class="itg"><tr class="gtr0">
        <td><a href="https://e-hentai.org/g/102/gamma/"><div class="glink">English title | 日本語タイトル</div></a></td>
        </tr></table></body></html>
        """
        let page = try GalleryHTMLParser().parseList(data: Data(html.utf8), query: GalleryListQuery())

        #expect(page.items.first?.title == "English title | 日本語タイトル")
        #expect(page.items.first?.japaneseTitle == nil)
        #expect(page.items.first?.displayTitle(showJapaneseTitle: false) == "English title | 日本語タイトル")
        #expect(page.items.first?.displayTitle(showJapaneseTitle: true) == "English title | 日本語タイトル")
    }

    @Test("Gallery list parser does not include result tags in a fallback title")
    func listParserSeparatesFallbackTags() throws {
        let html = """
        <html><body><table class="itg"><tr class="gtr0">
        <td class="gl3m glname"><a href="https://e-hentai.org/g/103/delta/">
        <div>Clean title</div><div><div class="gt" title="language:english">english</div></div>
        </a></td>
        </tr></table></body></html>
        """
        let page = try GalleryHTMLParser().parseList(data: Data(html.utf8), query: GalleryListQuery())

        #expect(page.items.first?.title == "Clean title")
        #expect(page.items.first?.tags == ["language:english"])
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
        // The current site only embeds a few summary tags in list rows; the
        // full tag list arrives through the gdata API during filtering.
        #expect(page.items.first?.tags == ["language:english", "female:valentine"])
        #expect(page.items.first?.uploader == "valentines")
        #expect(page.items.first?.postedAt != nil)
        #expect(page.items.first?.simpleLanguage == "EN")
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
        #expect(detail.summary.japaneseTitle == "バレンタイン 2019")
        #expect(detail.summary.displayTitle(showJapaneseTitle: false) == "Valentines 2019")
        #expect(detail.summary.displayTitle(showJapaneseTitle: true) == "バレンタイン 2019")
        #expect(detail.summary.category == "Manga")
        #expect(detail.summary.uploader == "valentines")
        #expect(detail.summary.pageCount == 838)
        #expect(detail.summary.rating == 4.46)
        #expect(detail.summary.postedAt != nil)
        #expect(detail.language == "English")
        #expect(detail.fileSize == "128 MB")
        #expect(detail.favoriteCount == 1234)
        #expect(detail.descriptionText == nil)
        #expect(detail.tags == [
            "parody:blue archive",
            "artist:sample",
            "language:english",
            "male:furry",
            "other:full color",
            "other:artbook",
        ])
        #expect(detail.pages.map(\.index) == [0, 1])
        #expect(detail.pages.first?.previewURL?.absoluteString == "https://ehgt.org/7e/7a/430636/1366222-1.jpg")
    }

    @Test("Gallery detail parses clipped high-resolution previews like the reference client")
    func detailClippedPreviews() throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: "detail-preview-clip", withExtension: "html"))
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")
        let detail = try GalleryHTMLParser().parseDetail(
            data: Data(contentsOf: fixtureURL),
            key: key,
            site: .eHentai
        )

        #expect(detail.pages.count == 3)
        let first = try #require(detail.pages.first)
        #expect(first.index == 0)
        #expect(first.previewURL?.absoluteString == "https://ehgt.org/7e/7a/430636/1366222-01-full.jpg")
        #expect(first.previewClip == GalleryPreviewClip(xOffset: 100, width: 250, height: 156))
        #expect(first.previewClip?.cropRect == CGRect(x: 100, y: 0, width: 250, height: 156))

        let second = try #require(detail.pages[safe: 1])
        #expect(second.index == 1)
        #expect(second.previewClip == GalleryPreviewClip(xOffset: 50, width: 160, height: 240))

        let third = try #require(detail.pages[safe: 2])
        #expect(third.index == 2)
        #expect(third.previewClip == GalleryPreviewClip(xOffset: 20, width: 200, height: 300))
    }

    @Test("Gallery preview parsing covers the reference label and legacy formats")
    func detailPreviewFormatVariants() throws {
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")

        let labeledHTML = """
        <div id="gdt"><a href="https://e-hentai.org/s/a/1-1"><div><div title="Page 1: 1000x1500 width:200 height:300 (https://ehgt.org/x.jpg) -20px"></div></div></a></div>
        """
        let labeled = try GalleryHTMLParser().parsePreviewPage(
            data: Data(labeledHTML.utf8),
            key: key,
            site: .eHentai
        )
        #expect(labeled.pages.first?.previewClip == GalleryPreviewClip(xOffset: 20, width: 200, height: 300))
        #expect(labeled.pages.first?.previewURL?.absoluteString == "https://ehgt.org/x.jpg")

        let offsetlessHTML = """
        <div id="gdt"><a href="https://e-hentai.org/s/c/1-1"><div title="Page 1: 800x1200 width:160 height:240 (https://ehgt.org/z.jpg)"></div></a></div>
        """
        let offsetless = try GalleryHTMLParser().parsePreviewPage(
            data: Data(offsetlessHTML.utf8),
            key: key,
            site: .eHentai
        )
        #expect(offsetless.pages.first?.previewClip == GalleryPreviewClip(xOffset: 0, width: 160, height: 240))
        #expect(offsetless.pages.first?.previewURL?.absoluteString == "https://ehgt.org/z.jpg")

        let legacyHTML = """
        <div id="gdt"><div class="gdtm" style="height:156px"><div style="width:250px;height:156px;background:transparent url(https://ehgt.org/y.jpg) -100px 0 no-repeat"><a href="https://e-hentai.org/s/b/1-1"><img alt="01" src="https://ehgt.org/t.jpg" /></a></div></div></div>
        """
        let legacy = try GalleryHTMLParser().parsePreviewPage(
            data: Data(legacyHTML.utf8),
            key: key,
            site: .eHentai
        )
        #expect(legacy.pages.first?.index == 0)
        #expect(legacy.pages.first?.previewURL?.absoluteString == "https://ehgt.org/y.jpg")
        #expect(legacy.pages.first?.previewClip == GalleryPreviewClip(xOffset: 100, width: 250, height: 156))
    }

    @Test("Gallery detail follows preview pagination beyond the first 20 pages")
    func detailLoadsAllPreviewPages() async throws {
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")
        let transport = PreviewPaginationTransport(key: key)
        let client = EHClient(transport: transport)

        let detail = try await client.detail(for: key, site: .eHentai)

        #expect(detail.summary.pageCount == 26)
        #expect(detail.pages.map(\.index) == Array(0..<26))
        let previewIndexes = Set(await transport.requestURLs().compactMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "p" })?.value
                .flatMap(Int.init)
        })
        #expect(previewIndexes == Set([1]))
    }

    @Test("Gallery detail stream emits the first preview batch before pagination finishes")
    func detailStreamEmitsInitialSnapshot() async throws {
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")
        let transport = PreviewPaginationTransport(key: key, blockAdditionalPage: true)
        let client = EHClient(transport: transport)
        var iterator = client.detailStream(for: key, site: .eHentai).makeAsyncIterator()

        let initial = try await iterator.next()
        #expect(initial?.pages.map(\.index) == Array(0..<20))

        await transport.waitUntilAdditionalPageStarted()
        #expect(await transport.didStartAdditionalPage())
        await transport.releaseAdditionalPage()

        let final = try await iterator.next()
        #expect(final?.pages.map(\.index) == Array(0..<26))
        #expect(try await iterator.next() == nil)
    }

    @Test("Cancelled detail requests are not retried or reported as empty responses")
    func cancelledDetailRequestsAreNotRetried() async throws {
        let transport = CancellationTransport()
        let client = EHClient(transport: transport)
        let key = GalleryKey(gid: 1_366_222, token: "sample-token")

        do {
            _ = try await client.detail(for: key, site: .eHentai)
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected: a cancelled URLSession request is a lifecycle event.
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(await transport.requestCount() == 1)
    }

    @Test("Cancelled tasks do not retry ordinary transport errors")
    func cancelledTasksDoNotRetryOrdinaryTransportErrors() async throws {
        let transport = CancelledTaskTransport()
        let client = EHClient(transport: transport)
        let requestTask = Task {
            try await client.list(query: GalleryListQuery())
        }

        await transport.waitUntilStarted()
        requestTask.cancel()
        await transport.release()

        do {
            _ = try await requestTask.value
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation takes precedence over transport retries.
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(await transport.requestCount() == 1)
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

    @Test("Gallery summaries use batched gdata requests without loading detail pages")
    func gallerySummaries() async throws {
        let payload = #"""
        {
            "gmetadata": [{
                "gid": 100,
                "token": "alpha",
                "title": "English title",
                "title_jpn": "日本語タイトル",
                "thumb": "/t/sample.jpg",
                "category": "Manga",
                "filecount": "12",
                "posted": "2020-01-02 03:04",
                "rating": "4.5",
                "tags": ["artist:sample"]
            }]
        }
        """#
        let recording = RecordingTransport(data: Data(payload.utf8))
        let client = EHClient(transport: recording)
        let keys = (0..<26).map { GalleryKey(gid: Int64(100 + $0), token: "token-\($0)") }

        let summaries = try await client.gallerySummaries(for: keys, site: .eHentai)

        #expect(summaries.count == 2)
        #expect(summaries.first?.displayTitle(showJapaneseTitle: false) == "English title")
        #expect(summaries.first?.displayTitle(showJapaneseTitle: true) == "日本語タイトル")
        #expect(summaries.first?.pageCount == 12)
        #expect(summaries.first?.postedAt != nil)
        #expect(summaries.first?.thumbnailURL?.absoluteString == "https://e-hentai.org/t/sample.jpg")

        let requests = await recording.requestsSnapshot()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.path == "/api.php" })
        let firstBody = try #require(requests.first?.httpBody)
        let firstJSON = try #require(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        #expect(firstJSON["method"] as? String == "gdata")
        #expect((firstJSON["gidlist"] as? [[Any]])?.count == 25)

        let numericPostedPayload = #"""
        {
            "gmetadata": [{
                "gid": 100,
                "token": "alpha",
                "title": "Numeric posted",
                "posted": 1514458781
            }]
        }
        """#
        let numericPosted = try GalleryAPIParser().parse(
            data: Data(numericPostedPayload.utf8),
            site: .eHentai
        )
        #expect(numericPosted.first?.postedAt == Date(timeIntervalSince1970: 1_514_458_781))
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

    @Test("Gallery cache keeps static detail data, caches preview images, and clears only its own root")
    func galleryCacheStore() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-gallery-cache-\(UUID().uuidString)")
        let unrelatedFile = root.deletingLastPathComponent()
            .appendingPathComponent("ehviewer-download-sentinel-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: unrelatedFile)
        }

        try Data("download placeholder".utf8).write(to: unrelatedFile, options: .atomic)
        let store = GalleryCacheStore(root: root)
        let key = GalleryKey(gid: 42, token: "cached-token")
        let page = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://e-hentai.org/s/page-token/42-1")!,
            previewURL: URL(string: "https://ehgt.org/preview.jpg")!
        )
        let summary = GallerySummary(
            key: key,
            title: "Cached gallery",
            category: "Manga",
            pageCount: 1,
            rating: 4.5,
            ratingCount: 12,
            tags: ["artist:sample"]
        )
        let detail = GalleryDetail(
            summary: summary,
            pages: [page],
            tags: summary.tags,
            comments: [GalleryComment(id: "comment", author: "reader", body: "stale")],
            favoriteCount: 99,
            favoriteName: "收藏夹",
            ratingCount: 12
        )

        await store.save(detail, for: key, site: .eHentai)
        let cached = try #require(await store.detail(for: key, site: .eHentai))
        #expect(cached.summary.title == "Cached gallery")
        #expect(cached.tags == ["artist:sample"])
        #expect(cached.pages == [page])
        #expect(cached.comments.isEmpty)
        #expect(cached.favoriteCount == nil)
        #expect(cached.summary.rating == nil)
        #expect(cached.summary.ratingCount == nil)

        let image = GalleryPageImage(galleryKey: key, index: 0, imageURL: page.previewURL!)
        let imageData = try await store.imageData(for: image, resolution: .preview) {
            Data("preview".utf8)
        }
        #expect(imageData == Data("preview".utf8))
        #expect((await store.usage()).byteCount > 0)

        await store.removeAll()
        #expect((await store.usage()).byteCount == 0)
        #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private actor PreviewPaginationTransport: HTTPTransport {
    private let key: GalleryKey
    private let blockAdditionalPage: Bool
    private var requests: [URLRequest] = []
    private var additionalPageStarted = false
    private var additionalPageRelease: CheckedContinuation<Void, Never>?

    init(key: GalleryKey, blockAdditionalPage: Bool = false) {
        self.key = key
        self.blockAdditionalPage = blockAdditionalPage
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let previewPage = URLComponents(url: request.url ?? URL(string: "https://e-hentai.org/")!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "p" })?.value
            .flatMap(Int.init) ?? 0
        if blockAdditionalPage && previewPage == 1 {
            additionalPageStarted = true
            await withCheckedContinuation { continuation in
                additionalPageRelease = continuation
            }
        }
        let data = Self.previewHTML(
            key: key,
            startIndex: previewPage == 0 ? 0 : 20,
            count: previewPage == 0 ? 20 : 6,
            includeMetadata: previewPage == 0
        )
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://e-hentai.org/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(data.utf8), response)
    }

    func requestURLs() -> [URL] {
        requests.compactMap(\.url)
    }

    func waitUntilAdditionalPageStarted() async {
        for _ in 0..<200 {
            if additionalPageStarted { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func didStartAdditionalPage() -> Bool {
        additionalPageStarted
    }

    func releaseAdditionalPage() {
        additionalPageRelease?.resume()
        additionalPageRelease = nil
    }

    private static func previewHTML(key: GalleryKey, startIndex: Int, count: Int, includeMetadata: Bool) -> String {
        let links = (0..<count).map { offset in
            let pageNumber = startIndex + offset + 1
            return "<a href=\"https://e-hentai.org/s/page-token/\(key.gid)-\(pageNumber)\"><img src=\"https://ehgt.org/sample-\(pageNumber).jpg\"></a>"
        }.joined()
        let metadata = includeMetadata
            ? "<h1 id=\"gn\">Sample</h1><div id=\"gdd\"><dd>26 pages</dd></div>"
            : ""
        let pagination = includeMetadata
            ? "<table class=\"ptt\"><tr><td>1</td><td>2</td><td>&gt;</td></tr></table>"
            : ""
        return "<html><body>\(metadata)\(pagination)<div id=\"gdt\">\(links)</div></body></html>"
    }
}

private struct StubTransport: HTTPTransport {
    let data: Data
    let response: HTTPURLResponse

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (data, response)
    }
}

private actor CancellationTransport: HTTPTransport {
    private var requests = 0

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        throw URLError(.cancelled)
    }

    func requestCount() -> Int {
        requests
    }
}

private actor CancelledTaskTransport: HTTPTransport {
    private var requests = 0
    private var started = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        started = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        throw EHError.networkFailed("transport failure after cancellation")
    }

    func waitUntilStarted() async {
        for _ in 0..<200 {
            if started { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func requestCount() -> Int {
        requests
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

    func requestsSnapshot() -> [URLRequest] {
        requests
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
