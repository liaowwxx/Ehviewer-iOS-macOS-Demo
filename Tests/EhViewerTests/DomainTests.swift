import Foundation
import Testing
import EHDomain
import EHNetworking

struct DomainTests {
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

    @Test("Advanced search maps all original filter options into query parameters")
    func advancedSearchURL() throws {
        let search = GalleryAdvancedSearch(
            categories: [.doujinshi, .manga],
            searchDescription: true,
            searchTorrentNames: true,
            onlyWithTorrents: true,
            searchLowPowerTags: true,
            searchDownvotedTags: true,
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
        #expect(values["f_sname"] == ["on"])
        #expect(values["f_stags"] == ["on"])
        #expect(values["f_sdesc"] == ["on"])
        #expect(values["f_storr"] == ["on"])
        #expect(values["f_sto"] == ["on"])
        #expect(values["f_sdt1"] == ["on"])
        #expect(values["f_sdt2"] == ["on"])
        #expect(values["f_sh"] == ["on"])
        #expect(values["f_sr"] == ["on"])
        #expect(values["f_srdd"] == ["4"])
        #expect(values["f_sp"] == ["on"])
        #expect(values["f_spf"] == ["20"])
        #expect(values["f_spt"] == ["80"])
        #expect(values["f_sfl"] == ["on"])
        #expect(values["f_sfu"] == ["on"])
        #expect(values["f_sft"] == ["on"])
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
    }
}
