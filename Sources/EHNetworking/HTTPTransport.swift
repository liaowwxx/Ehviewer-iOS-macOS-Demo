/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import EHDomain

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol ExHentaiCookieRefreshing: Sendable {
    func refreshExHentaiCookie(authenticationHeader: String) async throws -> String?
}

public struct URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EHError.invalidResponse
        }
        return (data, httpResponse)
    }
}

extension URLSessionTransport: ExHentaiCookieRefreshing {
    func refreshExHentaiCookie(authenticationHeader: String) async throws -> String? {
        guard let parsed = CookieHeader.parse(authenticationHeader), parsed.isAuthenticated else {
            throw EHError.invalidCookie
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        guard let cookieStore = configuration.httpCookieStorage else {
            throw EHError.invalidResponse
        }

        for domain in [".e-hentai.org", ".exhentai.org"] {
            for name in CookieHeader.requiredAuthenticationNames {
                guard let value = parsed.values[name],
                      let cookie = HTTPCookie(properties: [
                        .domain: domain,
                        .path: "/",
                        .name: name,
                        .value: value,
                        .secure: "TRUE"
                      ]) else { throw EHError.invalidCookie }
                cookieStore.setCookie(cookie)
            }
        }

        let refreshSession = URLSession(configuration: configuration)
        defer { refreshSession.invalidateAndCancel() }
        _ = try await refreshSession.data(for: Self.bootstrapRequest(
            url: URL(string: "https://e-hentai.org/")!
        ))

        let exHentaiURL = URL(string: "https://exhentai.org/")!
        for attempt in 0..<3 {
            let (_, response) = try await refreshSession.data(for: Self.bootstrapRequest(url: exHentaiURL))
            if let response = response as? HTTPURLResponse {
                switch response.statusCode {
                case 429: throw EHError.rateLimited
                case 509: throw EHError.bandwidthLimited
                default: break
                }
            }
            if let value = cookieStore.cookies(for: exHentaiURL)?
                .first(where: { $0.name == CookieHeader.igneousName })?.value,
               CookieHeader.isValidIgneousValue(value) {
                return value
            }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(500)) }
        }
        return nil
    }

    private static func bootstrapRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

public struct SiteRequestBuilder: Sendable {
    public let site: SiteMode

    public init(site: SiteMode) {
        self.site = site
    }

    public var baseURL: URL {
        URL(string: "https://\(site.host)")!
    }

    public func galleryListRequest(query: GalleryListQuery) throws -> URLRequest {
        let path: String = switch query.kind {
        case .home, .search: "/"
        case .subscriptions: "/watched"
        case .popular: "/popular"
        case .toplist: "/toplist.php"
        case .favorites: "/favorites.php"
        }
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw EHError.invalidURL
        }
        var items = [URLQueryItem]()
        if let searchText = query.searchText, searchText.isEmpty == false {
            items.append(URLQueryItem(name: "f_search", value: searchText))
        }
        if query.page > 0 {
            items.append(URLQueryItem(name: "page", value: String(query.page)))
        }
        if let excludedCategoryMask = query.advancedSearch?.excludedCategoryMask {
            items.append(URLQueryItem(name: "f_cats", value: String(excludedCategoryMask)))
        } else if let category = query.category {
            items.append(URLQueryItem(name: "f_cats", value: category))
        }
        if query.kind == .favorites, let favoriteCategory = query.favoriteCategory, (0...9).contains(favoriteCategory) {
            items.append(URLQueryItem(name: "favcat", value: String(favoriteCategory)))
        }
        if query.kind == .popular {
            items.append(URLQueryItem(name: "fs_from", value: "popular"))
        }
        if query.sort == .popular {
            items.append(URLQueryItem(name: "f_sname", value: "popularity"))
        } else if query.sort == .rating {
            items.append(URLQueryItem(name: "f_sname", value: "rating"))
        }
        if let advancedSearch = query.advancedSearch {
            appendAdvancedSearch(advancedSearch, to: &items)
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw EHError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func appendAdvancedSearch(_ search: GalleryAdvancedSearch, to items: inout [URLQueryItem]) {
        items.append(URLQueryItem(name: "advsearch", value: "1"))
        let flags: [(Bool, String)] = [
            (search.onlyWithTorrents, "f_sto"),
            (search.onlyShowExpunged, "f_sh"),
            (search.disableLanguageFilter, "f_sfl"),
            (search.disableUploaderFilter, "f_sfu"),
            (search.disableTagFilter, "f_sft")
        ]
        for (isEnabled, name) in flags where isEnabled {
            items.append(URLQueryItem(name: name, value: "on"))
        }
        if (2...5).contains(search.minimumRating) {
            items.append(URLQueryItem(name: "f_srdd", value: String(search.minimumRating)))
        }
        if search.minimumPageCount > 0 || search.maximumPageCount > 0 {
            items.append(URLQueryItem(name: "f_spf", value: search.minimumPageCount > 0 ? String(search.minimumPageCount) : ""))
            items.append(URLQueryItem(name: "f_spt", value: search.maximumPageCount > 0 ? String(search.maximumPageCount) : ""))
        }
    }

    public func galleryListRequest(pageURL: URL) throws -> URLRequest {
        guard pageURL.scheme?.lowercased() == "https",
              pageURL.host?.lowercased() == site.host else {
            throw EHError.invalidURL
        }
        var request = URLRequest(url: pageURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func galleryRequest(key: GalleryKey) throws -> URLRequest {
        try galleryRequest(key: key, previewPage: 0)
    }

    public func galleryRequest(key: GalleryKey, previewPage: Int) throws -> URLRequest {
        guard previewPage >= 0 else { throw EHError.invalidURL }
        guard var components = URLComponents(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/") else {
            throw EHError.invalidURL
        }
        if previewPage > 0 {
            components.queryItems = [URLQueryItem(name: "p", value: String(previewPage))]
        }
        guard let url = components.url else { throw EHError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public func pageRequest(_ descriptor: GalleryPageDescriptor) throws -> URLRequest {
        var request = URLRequest(url: descriptor.pageURL)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml,application/json", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }
}
