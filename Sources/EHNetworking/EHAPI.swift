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
import SwiftSoup

public protocol EHAPI: Sendable {
    func login(username: String, password: String) async throws -> LoginResult
    func list(query: GalleryListQuery) async throws -> GalleryListPage
    func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage
    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail
    func gallerySummaries(for keys: [GalleryKey], site: SiteMode) async throws -> [GallerySummary]
    func pageImage(for descriptor: GalleryPageDescriptor, site: SiteMode) async throws -> GalleryPageImage
    func imageData(for image: GalleryPageImage, resolution: ImageResolution) async throws -> Data
    func favorites(query: GalleryListQuery) async throws -> GalleryListPage
    func setFavorite(for key: GalleryKey, site: SiteMode, category: Int?, note: String?) async throws
    func rateGallery(for key: GalleryKey, site: SiteMode, rating: Double, apiUID: Int64, apiKey: String) async throws -> GalleryRating
    func comments(for key: GalleryKey, site: SiteMode) async throws -> [GalleryComment]
    func submitComment(for key: GalleryKey, site: SiteMode, body: String, editing commentID: String?) async throws -> [GalleryComment]
    func voteComment(for key: GalleryKey, site: SiteMode, commentID: String, vote: Int, apiUID: Int64, apiKey: String) async throws -> CommentVoteResult
    func watchedTags(site: SiteMode) async throws -> [WatchedTag]
    func followTag(_ tag: String, site: SiteMode, hidden: Bool) async throws -> [WatchedTag]
    func torrents(for key: GalleryKey, site: SiteMode) async throws -> [TorrentDescriptor]
    func archiveOptions(for key: GalleryKey, site: SiteMode) async throws -> [ArchiveOption]
    func archiveDownloadURL(for key: GalleryKey, site: SiteMode, resolution: String) async throws -> URL
    func imageSearch(imageData: Data, fileName: String, site: SiteMode, options: ImageSearchOptions) async throws -> GalleryListPage
    func imageQuota(site: SiteMode) async throws -> ImageQuota
    func resetImageQuota(site: SiteMode) async throws -> ImageQuota
}

public extension EHAPI {
    func login(username: String, password: String) async throws -> LoginResult {
        throw EHError.unsupportedFeature("密码登录")
    }

    func pageImage(for descriptor: GalleryPageDescriptor, site: SiteMode) async throws -> GalleryPageImage {
        throw EHError.parsingFailed("当前 API 未实现页面解析")
    }

    func gallerySummaries(for keys: [GalleryKey], site: SiteMode) async throws -> [GallerySummary] {
        var summaries: [GallerySummary] = []
        for key in keys {
            try Task.checkCancellation()
            summaries.append(try await detail(for: key, site: site).summary)
        }
        return summaries
    }

    func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage {
        if query.kind == .favorites {
            return try await favorites(query: query)
        }
        return try await list(query: query)
    }

    func imageData(for image: GalleryPageImage, resolution: ImageResolution) async throws -> Data {
        throw EHError.parsingFailed("当前 API 未实现图片请求")
    }

    func favorites(query: GalleryListQuery) async throws -> GalleryListPage {
        throw EHError.unsupportedFeature("远程收藏")
    }

    func setFavorite(for key: GalleryKey, site: SiteMode, category: Int?, note: String?) async throws {
        throw EHError.unsupportedFeature("远程收藏")
    }

    func rateGallery(for key: GalleryKey, site: SiteMode, rating: Double, apiUID: Int64, apiKey: String) async throws -> GalleryRating {
        throw EHError.unsupportedFeature("评分")
    }

    func comments(for key: GalleryKey, site: SiteMode) async throws -> [GalleryComment] {
        throw EHError.unsupportedFeature("评论")
    }

    func submitComment(for key: GalleryKey, site: SiteMode, body: String, editing commentID: String?) async throws -> [GalleryComment] {
        throw EHError.unsupportedFeature("评论")
    }

    func voteComment(for key: GalleryKey, site: SiteMode, commentID: String, vote: Int, apiUID: Int64, apiKey: String) async throws -> CommentVoteResult {
        throw EHError.unsupportedFeature("评论投票")
    }

    func watchedTags(site: SiteMode) async throws -> [WatchedTag] {
        throw EHError.unsupportedFeature("关注标签")
    }

    func followTag(_ tag: String, site: SiteMode, hidden: Bool = false) async throws -> [WatchedTag] {
        throw EHError.unsupportedFeature("关注标签")
    }

    func torrents(for key: GalleryKey, site: SiteMode) async throws -> [TorrentDescriptor] {
        throw EHError.unsupportedFeature("Torrent")
    }

    func archiveOptions(for key: GalleryKey, site: SiteMode) async throws -> [ArchiveOption] {
        throw EHError.unsupportedFeature("站点归档")
    }

    func archiveDownloadURL(for key: GalleryKey, site: SiteMode, resolution: String) async throws -> URL {
        throw EHError.unsupportedFeature("站点归档")
    }

    func imageSearch(imageData: Data, fileName: String, site: SiteMode, options: ImageSearchOptions) async throws -> GalleryListPage {
        throw EHError.unsupportedFeature("图片搜索")
    }

    func imageQuota(site: SiteMode) async throws -> ImageQuota {
        throw EHError.unsupportedFeature("图片配额")
    }

    func resetImageQuota(site: SiteMode) async throws -> ImageQuota {
        throw EHError.unsupportedFeature("重置图片配额")
    }
}

public struct EHClient: EHAPI, Sendable {
    private let transport: any HTTPTransport
    private let parser: GalleryHTMLParser
    private let pageParser: GalleryPageParser
    private let sessionVault: SessionVault
    private let exHentaiRefreshGate: ExHentaiRefreshGate

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        parser: GalleryHTMLParser = GalleryHTMLParser(),
        pageParser: GalleryPageParser = GalleryPageParser(),
        sessionVault: SessionVault = SessionVault()
    ) {
        self.transport = transport
        self.parser = parser
        self.pageParser = pageParser
        self.sessionVault = sessionVault
        self.exHentaiRefreshGate = ExHentaiRefreshGate()
    }

    public func login(username: String, password: String) async throws -> LoginResult {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.isEmpty == false else { throw EHError.parsingFailed("用户名不能为空") }
        guard password.isEmpty == false else { throw EHError.parsingFailed("密码不能为空") }
        try await sessionVault.clear()
        Self.clearTransientAuthenticationCookies()
        defer { Self.clearTransientAuthenticationCookies() }
        let url = URL(string: "https://forums.e-hentai.org/index.php?act=Login&CODE=01")!
        var request = formRequest(
            url: url,
            referer: URL(string: "https://forums.e-hentai.org/index.php?act=Login&CODE=00")!,
            fields: [
                ("UserName", username),
                ("PassWord", password),
                ("submit", "Log me in"),
                ("CookieDate", "1"),
                ("temporary_https", "off")
            ]
        )
        request.setValue("https://forums.e-hentai.org", forHTTPHeaderField: "Origin")
        let (data, response) = try await send(request)
        try validate(response)

        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        if let loggedIn = try document.select("p").first(where: { try $0.text().localizedCaseInsensitiveContains("You are now logged in as:") }) {
            let text = try loggedIn.text()
            let prefix = "You are now logged in as:"
            let displayName = text.replacingOccurrences(of: prefix, with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard displayName.isEmpty == false else { throw EHError.parsingFailed("登录响应缺少用户名") }
            var setCookieHeaders = Self.setCookieHeaders(from: response)
            setCookieHeaders.append(contentsOf: Self.transientAuthenticationCookieHeaders())
            guard setCookieHeaders.isEmpty == false else { throw EHError.invalidCookie }
            try await sessionVault.saveSetCookieHeaders(setCookieHeaders, url: url)
            guard try await sessionVault.hasAuthenticatedSession() else { throw EHError.invalidCookie }
            return LoginResult(displayName: displayName)
        }

        if let error = try document.select("h4 + p, span.postcolor, .d p").first()?.text(), error.isEmpty == false {
            throw EHError.networkFailed(error)
        }
        throw EHError.parsingFailed("登录响应无法识别")
    }

    private static func clearTransientAuthenticationCookies() {
        for cookie in HTTPCookieStorage.shared.cookies ?? []
        where CookieHeader.persistedCookieNames.contains(cookie.name) && isAuthenticationDomain(cookie.domain) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private static func transientAuthenticationCookieHeaders() -> [String] {
        (HTTPCookieStorage.shared.cookies ?? []).compactMap { cookie in
            guard CookieHeader.persistedCookieNames.contains(cookie.name),
                  isAuthenticationDomain(cookie.domain) else { return nil }
            return "\(cookie.name)=\(cookie.value)"
        }
    }

    private static func isAuthenticationDomain(_ domain: String) -> Bool {
        let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized == "e-hentai.org"
            || normalized.hasSuffix(".e-hentai.org")
            || normalized == "exhentai.org"
            || normalized.hasSuffix(".exhentai.org")
    }

    public func list(query: GalleryListQuery) async throws -> GalleryListPage {
        try await list(query: query, pageURL: nil)
    }

    public func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage {
        let builder = SiteRequestBuilder(site: query.site)
        let request = if let pageURL {
            try builder.galleryListRequest(pageURL: pageURL)
        } else {
            try builder.galleryListRequest(query: query)
        }
        let (data, response) = try await authorized(request)
        try validate(response)
        if query.site == .exHentai, Self.isBlank(data) {
            throw EHError.exHentaiAccessDenied
        }
        return try parser.parseList(data: data, query: query)
    }

    public func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        let builder = SiteRequestBuilder(site: site)
        let request = try builder.galleryRequest(key: key)
        let (data, response) = try await authorized(request)
        try validate(response)
        var detail = try parser.parseDetail(data: data, key: key, site: site)
        let firstPreviewPage = try parser.parsePreviewPage(data: data, key: key, site: site)
        let previewPageCount = max(
            firstPreviewPage.pageCount ?? 1,
            Self.estimatedPreviewPageCount(
                totalPageCount: detail.summary.pageCount,
                firstPreviewPageCount: firstPreviewPage.pages.count
            )
        )
        guard previewPageCount > 1 else { return detail }

        let additionalPages = try await loadAdditionalPreviewPages(
            key: key,
            site: site,
            pageCount: previewPageCount,
            builder: builder
        )
        var pagesByIndex: [Int: GalleryPageDescriptor] = [:]
        for page in detail.pages + additionalPages {
            pagesByIndex[page.index] = page
        }
        detail.pages = pagesByIndex.values.sorted { $0.index < $1.index }
        return detail
    }

    public func gallerySummaries(for keys: [GalleryKey], site: SiteMode) async throws -> [GallerySummary] {
        guard keys.isEmpty == false else { return [] }

        let requestSize = 25
        var summaries: [GallerySummary] = []
        for start in stride(from: 0, to: keys.count, by: requestSize) {
            try Task.checkCancellation()
            let end = min(start + requestSize, keys.count)
            let batch = Array(keys[start..<end])
            let url = try makeURL(site: site, path: "/api.php", query: [])
            let gidList: [[Any]] = batch.map { key in
                [NSNumber(value: key.gid), key.token]
            }
            let payload: [String: Any] = [
                "method": "gdata",
                "gidlist": gidList,
                "namespace": 1
            ]
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://\(site.host)/", forHTTPHeaderField: "Referer")
            request.setValue("https://\(site.host)", forHTTPHeaderField: "Origin")
            request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await authorized(request)
            try validate(response)
            summaries.append(contentsOf: try GalleryAPIParser().parse(data: data, site: site))
        }
        return summaries
    }

    private func loadAdditionalPreviewPages(
        key: GalleryKey,
        site: SiteMode,
        pageCount: Int,
        builder: SiteRequestBuilder,
        maximumConcurrent: Int = 4
    ) async throws -> [GalleryPageDescriptor] {
        guard pageCount > 1 else { return [] }
        return try await withThrowingTaskGroup(
            of: [GalleryPageDescriptor].self,
            returning: [GalleryPageDescriptor].self
        ) { group in
            var nextPage = 1
            let initialTaskCount = min(maximumConcurrent, pageCount - 1)
            for _ in 0..<initialTaskCount {
                let previewPage = nextPage
                nextPage += 1
                group.addTask { [self] in
                    let request = try builder.galleryRequest(key: key, previewPage: previewPage)
                    let (data, response) = try await authorized(request)
                    try validate(response)
                    return try parser.parsePreviewPage(data: data, key: key, site: site).pages
                }
            }

            var pages: [GalleryPageDescriptor] = []
            while let previewPages = try await group.next() {
                pages.append(contentsOf: previewPages)
                guard nextPage < pageCount else { continue }
                let previewPage = nextPage
                nextPage += 1
                group.addTask { [self] in
                    let request = try builder.galleryRequest(key: key, previewPage: previewPage)
                    let (data, response) = try await authorized(request)
                    try validate(response)
                    return try parser.parsePreviewPage(data: data, key: key, site: site).pages
                }
            }
            return pages
        }
    }

    private static func estimatedPreviewPageCount(totalPageCount: Int?, firstPreviewPageCount: Int) -> Int {
        guard let totalPageCount,
              totalPageCount > 0,
              firstPreviewPageCount > 0,
              totalPageCount > firstPreviewPageCount else { return 1 }
        let previewPageCapacity = max(firstPreviewPageCount, 20)
        return (totalPageCount + previewPageCapacity - 1) / previewPageCapacity
    }

    public func pageImage(for descriptor: GalleryPageDescriptor, site: SiteMode) async throws -> GalleryPageImage {
        let request = try SiteRequestBuilder(site: site).pageRequest(descriptor)
        let (data, response) = try await authorized(request)
        try validate(response)
        return try pageParser.parse(data: data, descriptor: descriptor, site: site)
    }

    public func imageData(for image: GalleryPageImage, resolution: ImageResolution) async throws -> Data {
        let imageURL = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
        var request = URLRequest(url: imageURL)
        request.httpMethod = "GET"
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await authorized(request)
        try validate(response)
        return data
    }

    public func favorites(query: GalleryListQuery) async throws -> GalleryListPage {
        let favoriteQuery = GalleryListQuery(
            site: query.site,
            kind: .favorites,
            searchText: query.searchText,
            page: query.page,
            sort: query.sort,
            category: query.category,
            favoriteCategory: query.favoriteCategory,
            advancedSearch: query.advancedSearch
        )
        return try await list(query: favoriteQuery, pageURL: nil)
    }

    public func setFavorite(for key: GalleryKey, site: SiteMode, category: Int?, note: String? = nil) async throws {
        guard category == nil || (0...9).contains(category!) else {
            throw EHError.parsingFailed("收藏分类必须为 0 到 9，nil 表示移除")
        }
        let url = try makeURL(site: site, path: "/gallerypopups.php", query: [
            URLQueryItem(name: "gid", value: String(key.gid)),
            URLQueryItem(name: "t", value: key.token),
            URLQueryItem(name: "act", value: "addfav")
        ])
        let request = formRequest(url: url, referer: url, fields: [
            ("favcat", category.map(String.init) ?? "favdel"),
            ("favnote", note ?? ""),
            ("submit", "Apply Changes"),
            ("update", "1")
        ])
        let (_, response) = try await authorized(request)
        try validate(response)
    }

    public func rateGallery(for key: GalleryKey, site: SiteMode, rating: Double, apiUID: Int64, apiKey: String) async throws -> GalleryRating {
        let value = max(1, min(10, Int(ceil(rating * 2))))
        let body: [String: Any] = [
            "method": "rategallery",
            "apiuid": apiUID,
            "apikey": apiKey,
            "gid": key.gid,
            "token": key.token,
            "rating": value
        ]
        let request = try apiRequest(site: site, referer: galleryURL(key, site: site), json: body)
        let (data, response) = try await authorized(request)
        try validate(response)
        return try decodeRating(data)
    }

    public func comments(for key: GalleryKey, site: SiteMode) async throws -> [GalleryComment] {
        try await (detail(for: key, site: site)).comments
    }

    public func submitComment(for key: GalleryKey, site: SiteMode, body: String, editing commentID: String? = nil) async throws -> [GalleryComment] {
        guard body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw EHError.parsingFailed("评论不能为空")
        }
        var fields = [(String, String)]()
        if let commentID {
            fields.append(("commenttext_edit", body))
            fields.append(("edit_comment", commentID))
        } else {
            fields.append(("commenttext_new", body))
        }
        let url = galleryURL(key, site: site)
        let request = formRequest(url: url, referer: url, fields: fields)
        let (data, response) = try await authorized(request)
        try validate(response)
        if let message = try? parseSiteError(data), message.isEmpty == false {
            throw EHError.networkFailed(message)
        }
        return try parser.parseDetail(data: data, key: key, site: site).comments
    }

    public func voteComment(for key: GalleryKey, site: SiteMode, commentID: String, vote: Int, apiUID: Int64, apiKey: String) async throws -> CommentVoteResult {
        let body: [String: Any] = [
            "method": "votecomment",
            "apiuid": apiUID,
            "apikey": apiKey,
            "gid": key.gid,
            "token": key.token,
            "comment_id": Int64(commentID) ?? 0,
            "comment_vote": max(-1, min(1, vote))
        ]
        let request = try apiRequest(site: site, referer: galleryURL(key, site: site), json: body)
        let (data, response) = try await authorized(request)
        try validate(response)
        return try decodeVote(data, expectedVote: vote)
    }

    public func watchedTags(site: SiteMode) async throws -> [WatchedTag] {
        let url = try makeURL(site: site, path: "/mytags", query: [])
        let request = try getRequest(url: url)
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseWatchedTags(data: data)
    }

    public func followTag(_ tag: String, site: SiteMode, hidden: Bool = false) async throws -> [WatchedTag] {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { throw EHError.parsingFailed("标签不能为空") }
        let url = try makeURL(site: site, path: "/mytags", query: [])
        let request = formRequest(url: url, referer: url, fields: [
            ("usertag_action", "add"),
            ("tagname_new", normalized),
            ("tagwatch_new", "on"),
            ("taghide_new", hidden ? "on" : ""),
            ("tagcolor_new", ""),
            ("tagweight_new", "10"),
            ("usertag_target", "0")
        ])
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseWatchedTags(data: data)
    }

    public func torrents(for key: GalleryKey, site: SiteMode) async throws -> [TorrentDescriptor] {
        guard let url = try await detail(for: key, site: site).torrentURL else { return [] }
        var request = try getRequest(url: url)
        request.setValue(galleryURL(key, site: site).absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseTorrents(data: data, site: site)
    }

    public func archiveOptions(for key: GalleryKey, site: SiteMode) async throws -> [ArchiveOption] {
        guard let url = try await detail(for: key, site: site).archiveURL else { return [] }
        var request = try getRequest(url: url)
        request.setValue(galleryURL(key, site: site).absoluteString, forHTTPHeaderField: "Referer")
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseArchiveOptions(data: data)
    }

    public func archiveDownloadURL(for key: GalleryKey, site: SiteMode, resolution: String) async throws -> URL {
        guard let url = try await detail(for: key, site: site).archiveURL else { throw EHError.notFound }
        let request = formRequest(url: url, referer: galleryURL(key, site: site), fields: [("hathdl_xres", resolution)])
        let (data, response) = try await authorized(request)
        try validate(response)
        guard let downloadURL = try AdvancedHTMLParser().parseArchiveDownloadURL(data: data, site: site) else {
            throw EHError.parsingFailed("归档服务器未返回下载地址")
        }
        return downloadURL
    }

    public func imageSearch(imageData: Data, fileName: String = "upload.jpg", site: SiteMode, options: ImageSearchOptions = ImageSearchOptions()) async throws -> GalleryListPage {
        let boundary = "EhViewer-\(UUID().uuidString)"
        var request = URLRequest(url: site.imageSearchURL)
        request.httpMethod = "POST"
        request.httpBody = multipartBody(
            imageData: imageData,
            fileName: fileName,
            options: options,
            boundary: boundary
        )
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("https://\(site.host)/", forHTTPHeaderField: "Referer")
        request.setValue("https://\(site.host)", forHTTPHeaderField: "Origin")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await authorized(request)
        try validate(response)
        return try parser.parseList(data: data, query: GalleryListQuery(site: site, kind: .search))
    }

    public func imageQuota(site: SiteMode) async throws -> ImageQuota {
        let url = try makeURL(site: site, path: "/home.php", query: [])
        let request = try getRequest(url: url)
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseImageQuota(data: data)
    }

    public func resetImageQuota(site: SiteMode) async throws -> ImageQuota {
        let url = try makeURL(site: site, path: "/home.php", query: [])
        let request = formRequest(url: url, referer: url, fields: [("reset_imagelimit", "Reset Limit")])
        let (data, response) = try await authorized(request)
        try validate(response)
        return try AdvancedHTMLParser().parseImageQuota(data: data)
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            switch response.statusCode {
            case 403: throw EHError.authenticationRequired
            case 429: throw EHError.rateLimited
            case 509: throw EHError.bandwidthLimited
            case 404: throw EHError.notFound
            default: throw EHError.httpStatus(response.statusCode)
            }
        }
        if response.value(forHTTPHeaderField: "Content-Disposition") == "inline; filename=\"sadpanda.jpg\"",
           response.value(forHTTPHeaderField: "Content-Type") == "image/gif",
           response.value(forHTTPHeaderField: "Content-Length") == "9615" {
            throw EHError.exHentaiAccessDenied
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<3 {
            do {
                let result = try await transport.send(request)
                await persistResponseCookies(from: result.1)
                if result.1.statusCode >= 400 {
                    EHLog.network.warning("HTTP status \(result.1.statusCode, privacy: .public)")
                }
                if shouldRetry(result.1), attempt < 2 {
                    try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
                    continue
                }
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                EHLog.network.error("request failed: \(error.localizedDescription, privacy: .public)")
                guard attempt < 2 else { throw error }
                try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
            }
        }
        throw EHError.invalidResponse
    }

    private func shouldRetry(_ response: HTTPURLResponse) -> Bool {
        [408, 429, 500, 502, 503, 504, 509].contains(response.statusCode)
    }

    private func attachSessionCookie(to request: inout URLRequest) async throws {
        if let cookieHeader = try await sessionVault.loadAuthenticatedCookieHeader() {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
    }

    private func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let previousSession = try await sessionVault.loadAuthenticatedCookieHeader()
        var authorizedRequest = request
        try await attachSessionCookie(to: &authorizedRequest)
        let result = try await send(authorizedRequest)

        guard isExHentaiGET(request), isExHentaiAccessFailure(result, for: request) else {
            return result
        }

        let updatedSession = try await sessionVault.loadAuthenticatedCookieHeader()
        if updatedSession != previousSession, try await sessionVault.hasExHentaiSession() {
            return try await replayExHentaiRequest(request)
        }

        let refreshed = try await exHentaiRefreshGate.run {
            try await refreshExHentaiSession()
        }
        guard refreshed else { throw EHError.exHentaiAccessDenied }
        return try await replayExHentaiRequest(request)
    }

    private func replayExHentaiRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var replayRequest = request
        try await attachSessionCookie(to: &replayRequest)
        let replay = try await send(replayRequest)
        guard isExHentaiAccessFailure(replay, for: request) == false else {
            throw EHError.exHentaiAccessDenied
        }
        return replay
    }

    private func refreshExHentaiSession() async throws -> Bool {
        guard try await sessionVault.hasAuthenticatedSession() else { return false }
        try await sessionVault.clearIgneous()

        if let refresher = transport as? any ExHentaiCookieRefreshing,
           let authenticationHeader = try await sessionVault.loadAuthenticatedCookieHeader(),
           let igneous = try await refresher.refreshExHentaiCookie(
               authenticationHeader: authenticationHeader
           ),
           let base = CookieHeader.parse(authenticationHeader) {
            var values = base.values
            values[CookieHeader.igneousName] = igneous
            try await sessionVault.saveCookieHeader(CookieHeader(values: values).sessionHeaderValue)
            return true
        }

        var eHentaiRequest = Self.authenticationBootstrapRequest(
            url: URL(string: "https://e-hentai.org/")!
        )
        try await attachSessionCookie(to: &eHentaiRequest)
        let (_, eHentaiResponse) = try await send(eHentaiRequest)
        try validate(eHentaiResponse)

        for attempt in 0..<3 {
            var exHentaiRequest = Self.authenticationBootstrapRequest(
                url: URL(string: "https://exhentai.org/")!
            )
            try await attachSessionCookie(to: &exHentaiRequest)
            let (_, response) = try await send(exHentaiRequest)
            if try await sessionVault.hasExHentaiSession() { return true }
            if [429, 509].contains(response.statusCode) { try validate(response) }
            if attempt < 2 { try await Task.sleep(for: .milliseconds(500)) }
        }
        return false
    }

    private func isExHentaiGET(_ request: URLRequest) -> Bool {
        request.httpMethod?.uppercased() == "GET"
            && request.url?.host?.lowercased() == SiteMode.exHentai.host
    }

    private func isExHentaiAccessFailure(
        _ result: (Data, HTTPURLResponse),
        for request: URLRequest
    ) -> Bool {
        guard isExHentaiGET(request) else { return false }
        let (data, response) = result
        if response.url?.host?.lowercased() != SiteMode.exHentai.host { return true }
        if response.statusCode == 302 || response.statusCode == 403 { return true }
        if response.value(forHTTPHeaderField: "Content-Disposition") == "inline; filename=\"sadpanda.jpg\"",
           response.value(forHTTPHeaderField: "Content-Type") == "image/gif" {
            return true
        }
        return Self.isBlank(data)
    }

    private static func authenticationBootstrapRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func isBlank(_ data: Data) -> Bool {
        if data.isEmpty { return true }
        guard let body = String(data: data, encoding: .utf8) else { return false }
        return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persistResponseCookies(from response: HTTPURLResponse) async {
        guard let url = response.url else { return }
        let headers = Self.setCookieHeaders(from: response)
        guard headers.isEmpty == false else { return }
        do {
            try await sessionVault.saveSetCookieHeaders(headers, url: url)
        } catch let error as EHError where error == .invalidCookie {
            // A guest response can set an isolated optional cookie; it is not an authenticated session.
        } catch {
            EHLog.network.error("response cookie persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func setCookieHeaders(from response: HTTPURLResponse) -> [String] {
        response.allHeaderFields.compactMap { key, value -> String? in
            guard String(describing: key).caseInsensitiveCompare("Set-Cookie") == .orderedSame else { return nil }
            if let values = value as? [String] { return values.joined(separator: ", ") }
            return String(describing: value)
        }
    }

    private func galleryURL(_ key: GalleryKey, site: SiteMode) -> URL {
        URL(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/")!
    }

    private func getRequest(url: URL) throws -> URLRequest {
        guard url.scheme != nil else { throw EHError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func formRequest(url: URL, referer: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = formData(fields)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("https://\(url.host ?? "")", forHTTPHeaderField: "Origin")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func apiRequest(site: SiteMode, referer: URL, json: [String: Any]) throws -> URLRequest {
        let url = try makeURL(site: site, path: "/api.php", query: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("https://\(site.host)", forHTTPHeaderField: "Origin")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeURL(site: SiteMode, path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(string: "https://\(site.host)\(path)") else { throw EHError.invalidURL }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw EHError.invalidURL }
        return url
    }

    private func formData(_ fields: [(String, String)]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.0, value: $0.1) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func multipartBody(imageData: Data, fileName: String, options: ImageSearchOptions, boundary: String) -> Data {
        let safeFileName = URL(fileURLWithPath: fileName).lastPathComponent.replacingOccurrences(of: "\"", with: "_")
        var body = Data()
        func append(_ string: String) { body.append(contentsOf: string.utf8) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"sfile\"; filename=\"\(safeFileName)\"; size=\"\(imageData.count)\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n")
        if options.similar { field("fs_similar", "on") }
        if options.covers { field("fs_covers", "on") }
        if options.expanded { field("fs_exp", "on") }
        field("f_sfile", "File Search")
        append("--\(boundary)--\r\n")
        return body
    }

    private func decodeRating(_ data: Data) throws -> GalleryRating {
        let payload = try jsonObject(data)
        if let error = payload["error"] as? String { throw EHError.networkFailed(error) }
        guard let average = payload["rating_avg"] as? NSNumber, let count = payload["rating_cnt"] as? NSNumber else {
            throw EHError.parsingFailed("评分接口响应缺少 rating_avg/rating_cnt")
        }
        return GalleryRating(average: average.doubleValue, count: count.intValue)
    }

    private func decodeVote(_ data: Data, expectedVote: Int) throws -> CommentVoteResult {
        let payload = try jsonObject(data)
        if let error = payload["error"] as? String { throw EHError.networkFailed(error) }
        guard let id = payload["comment_id"] as? NSNumber,
              let score = payload["comment_score"] as? NSNumber,
              let vote = payload["comment_vote"] as? NSNumber else {
            throw EHError.parsingFailed("投票接口响应缺少评论字段")
        }
        return CommentVoteResult(commentID: String(id.int64Value), score: score.intValue, vote: vote.intValue, expectedVote: expectedVote)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EHError.parsingFailed("接口响应不是 JSON 对象")
        }
        return object
    }

    private func parseSiteError(_ data: Data) throws -> String? {
        let document = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
        return try document.select("#chd + p, .d p").first()?.text()
    }
}

private actor ExHentaiRefreshGate {
    private var task: Task<Bool, any Error>?

    func run(_ operation: @escaping @Sendable () async throws -> Bool) async throws -> Bool {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        defer { self.task = nil }
        return try await task.value
    }
}
