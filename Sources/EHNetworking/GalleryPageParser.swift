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

public struct GalleryPageParser: Sendable {
    public init() {}

    public func parse(data: Data, descriptor: GalleryPageDescriptor, site: SiteMode) throws -> GalleryPageImage {
        guard let body = String(data: data, encoding: .utf8) else {
            throw EHError.parsingFailed("页面不是 UTF-8")
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).first == "{" {
            return try parseJSON(body, descriptor: descriptor, site: site)
        }
        return try parseHTML(body, descriptor: descriptor, site: site)
    }

    private func parseHTML(_ body: String, descriptor: GalleryPageDescriptor, site: SiteMode) throws -> GalleryPageImage {
        let document = try SwiftSoup.parse(body)
        guard let imageElement = try document.select("#img, #i3 img").first() else {
            throw EHError.parsingFailed("找不到页面图片")
        }
        let imageURL = try absoluteURL(try imageElement.attr("src"), site: site)
        let originURL: URL?
        if let originElement = try document.select("#i7 a[href*='fullimg.php']").first() {
            originURL = try absoluteURL(try originElement.attr("href"), site: site)
        } else {
            originURL = nil
        }
        let info = try document.select("#i2, #i4, #i7").text()
        let metadata = parseInfo(info)
        let skipHathKey = parseCapture(try imageElement.attr("onerror"), pattern: #"nl\(['\"]([^'\"]+)['\"]\)"#)
        let showKey = parseCapture(body, pattern: #"(?:var\s+)?showkey\s*=\s*['\"]([^'\"]+)['\"]"#)
        return GalleryPageImage(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            imageURL: imageURL,
            originImageURL: originURL,
            fileName: metadata.fileName,
            width: metadata.width,
            height: metadata.height,
            byteCount: metadata.byteCount,
            skipHathKey: skipHathKey,
            showKey: showKey
        )
    }

    private func parseJSON(_ body: String, descriptor: GalleryPageDescriptor, site: SiteMode) throws -> GalleryPageImage {
        let payload = try JSONDecoder().decode(PageAPIResponse.self, from: Data(body.utf8))
        let fragment = try SwiftSoup.parse(payload.imageFragment)
        guard let imageElement = try fragment.select("#img, img").first() else {
            throw EHError.parsingFailed("页面 API 没有返回图片")
        }
        let imageURL = try absoluteURL(try imageElement.attr("src"), site: site)
        let originFragment = try SwiftSoup.parse(payload.originFragment ?? "")
        let originURL: URL?
        if let originElement = try originFragment.select("a[href*='fullimg.php']").first() {
            originURL = try absoluteURL(try originElement.attr("href"), site: site)
        } else {
            originURL = nil
        }
        let metadata = parseInfo(payload.infoFragment ?? "")
        let skipHathKey = parseCapture(try imageElement.attr("onerror"), pattern: #"nl\(['\"]([^'\"]+)['\"]\)"#)
        return GalleryPageImage(
            galleryKey: descriptor.galleryKey,
            index: descriptor.index,
            imageURL: imageURL,
            originImageURL: originURL,
            fileName: metadata.fileName,
            width: payload.width.flatMap(Int.init) ?? metadata.width,
            height: payload.height.flatMap(Int.init) ?? metadata.height,
            byteCount: metadata.byteCount,
            skipHathKey: skipHathKey,
            showKey: nil
        )
    }

    private func absoluteURL(_ string: String, site: SiteMode) throws -> URL {
        guard let url = URL(string: string, relativeTo: URL(string: "https://\(site.host)/"))?.absoluteURL else {
            throw EHError.invalidURL
        }
        return url
    }

    private func parseCapture(_ value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private func parseInfo(_ text: String) -> PageMetadata {
        let pattern = #"([^:<]+?)\s*::\s*(\d+)\s*x\s*(\d+)\s*::\s*([0-9.]+)\s*(KB|MB|GB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return PageMetadata() }
        func capture(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
        let unit = capture(5)
        let multiplier: Double = switch unit {
        case "GB": 1024 * 1024 * 1024
        case "MB": 1024 * 1024
        default: 1024
        }
        return PageMetadata(
            fileName: capture(1)?.trimmingCharacters(in: .whitespaces),
            width: capture(2).flatMap(Int.init),
            height: capture(3).flatMap(Int.init),
            byteCount: capture(4).flatMap(Double.init).map { Int64($0 * multiplier) }
        )
    }
}

private struct PageMetadata: Sendable {
    let fileName: String?
    let width: Int?
    let height: Int?
    let byteCount: Int64?

    init(fileName: String? = nil, width: Int? = nil, height: Int? = nil, byteCount: Int64? = nil) {
        self.fileName = fileName
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }
}

private struct PageAPIResponse: Decodable {
    let infoFragment: String?
    let imageFragment: String
    let originFragment: String?
    let width: String?
    let height: String?

    enum CodingKeys: String, CodingKey {
        case infoFragment = "i"
        case imageFragment = "i3"
        case originFragment = "i7"
        case width = "x"
        case height = "y"
    }
}
