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
                == "language:english  f:\"big breasts$\""
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
}
