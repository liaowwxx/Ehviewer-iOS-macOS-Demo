import Foundation
import EHDomain
import SwiftSoup

public protocol EHAPI: Sendable {
    func login(username: String, password: String) async throws -> LoginResult
    func list(query: GalleryListQuery) async throws -> GalleryListPage
    func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage
    func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail
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
    }

    public func login(username: String, password: String) async throws -> LoginResult {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard username.isEmpty == false else { throw EHError.parsingFailed("用户名不能为空") }
        guard password.isEmpty == false else { throw EHError.parsingFailed("密码不能为空") }
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
            let setCookieHeaders = response.allHeaderFields.compactMap { key, value -> String? in
                guard String(describing: key).caseInsensitiveCompare("Set-Cookie") == .orderedSame else { return nil }
                if let values = value as? [String] { return values.joined(separator: ", ") }
                return String(describing: value)
            }
            if setCookieHeaders.isEmpty == false {
                try await sessionVault.saveSetCookieHeaders(setCookieHeaders, url: url)
            }
            return LoginResult(displayName: displayName)
        }

        if let error = try document.select("h4 + p, span.postcolor, .d p").first()?.text(), error.isEmpty == false {
            throw EHError.networkFailed(error)
        }
        throw EHError.parsingFailed("登录响应无法识别")
    }

    public func list(query: GalleryListQuery) async throws -> GalleryListPage {
        try await list(query: query, pageURL: nil)
    }

    public func list(query: GalleryListQuery, pageURL: URL?) async throws -> GalleryListPage {
        let builder = SiteRequestBuilder(site: query.site)
        var request = if let pageURL {
            try builder.galleryListRequest(pageURL: pageURL)
        } else {
            try builder.galleryListRequest(query: query)
        }
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
        try validate(response)
        return try parser.parseList(data: data, query: query)
    }

    public func detail(for key: GalleryKey, site: SiteMode) async throws -> GalleryDetail {
        let builder = SiteRequestBuilder(site: site)
        var request = try builder.galleryRequest(key: key)
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
        try validate(response)
        return try parser.parseDetail(data: data, key: key, site: site)
    }

    public func pageImage(for descriptor: GalleryPageDescriptor, site: SiteMode) async throws -> GalleryPageImage {
        var request = try SiteRequestBuilder(site: site).pageRequest(descriptor)
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
        try validate(response)
        return try pageParser.parse(data: data, descriptor: descriptor, site: site)
    }

    public func imageData(for image: GalleryPageImage, resolution: ImageResolution) async throws -> Data {
        let imageURL = resolution == .original ? (image.originImageURL ?? image.imageURL) : image.imageURL
        var request = URLRequest(url: imageURL)
        request.httpMethod = "GET"
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("EhViewer/0.1 (personal use)", forHTTPHeaderField: "User-Agent")
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
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
        var request = formRequest(url: url, referer: url, fields: [
            ("favcat", category.map(String.init) ?? "favdel"),
            ("favnote", note ?? ""),
            ("submit", "Apply Changes"),
            ("update", "1")
        ])
        try await attachSessionCookie(to: &request)
        let (_, response) = try await send(request)
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
        var request = formRequest(url: url, referer: url, fields: fields)
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
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
        var request = formRequest(url: url, referer: url, fields: [
            ("usertag_action", "add"),
            ("tagname_new", normalized),
            ("tagwatch_new", "on"),
            ("taghide_new", hidden ? "on" : ""),
            ("tagcolor_new", ""),
            ("tagweight_new", "10"),
            ("usertag_target", "0")
        ])
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
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
        var request = formRequest(url: url, referer: galleryURL(key, site: site), fields: [("hathdl_xres", resolution)])
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
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
        var request = formRequest(url: url, referer: url, fields: [("reset_imagelimit", "Reset Limit")])
        try await attachSessionCookie(to: &request)
        let (data, response) = try await send(request)
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
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0..<3 {
            do {
                let result = try await transport.send(request)
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
        if let cookieHeader = try await sessionVault.loadCookieHeader() {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
    }

    private func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        try await attachSessionCookie(to: &request)
        return try await send(request)
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
