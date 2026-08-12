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

    @Test("Cookie parser normalizes whitespace without persisting credentials")
    func cookieParser() throws {
        let cookie = try #require(CookieHeader.parse(" ipb_member_id = 42; ipb_pass_hash = abc "))
        #expect(cookie.values["ipb_member_id"] == "42")
        #expect(cookie.headerValue == "ipb_member_id=42; ipb_pass_hash=abc")
    }
}
