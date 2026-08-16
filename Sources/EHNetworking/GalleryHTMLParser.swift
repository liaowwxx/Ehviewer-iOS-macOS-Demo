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

public struct GalleryHTMLParser: Sendable {
    public struct PreviewPage: Sendable {
        public let pages: [GalleryPageDescriptor]
        public let pageCount: Int?

        public init(pages: [GalleryPageDescriptor], pageCount: Int?) {
            self.pages = pages
            self.pageCount = pageCount
        }
    }

    public init() {}

    public func parseList(data: Data, query: GalleryListQuery) throws -> GalleryListPage {
        guard let html = String(data: data, encoding: .utf8) else {
            throw EHError.parsingFailed(String(localized: "页面不是 UTF-8"))
        }
        do {
            let document = try SwiftSoup.parse(html)
            let candidates = try document.select("table.itg > tr, table.itg > tbody > tr, tr.gtr0, tr.gtr1, div.gl1t3")
            let summaries = try candidates.compactMap { try parseSummary(from: $0) }
            let nextPageURL = try parseNextPageURL(from: document, html: html, site: query.site)
            if summaries.isEmpty, nextPageURL == nil, isNoHitsPage(document) == false {
                throw EHError.parsingFailed(String(localized: "站点没有返回可识别的画廊列表"))
            }
            return GalleryListPage(
                items: summaries,
                cursor: GalleryCursor(
                    page: query.page,
                    nextPageURL: nextPageURL
                )
            )
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.parsingFailed(error.localizedDescription)
        }
    }

    private func isNoHitsPage(_ document: Document) -> Bool {
        let text = (try? document.text())?.lowercased() ?? ""
        return text.contains("no hits found") || text.contains("no galleries found")
    }

    private func parseNextPageURL(from document: Document, html: String, site: SiteMode) throws -> URL? {
        let baseURL = URL(string: "https://\(site.host)/")
        let selectors = [
            "a[rel=next][href]",
            "a.next[href]",
            "a#unext[href]",
            "a#dnext[href]",
            ".searchnav a[id$=next][href]",
            "table.ptt td:last-child a[href]"
        ]

        for selector in selectors {
            guard let href = try document.select(selector).first()?.attr("href"),
                  href.isEmpty == false,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            return url
        }

        let pattern = #"\bnexturl\s*=\s*[\"']([^\"']+)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let value = String(html[range])
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\u0026"#, with: "&", options: .caseInsensitive)
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    public func parseDetail(data: Data, key: GalleryKey, site: SiteMode) throws -> GalleryDetail {
        guard let html = String(data: data, encoding: .utf8) else {
            throw EHError.parsingFailed(String(localized: "页面不是 UTF-8"))
        }
        do {
            let document = try SwiftSoup.parse(html)
            let title = try document.select("#gn, h1#gn").first()?.text() ?? "Gallery \(key.gid)"
            let japaneseTitle = try document.select("#gj").first()?.text()
            let category = try document.select("#gdc, #gdc .cs").first()?.text()
            let pageCount = try parsePageCount(document)
            let tags = try parseTagGroups(from: document)
            let uploaderElement = try document.select("#gdn a").first()
            let uploader: String?
            if let uploaderElement {
                uploader = Self.nilIfBlank(try uploaderElement.text())
            } else {
                uploader = nil
            }
            let info = try parseInfoRows(from: document)
            let thumbnailElement = try document.select("#gd1 img, #gd1 div, .gdtm img").first()
            let thumbnailURL: URL?
            if let thumbnailElement {
                let src = try thumbnailElement.attr("src")
                if let directURL = URL(string: src) {
                    thumbnailURL = directURL
                } else {
                    thumbnailURL = Self.urlInStyle(try thumbnailElement.attr("style"))
                }
            } else {
                thumbnailURL = nil
            }
            let rating = try document.select("#rating_label").first()?.text()
                .split(separator: ":", maxSplits: 1)
                .last
                .flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let ratingCount = Int(try document.select("#rating_count").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            let favoriteName = try document.select("#gdf").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let api = Self.parseAPIInfo(from: html)
            let comments = try parseComments(from: document)
            let torrent = Self.parseTorrent(from: html, site: site)
            let archiveURL = Self.parseArchiveURL(from: html, site: site)
            let summary = GallerySummary(
                key: key,
                title: title,
                japaneseTitle: japaneseTitle,
                thumbnailURL: thumbnailURL,
                category: category,
                pageCount: pageCount,
                postedAt: info.postedAt,
                rating: rating,
                ratingCount: ratingCount,
                uploader: uploader,
                tags: tags
            )
            let previewPage = try parsePreviewPage(from: document, rawHTML: html, key: key, site: site)
            let externalURL = URL(string: "https://\(site.host)/g/\(key.gid)/\(key.token)/")
            return GalleryDetail(
                summary: summary,
                pages: previewPage.pages,
                tags: tags,
                comments: comments,
                descriptionText: category.map { String(localized: "站点：\(site.displayName) · \($0)") },
                externalURL: externalURL,
                apiUID: api.uid,
                apiKey: api.key,
                favoriteCount: info.favoriteCount,
                favoriteName: favoriteName == "Add to Favorites" ? nil : favoriteName,
                ratingCount: ratingCount,
                language: info.language,
                fileSize: info.fileSize,
                torrentURL: torrent.url,
                torrentCount: torrent.count,
                archiveURL: archiveURL
            )
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.parsingFailed(error.localizedDescription)
        }
    }

    public func parsePreviewPage(data: Data, key: GalleryKey, site: SiteMode) throws -> PreviewPage {
        guard let html = String(data: data, encoding: .utf8) else {
            throw EHError.parsingFailed(String(localized: "页面不是 UTF-8"))
        }
        do {
            return try parsePreviewPage(from: SwiftSoup.parse(html), rawHTML: html, key: key, site: site)
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.parsingFailed(error.localizedDescription)
        }
    }

    private func parsePreviewPage(from document: Document, rawHTML: String, key: GalleryKey, site: SiteMode) throws -> PreviewPage {
        let pageCount = try parsePreviewPageCount(from: document)
        let baseURL = URL(string: "https://\(site.host)/")!
        // The reference regexes run over the raw body markup, not over a
        // serialized DOM whose pretty-printing inserts whitespace.
        let clippedPages = parseClippedPreviewPages(from: rawHTML, key: key, baseURL: baseURL)
        let pages: [GalleryPageDescriptor]
        if clippedPages.isEmpty {
            pages = try parseLegacyPreviewLinks(from: document, key: key, baseURL: baseURL)
        } else {
            pages = clippedPages
        }
        return PreviewPage(
            pages: pages.sorted { $0.index < $1.index },
            pageCount: pageCount
        )
    }

    /// Port of the reference `GalleryDetailParser.parseNormalPreviewSet`:
    /// each preview carries one large image plus the clip window and offset
    /// rendered through `background-position`. Pattern order matters.
    private func parseClippedPreviewPages(from html: String, key: GalleryKey, baseURL: URL) -> [GalleryPageDescriptor] {
        let patterns: [PreviewPattern] = [
            // PATTERN_SMALL_PREVIEW
            PreviewPattern(
                #"<a href="([^"]+?)">[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\((.+?)\)[^<>]*-(\d+)px[^<>]*>"#,
                pageURL: 1, page: 2, width: 3, height: 4, imageURL: 5, xOffset: 6
            ),
            // PATTERN_NORMAL_PREVIEW_NEW
            PreviewPattern(
                #"<a href="([^"]+?)">[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\((.+?)\)[^<>]*"></div>[^<>]*</a>"#,
                pageURL: 1, page: 2, width: 3, height: 4, imageURL: 5, xOffset: nil
            ),
            // PATTERN_SMALL_PREVIEW_WITH_LABEL
            PreviewPattern(
                #"<a href="([^"]+?)">[^<>]*<div>[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\((.+?)\)[^<>]*-(\d+)px[^<>]*>"#,
                pageURL: 1, page: 2, width: 3, height: 4, imageURL: 5, xOffset: 6
            ),
            // PATTERN_NORMAL_PREVIEW_NEW_WITH_LABEL
            PreviewPattern(
                #"<a href="([^"]+?)">[^<>]*<div>[^<>]*<div[^<>]*title="Page (\d+):[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\((.+?)\)[^<>]*">"#,
                pageURL: 1, page: 2, width: 3, height: 4, imageURL: 5, xOffset: nil
            ),
            // PATTERN_NORMAL_PREVIEW
            PreviewPattern(
                #"<div class="gdtm"[^<>]*><div[^<>]*width:(\d+)[^<>]*height:(\d+)[^<>]*\((.+?)\)[^<>]*-(\d+)px[^<>]*><a[^<>]*href="([^"]+?)"[^<>]*><img alt="([\d,]+)""#,
                pageURL: 5, page: 6, width: 1, height: 2, imageURL: 3, xOffset: 4
            ),
        ]

        for pattern in patterns {
            let matches = pattern.regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            guard matches.isEmpty == false else { continue }
            return matches.compactMap { match in
                guard let pageValue = pattern.value(match, at: pattern.page, in: html),
                      let page = Int(pageValue), page >= 1,
                      let widthValue = pattern.value(match, at: pattern.width, in: html),
                      let width = Int(widthValue), width > 0,
                      let heightValue = pattern.value(match, at: pattern.height, in: html),
                      let height = Int(heightValue), height > 0,
                      let href = pattern.value(match, at: pattern.pageURL, in: html),
                      let imageValue = pattern.value(match, at: pattern.imageURL, in: html),
                      let pageURL = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
                let previewURL = URL(string: imageValue, relativeTo: baseURL)?.absoluteURL
                    ?? URL(string: imageValue)
                let xOffset = pattern.xOffset.flatMap { pattern.value(match, at: $0, in: html) }.flatMap(Int.init) ?? 0
                return GalleryPageDescriptor(
                    galleryKey: key,
                    index: page - 1,
                    pageURL: pageURL,
                    previewURL: previewURL,
                    previewClip: GalleryPreviewClip(xOffset: xOffset, width: width, height: height)
                )
            }
        }
        return []
    }

    /// Fallback for simplified or older markup without clip metadata.
    private func parseLegacyPreviewLinks(from document: Document, key: GalleryKey, baseURL: URL) throws -> [GalleryPageDescriptor] {
        let pageLinks = try document.select("#gdt a[href*=/s/], a.gdtm[href]")
        return try pageLinks.compactMap { element -> GalleryPageDescriptor? in
            let href = try element.attr("href")
            guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else { return nil }
            let index = Self.pageIndex(in: url) ?? 0
            let previewURL = try element.select("img").first().flatMap { try $0.attr("src") }.flatMap(URL.init(string:))
                ?? Self.urlInStyle(try element.select("div").first()?.attr("style") ?? "")
            return GalleryPageDescriptor(galleryKey: key, index: index, pageURL: url, previewURL: previewURL)
        }
    }

    private struct PreviewPattern {
        let regex: NSRegularExpression
        let pageURL: Int
        let page: Int
        let width: Int
        let height: Int
        let imageURL: Int
        let xOffset: Int?

        init(_ pattern: String, pageURL: Int, page: Int, width: Int, height: Int, imageURL: Int, xOffset: Int?) {
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.pageURL = pageURL
            self.page = page
            self.width = width
            self.height = height
            self.imageURL = imageURL
            self.xOffset = xOffset
        }

        func value(_ match: NSTextCheckingResult, at group: Int, in source: String) -> String? {
            guard match.range(at: group).location != NSNotFound,
                  let range = Range(match.range(at: group), in: source) else { return nil }
            return String(source[range])
        }
    }

    private func parseSummary(from element: Element) throws -> GallerySummary? {
        let link = try element.select("a[href*=/g/]").first() ?? element
        let href = try link.attr("href")
        guard let key = GalleryKey(url: href) else { return nil }
        let title = try Self.listTitle(from: element, fallback: link.text())
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let thumbnailImage = try element.select(".glthumb img, img").first()
        let thumbnailURL: URL?
        if let thumbnailImage {
            let dataSource = try thumbnailImage.attr("data-src")
            let source = try thumbnailImage.attr("src")
            thumbnailURL = URL(string: dataSource) ?? URL(string: source)
        } else {
            thumbnailURL = nil
        }
        let category = try element.select(".cn, .gl1e").first()?.text()
        let pageCount = try parsePageCount(in: element)
        let rating = try parseRating(in: element)
        // The reference client reads the full tag table hidden in the list
        // row's `.glname` tbody for filtering; the `.gt`/`.gtl` titles only
        // carry a few summary tags and are a fallback for simplified pages.
        var tags = try parseTagGroupRows(try element.select(".glname tbody tr"))
        if tags.isEmpty {
            tags = try element.select(".gt[title]").map { try $0.attr("title") }
            tags += try element.select(".gtl[title]").map { try $0.attr("title") }
        }
        let postedAt = try parsePostedAt(in: element, key: key)
        let favoriteCategory = try parseFavoriteCategory(in: element, key: key)
        let uploader = try parseUploader(in: element)
        return GallerySummary(
            key: key,
            title: title,
            thumbnailURL: thumbnailURL,
            category: category,
            pageCount: pageCount,
            postedAt: postedAt,
            rating: rating,
            favoriteCategory: favoriteCategory,
            uploader: uploader,
            tags: tags
        )
    }

    /// Port of the reference `GalleryDetailParser.parseTagGroups`: the site's
    /// taglist stores the namespace in each row's first cell and the bare tag
    /// names in the second, so tags are reconstructed as `namespace:name` —
    /// required for the reference database lookups to find translations.
    private func parseTagGroups(from document: Document) throws -> [String] {
        guard let taglist = try document.select("#taglist").first() else {
            return try document.select(".gt a").map { try $0.text() }
        }
        let tags = try parseTagGroupRows(try taglist.select("tr"))
        if tags.isEmpty {
            // Simplified pages may list tags as flat links.
            return try document.select("#taglist a").map { try $0.text() }
        }
        return tags
    }

    /// Shared port of the reference `parseTagGroups(Elements trs)`: each
    /// row's first cell is the namespace label (with a trailing colon) and
    /// the second cell holds the bare tag names, so every tag is rebuilt as
    /// `namespace:name`. Used for both the detail taglist and the full tag
    /// table hidden in list rows.
    private func parseTagGroupRows(_ rows: Elements) throws -> [String] {
        var tags: [String] = []
        for row in rows {
            let cells = try row.select("td")
            guard cells.count >= 2 else { continue }
            var namespace = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)
            if namespace.hasSuffix(":") { namespace.removeLast() }
            guard namespace.isEmpty == false else { continue }
            for container in try cells[1].children() {
                var name = try container.text().trimmingCharacters(in: .whitespacesAndNewlines)
                // The site sometimes appends "| english title" to parody tags.
                if let separator = name.firstIndex(of: "|") {
                    name = String(name[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard name.isEmpty == false else { continue }
                tags.append("\(namespace):\(name)")
            }
        }
        return tags
    }

    /// The list title is the site's full display string, like the reference
    /// client's `GalleryListParser`: no `|` splitting, no language heuristics.
    private static func listTitle(from element: Element, fallback: String) throws -> String {
        if let glink = try element.select(".glink").first() {
            return try glink.text()
        }
        if var glname = try element.select(".glname").first() {
            while let firstChild = glname.children().first() {
                glname = firstChild
            }
            let title = try glname.text().trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty == false {
                return title
            }
        }
        return fallback
    }

    /// Uploader lives in the first child of `.glhide` (extended layout) or the
    /// fourth child of `.gl3e` (compact layout), mirroring the reference
    /// client's `GalleryListParser.parseGalleryInfo`.
    private func parseUploader(in element: Element) throws -> String? {
        let containers = try element.select(".glhide, .gl3e")
        for container in containers {
            let children = container.children()
            let index = container.hasClass("gl3e") ? 3 : 0
            guard children.count > index else { continue }
            let anchor = try children[index].select("a").first()
            if let text = try anchor?.text(), text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private struct DetailInfoRows {
        var language: String?
        var fileSize: String?
        var postedAt: Date?
        var favoriteCount: Int?
    }

    /// The `#gdd` table rows labeled like the site's "Posted:", "Language:",
    /// "File Size:" and "Favorited:" cells.
    private func parseInfoRows(from document: Document) throws -> DetailInfoRows {
        var rows = DetailInfoRows()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for row in try document.select("#gdd tr") {
            let cells = try row.select("td")
            guard cells.count >= 2 else { continue }
            let label = try cells[0].text().trimmingCharacters(in: .whitespaces).lowercased()
            let value = try cells[1].text().trimmingCharacters(in: .whitespacesAndNewlines)
            if label.hasPrefix("language") {
                rows.language = value
            } else if label.hasPrefix("file size") {
                rows.fileSize = value
            } else if label.hasPrefix("posted") {
                rows.postedAt = formatter.date(from: value)
            } else if label.hasPrefix("favorited") {
                let number = value.split(separator: " ").first
                    .map { $0.replacingOccurrences(of: ",", with: "") }
                rows.favoriteCount = number.flatMap(Int.init)
            }
        }
        return rows
    }

    private func parsePageCount(in element: Element) throws -> Int? {
        let text = try element.text()
        guard let match = text.range(of: #"[\d,]+\s+pages?"#, options: .regularExpression) else { return nil }
        return text[match].split(whereSeparator: { $0 == " " }).first
            .map { $0.replacingOccurrences(of: ",", with: "") }
            .flatMap(Int.init)
    }

    private func parseRating(in element: Element) throws -> Double? {
        guard let style = try element.select(".ir").first()?.attr("style"),
              let match = style.range(of: #"-?(\d+)px\s+-?(\d+)px"#, options: .regularExpression) else { return nil }
        let values = style[match].split(whereSeparator: { $0 == " " }).compactMap { value in
            Int(value.replacingOccurrences(of: "px", with: "").replacingOccurrences(of: "-", with: ""))
        }
        guard let horizontal = values.first else { return nil }
        var rating = 5.0 - Double(horizontal) / 16.0
        if values.count > 1, values[1] == 21 { rating -= 0.5 }
        return max(0, rating)
    }

    private func parsePostedAt(in element: Element, key: GalleryKey) throws -> Date? {
        guard let text = try element.select("#posted_\(key.gid), #postedpop_\(key.gid)").first()?.text() else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseFavoriteCategory(in element: Element, key: GalleryKey) throws -> Int? {
        guard let style = try element.select("#posted_\(key.gid), #postedpop_\(key.gid)").first()?.attr("style") else { return nil }
        let pattern = #"background-color\s*:\s*rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: style, range: NSRange(style.startIndex..., in: style)) else { return nil }
        let rgb = (1...3).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: style) else { return nil }
            return Int(style[range])
        }
        let colors = [(0, 0, 0), (240, 0, 0), (240, 160, 0), (208, 208, 0), (0, 128, 0), (144, 240, 64), (64, 176, 240), (0, 0, 240), (80, 0, 128), (224, 128, 224)]
        guard rgb.count == 3 else { return nil }
        return colors.firstIndex { $0.0 == rgb[0] && $0.1 == rgb[1] && $0.2 == rgb[2] }
    }

    private func parsePageCount(_ document: Document) throws -> Int? {
        let text = try document.select("#gdd, #gdd1, .gtb").text()
        guard let range = text.range(of: #"\d+\s*pages?"#, options: .regularExpression) else { return nil }
        return text[range].split(whereSeparator: { $0.isNumber == false }).first.flatMap { Int($0) }
    }

    private func parsePreviewPageCount(from document: Document) throws -> Int? {
        let cells = try document.select(".ptt td").map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cells.count >= 2 else { return nil }
        let candidate = cells[cells.count - 2].replacingOccurrences(of: ",", with: "")
        guard let count = Int(candidate), count > 0 else { return nil }
        return count
    }

    private func parseComments(from document: Document) throws -> [GalleryComment] {
        let elements = try document.select("#cdiv .c1")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "dd MMMM yyyy, HH:mm"
        return try elements.enumerated().compactMap { offset, element in
            let siblingName = try element.previousElementSibling()?.attr("name") ?? ""
            let id = siblingName.hasPrefix("#") ? String(siblingName.dropFirst()) : siblingName
            let fallbackID = element.id()
            let c3 = try element.select(".c3").first()
            let author = try c3?.select("a").first()?.text() ?? c3?.text().replacingOccurrences(of: "Posted on ", with: "") ?? ""
            let dateText = c3?.ownText()
                .replacingOccurrences(of: "Posted on ", with: "")
                .components(separatedBy: " by:").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let postedAt = dateText.flatMap(formatter.date(from:))
            let body = try parseCommentBody(from: element.select(".c6").first())
            guard body.isEmpty == false || author.isEmpty == false else { return nil }
            let score = Int(try element.select(".c5").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            let voteState = try element.select(".c7").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let actions = try element.select(".c4 a, .c4 span").map { try $0.text() }
            return GalleryComment(
                id: id.isEmpty ? (fallbackID.isEmpty ? "comment-\(offset)" : fallbackID) : id,
                author: author,
                body: body,
                postedAt: postedAt,
                score: score,
                voteState: voteState,
                isEditable: actions.contains("Edit"),
                canVoteUp: actions.contains("Vote+"),
                canVoteDown: actions.contains("Vote-")
            )
        }
    }

    private func parseCommentBody(from element: Element?) throws -> String {
        guard let element else { return "" }

        var text = try plainText(fromHTML: element.html())
        let escapedMarkupPattern = #"</?(?:a|br|p|div|span|strong|em|b|i|u|s|code|pre|blockquote|li)(?:\s[^>]*)?>"#

        // The site sometimes returns markup as escaped text. Decode at most two
        // extra layers so links and line breaks read naturally without exposing HTML.
        for _ in 0..<2 where text.range(
            of: escapedMarkupPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            let decoded = try plainText(fromHTML: text)
            guard decoded != text else { break }
            text = decoded
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func plainText(fromHTML html: String) throws -> String {
        let lineBreakMarker = "\u{E000}"
        let source = html.replacingOccurrences(
            of: #"<br\s*/?>|</(?:p|div|li|blockquote|pre)\s*>"#,
            with: lineBreakMarker,
            options: [.regularExpression, .caseInsensitive]
        )
        let fragment = try SwiftSoup.parseBodyFragment(source)
        return try fragment.text().replacingOccurrences(of: lineBreakMarker, with: "\n")
    }

    private static func parseAPIInfo(from html: String) -> (uid: Int64?, key: String?) {
        let pattern = #"var\s+gid\s*=\s*(\d+).*?var\s+token\s*=\s*['\"]([a-f0-9]+)['\"].*?var\s+apiuid\s*=\s*(-?\d+).*?var\s+apikey\s*=\s*['\"]([a-f0-9]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let uidRange = Range(match.range(at: 3), in: html),
              let keyRange = Range(match.range(at: 4), in: html) else { return (nil, nil) }
        return (Int64(html[uidRange]), String(html[keyRange]))
    }

    private static func parseTorrent(from html: String, site: SiteMode) -> (url: URL?, count: Int?) {
        let pattern = #"onclick\s*=\s*['\"]return\s+popUp\(['\"]([^'\"]+)['\"][^)]*\)['\"][^>]*>\s*Torrent\s+Download\s*\((\d+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let urlRange = Range(match.range(at: 1), in: html),
              let countRange = Range(match.range(at: 2), in: html) else { return (nil, nil) }
        let url = URL(string: String(html[urlRange]), relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL
        return (url, Int(html[countRange]))
    }

    private static func parseArchiveURL(from html: String, site: SiteMode) -> URL? {
        let pattern = #"onclick\s*=\s*['\"]return\s+popUp\(['\"]([^'\"]+)['\"][^)]*\)['\"][^>]*>\s*Archive\s+Download"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return URL(string: String(html[range]), relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL
    }

    private static func urlInStyle(_ style: String) -> URL? {
        guard let range = style.range(of: #"url\((['\"]?)([^)'\"]+)\1\)"#, options: .regularExpression) else { return nil }
        let value = String(style[range])
            .replacingOccurrences(of: "url(", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "'\")"))
        return URL(string: value)
    }

    private static func nilIfBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func pageIndex(in url: URL) -> Int? {
        guard let last = url.path.split(separator: "/").last else { return nil }
        let pieces = last.split(separator: "-", maxSplits: 1)
        return pieces.last.flatMap { Int($0).map { $0 - 1 } }
    }
}

private extension GalleryKey {
    init?(url: String) {
        guard let components = URLComponents(string: url) else { return nil }
        let pieces = components.path.split(separator: "/")
        guard pieces.count >= 3, pieces[0] == "g", let gid = Int64(pieces[1]) else { return nil }
        self.init(gid: gid, token: String(pieces[2]))
    }
}
