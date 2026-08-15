import Foundation
import Testing
import EHDomain
import EHNetworking

struct DomainTests {
    @Test("Search composer follows the original tag completion syntax")
    func searchQueryComposer() throws {
        #expect(SearchQueryComposer.suggestionFragment(in: "language:english  blue archive") == "blue archive")
        #expect(SearchQueryComposer.suggestionFragment(in: "language:english blue archive") == "blue archive")
        #expect(SearchQueryComposer.suggestionFragment(in: "f:\"big breasts$\" blue") == "blue")
        #expect(SearchQueryComposer.suggestionFragment(in: "artist:") == "")
        #expect(SearchQueryComposer.searchSyntax(for: "artist:john doe") == "a:\"john doe$\"")
        #expect(
            SearchQueryComposer.completing(tag: "female:big breasts", in: "language:english  big")
                == "language:english f:\"big breasts$\""
        )
        #expect(
            SearchQueryComposer.completing(tag: "female:furry", in: "l:\"chinese$\" furry")
                == "l:\"chinese$\" f:\"furry$\""
        )
        #expect(
            SearchQueryComposer.galleryKey(in: "https://e-hentai.org/g/12345/token/")
                == GalleryKey(gid: 12_345, token: "token")
        )
    }

    @Test("Gallery URL is converted into a stable key")
    func galleryURL() throws {
        let builder = SiteRequestBuilder(site: .eHentai)
        let request = try builder.galleryRequest(key: GalleryKey(gid: 123, token: "abc"))
        #expect(request.url?.absoluteString == "https://e-hentai.org/g/123/abc/")
    }

    @Test("Stored site page URLs defer page resolution until download")
    func deferredPageResolution() {
        let key = GalleryKey(gid: 123, token: "abc")
        let sitePage = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://e-hentai.org/s/page-token/123-1")!
        )
        let imagePage = GalleryPageDescriptor(
            galleryKey: key,
            index: 0,
            pageURL: URL(string: "https://ehgt.org/sample.jpg")!
        )

        #expect(sitePage.requiresPageResolution)
        #expect(imagePage.requiresPageResolution == false)
    }

    @Test("Search query keeps search and page parameters")
    func searchURL() throws {
        let request = try SiteRequestBuilder(site: .exHentai).galleryListRequest(
            query: GalleryListQuery(site: .exHentai, searchText: "猫", page: 2)
        )
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items: [String: String] = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components.host == "exhentai.org")
        #expect(items["f_search"] == "猫")
        #expect(items["page"] == "2")
    }

    @Test("Advanced search maps the current site filter options into query parameters")
    func advancedSearchURL() throws {
        let search = GalleryAdvancedSearch(
            categories: [.doujinshi, .manga],
            onlyWithTorrents: true,
            onlyShowExpunged: true,
            minimumRating: 4,
            minimumPageCount: 20,
            maximumPageCount: 80,
            disableLanguageFilter: true,
            disableUploaderFilter: true,
            disableTagFilter: true
        )
        let request = try SiteRequestBuilder(site: .eHentai).galleryListRequest(
            query: GalleryListQuery(searchText: "artist:test", advancedSearch: search)
        )
        let components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items = try #require(components.queryItems)
        let values = Dictionary(grouping: items, by: \.name).mapValues { $0.compactMap(\.value) }

        #expect(values["f_search"] == ["artist:test"])
        #expect(values["f_cats"] == ["1017"])
        #expect(values["advsearch"] == ["1"])
        #expect(values["f_sto"] == ["on"])
        #expect(values["f_sh"] == ["on"])
        #expect(values["f_srdd"] == ["4"])
        #expect(values["f_spf"] == ["20"])
        #expect(values["f_spt"] == ["80"])
        #expect(values["f_sfl"] == ["on"])
        #expect(values["f_sfu"] == ["on"])
        #expect(values["f_sft"] == ["on"])
        #expect(values["f_sr"] == nil)
        #expect(values["f_sp"] == nil)
        #expect(values["f_sdesc"] == nil)
    }

    @Test("Advanced search validates page ranges")
    func advancedSearchPageRange() {
        #expect(GalleryAdvancedSearch(minimumPageCount: 10, maximumPageCount: 0).hasValidPageRange)
        #expect(GalleryAdvancedSearch(minimumPageCount: 10, maximumPageCount: 20).hasValidPageRange)
        #expect(GalleryAdvancedSearch(minimumPageCount: 20, maximumPageCount: 10).hasValidPageRange == false)
        #expect(GalleryAdvancedSearch(minimumPageCount: -1, maximumPageCount: 10).hasValidPageRange == false)
    }

    @Test("Cookie parser normalizes whitespace without persisting credentials")
    func cookieParser() throws {
        let cookie = try #require(CookieHeader.parse(" ipb_member_id = 42; ipb_pass_hash = abc "))
        #expect(cookie.values["ipb_member_id"] == "42")
        #expect(cookie.headerValue == "ipb_member_id=42; ipb_pass_hash=abc")
        #expect(cookie.isAuthenticated)
    }

    @Test("Cookie authentication requires both original-project session values")
    func cookieAuthenticationRequirements() throws {
        let incomplete = try #require(CookieHeader.parse("ipb_member_id=42; unrelated=value"))
        #expect(incomplete.isAuthenticated == false)

        let complete = try #require(CookieHeader.parse("igneous=optional; ipb_pass_hash=abc; ipb_member_id=42; unrelated=value"))
        #expect(complete.isAuthenticated)
        #expect(complete.isExHentaiAuthenticated)
        #expect(complete.sessionHeaderValue == "igneous=optional; ipb_member_id=42; ipb_pass_hash=abc")

        let rejected = try #require(CookieHeader.parse("igneous=mystery; ipb_pass_hash=abc; ipb_member_id=42"))
        #expect(rejected.isAuthenticated)
        #expect(rejected.isExHentaiAuthenticated == false)
        #expect(rejected.sessionHeaderValue == "ipb_member_id=42; ipb_pass_hash=abc")
    }

    @Test("Session vault rejects unrelated cookies")
    func sessionVaultRejectsUnrelatedCookies() async throws {
        let vault = SessionVault(service: "EhViewerInvalidCookieTests-\(UUID().uuidString)")
        defer { Task { try? await vault.clear() } }
        do {
            try await vault.saveCookieHeader("foo=bar")
            Issue.record("expected invalid cookie error")
        } catch let error as EHError {
            #expect(error == .invalidCookie)
        }
    }

    @Test("A response cookie is merged into the authenticated session")
    func responseCookieMergesIntoSession() async throws {
        let vault = SessionVault(service: "EhViewerCookieMergeTests-\(UUID().uuidString)")
        try await vault.clear()
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")

        let changed = try await vault.saveSetCookieHeaders(
            ["igneous=valid-session; Domain=.exhentai.org; Path=/"],
            url: URL(string: "https://exhentai.org/")!
        )

        #expect(changed)
        #expect(try await vault.loadAuthenticatedCookieHeader() == "igneous=valid-session; ipb_member_id=42; ipb_pass_hash=secret")
        try await vault.clear()
    }

    @Test("Rejected igneous placeholders are not persisted")
    func rejectedIgneousIsDiscarded() async throws {
        let vault = SessionVault(service: "EhViewerRejectedIgneousTests-\(UUID().uuidString)")
        try await vault.clear()
        try await vault.saveCookieHeader("ipb_member_id=42; ipb_pass_hash=secret")

        let changed = try await vault.saveSetCookieHeaders(
            ["igneous=mystery; Domain=.exhentai.org; Path=/"],
            url: URL(string: "https://exhentai.org/")!
        )

        #expect(changed == false)
        #expect(try await vault.loadAuthenticatedCookieHeader() == "ipb_member_id=42; ipb_pass_hash=secret")
        #expect(try await vault.hasExHentaiSession() == false)
        try await vault.clear()
    }

    @Test("Display title mirrors the reference getSuitableTitle toggle behavior")
    func displayTitlePreference() {
        let key = GalleryKey(gid: 1, token: "a")
        let paired = GallerySummary(key: key, title: "English title", japaneseTitle: "日本語タイトル")
        #expect(paired.displayTitle(showJapaneseTitle: false) == "English title")
        #expect(paired.displayTitle(showJapaneseTitle: true) == "日本語タイトル")

        let englishOnly = GallerySummary(key: key, title: "English title")
        #expect(englishOnly.displayTitle(showJapaneseTitle: true) == "English title")

        let japaneseOnly = GallerySummary(key: key, title: "", japaneseTitle: "日本語タイトル")
        #expect(japaneseOnly.displayTitle(showJapaneseTitle: false) == "日本語タイトル")
        #expect(japaneseOnly.displayTitle(showJapaneseTitle: true) == "日本語タイトル")
    }

    @Test("Title search matches against both stored titles")
    func containsTitleMatchesBothTitles() {
        let key = GalleryKey(gid: 1, token: "a")
        let summary = GallerySummary(key: key, title: "English title", japaneseTitle: "日本語タイトル")
        #expect(summary.containsTitle("english"))
        #expect(summary.containsTitle("日本語"))
        #expect(summary.containsTitle("missing") == false)
        #expect(summary.containsTitle("  ") == true)
    }

    @Test("Simple language prefers language tags and falls back to title patterns")
    func simpleLanguageDerivation() {
        let key = GalleryKey(gid: 1, token: "a")
        let tagged = GallerySummary(key: key, title: "Untitled", tags: ["artist:sample", "language:chinese"])
        #expect(tagged.simpleLanguage == "ZH")

        let fromTitle = GallerySummary(key: key, title: "[Circle] Sample (Chinese)")
        #expect(fromTitle.simpleLanguage == "ZH")

        let english = GallerySummary(key: key, title: "Plain title", tags: ["language:english"])
        #expect(english.simpleLanguage == "EN")

        let none = GallerySummary(key: key, title: "Plain title")
        #expect(none.simpleLanguage == nil)
    }

    @Test("Similar-search keywords strip decorations and keep the pre-pipe title")
    func extractTitleKeyword() {
        #expect(SearchQueryComposer.extractTitleKeyword(from: "(C101) [Circle (Artist)] Sample Title | サンプル") == "Sample Title")
        #expect(SearchQueryComposer.extractTitleKeyword(from: "Sample ch. 1-23") == "Sample")
        #expect(SearchQueryComposer.extractTitleKeyword(from: "  ~decorated~ Title  ") == "Title")
        #expect(SearchQueryComposer.extractTitleKeyword(from: "| only decorations") == nil)
        #expect(SearchQueryComposer.uploaderSyntax("john doe") == "uploader:\"john doe\"")
        #expect(SearchQueryComposer.exactKeyword("blue archive") == "\"blue archive\"")
    }

    @Test("Preview clips crop the site offset and clamp aspect to the reference range")
    func previewClipGeometry() {
        let clipped = GalleryPreviewClip(xOffset: 100, width: 250, height: 156)
        #expect(clipped.cropRect == CGRect(x: 100, y: 0, width: 250, height: 156))

        let wide = GalleryPreviewClip(xOffset: 0, width: 400, height: 100)
        #expect(wide.clampedAspect == 0.8)

        let tall = GalleryPreviewClip(xOffset: 0, width: 100, height: 400)
        #expect(tall.clampedAspect == 0.5)

        let middle = GalleryPreviewClip(xOffset: 0, width: 2, height: 3)
        #expect(abs(middle.clampedAspect - 2.0 / 3.0) < 0.0001)
    }

    @Test("Detail tags convert into the reference database's short keys")
    func databaseTagKeys() {
        #expect(SearchQueryComposer.databaseTagKey(for: "artist:john doe") == "a:john doe")
        #expect(SearchQueryComposer.databaseTagKey(for: "female:big breasts") == "f:big breasts")
        #expect(SearchQueryComposer.databaseTagKey(for: "misc:some tag") == "some tag")
        #expect(SearchQueryComposer.databaseTagKey(for: "unknown:value") == "unknown:value")
        #expect(SearchQueryComposer.databaseTagKey(for: "plain") == "plain")
    }

    @Test("Filter rules mirror the reference EhFilter matching modes")
    func filterRuleModes() {
        let key = GalleryKey(gid: 1, token: "a")
        let gallery = GallerySummary(
            key: key,
            title: "Sample Title",
            uploader: "john doe",
            tags: ["misc:ai generated", "male:furry", "language:english"]
        )

        // Title: case-insensitive substring.
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .title, keyword: "sample"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .title, keyword: "SAM"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .title, keyword: "missing") == false)

        // Uploader: exact equality, case-sensitive.
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .uploader, keyword: "john doe"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .uploader, keyword: "John Doe") == false)
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .uploader, keyword: "john") == false)

        // Tag: exact name match; optional namespace; keyword is lowercased
        // like the reference does when the rule is saved.
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "ai generated"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "AI Generated"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "misc:ai generated"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "male:ai generated") == false)
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "generated") == false)
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "furry"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "male:furry"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tag, keyword: "misc:furry") == false)

        // Tag namespace: any tag in the namespace.
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tagNamespace, keyword: "male"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tagNamespace, keyword: "MALE"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tagNamespace, keyword: "language"))
        #expect(GalleryFilterMatcher.isBlocked(gallery, mode: .tagNamespace, keyword: "artist") == false)
    }
}
