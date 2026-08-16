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

public enum EHError: LocalizedError, Hashable, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case networkFailed(String)
    case notFound
    case authenticationRequired
    case rateLimited
    case bandwidthLimited
    case parsingFailed(String)
    case invalidCookie
    case exHentaiAccessDenied
    case diskSpaceLow
    case storageFailed(String)
    case unsupportedFeature(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL: String(localized: "无效的站点地址")
        case .invalidResponse: String(localized: "服务器响应无效")
        case .httpStatus(let code): String(localized: "服务器返回 HTTP \(code)")
        case .networkFailed(let reason): String(localized: "网络请求失败：\(reason)")
        case .notFound: String(localized: "找不到画廊")
        case .authenticationRequired: String(localized: "此操作需要登录")
        case .rateLimited: String(localized: "请求过于频繁，请稍后再试")
        case .bandwidthLimited: String(localized: "已达到站点流量限制")
        case .parsingFailed(let reason): String(localized: "页面解析失败：\(reason)")
        case .invalidCookie: String(localized: "Cookie 格式无效")
        case .exHentaiAccessDenied: String(localized: "ExHentai 会话无效或无访问权限（igneous 未正确签发）。请重新进行网页登录，并确认账号可访问 ExHentai")
        case .diskSpaceLow: String(localized: "磁盘空间不足，下载已暂停")
        case .storageFailed(let reason): String(localized: "本地存储失败：\(reason)")
        case .unsupportedFeature(let feature): String(localized: "当前版本暂不支持：\(feature)")
        case .cancelled: String(localized: "操作已取消")
        }
    }
}
