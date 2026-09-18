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
import WebKit
import EHNetworking

enum WebLoginCookieSupport {
    @MainActor
    static func baseAuthenticationHeader(from webView: WKWebView) async -> String? {
        let header = CookieHeader(values: await authenticationValues(from: webView))
        return header.isAuthenticated ? header.sessionHeaderValue : nil
    }

    @MainActor
    static func exHentaiAuthenticationHeader(from webView: WKWebView) async -> String? {
        let header = CookieHeader(values: await authenticationValues(from: webView))
        return header.isExHentaiAuthenticated ? header.sessionHeaderValue : nil
    }

    @MainActor
    static func copyBaseAuthenticationCookies(from webView: WKWebView) async -> Bool {
        guard let headerValue = await baseAuthenticationHeader(from: webView),
              let header = CookieHeader.parse(headerValue) else { return false }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let exCookies = cookies.filter { isExHentaiDomain($0.domain) }
        let matchesAccount = CookieHeader.requiredAuthenticationNames.allSatisfy { name in
            let matches = exCookies.filter { $0.name == name }
            return !matches.isEmpty && matches.allSatisfy { $0.value == header.values[name] }
        }
        if !matchesAccount {
            for cookie in exCookies where cookie.name == CookieHeader.igneousName {
                guard !Task.isCancelled else { return false }
                await withCheckedContinuation { continuation in
                    store.delete(cookie) { continuation.resume() }
                }
            }
        }
        for domain in [".e-hentai.org", ".exhentai.org"] {
            for name in CookieHeader.requiredAuthenticationNames {
                guard !Task.isCancelled else { return false }
                guard let value = header.values[name],
                      let cookie = HTTPCookie(properties: [
                        .domain: domain,
                        .path: "/",
                        .name: name,
                        .value: value,
                        .secure: "TRUE"
                      ]) else { return false }
                await withCheckedContinuation { continuation in
                    store.setCookie(cookie) { continuation.resume() }
                }
            }
        }
        return true
    }

    @MainActor
    private static func authenticationValues(from webView: WKWebView) async -> [String: String] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        return authenticationValues(from: cookies)
    }

    static func authenticationValues(from cookies: [HTTPCookie]) -> [String: String] {
        let valid = cookies.filter { !$0.value.isEmpty && ($0.expiresDate.map { $0 > Date() } ?? true) }
        let domains = ["forums.e-hentai.org", "e-hentai.org", "exhentai.org"]
        func normalizedDomain(_ cookie: HTTPCookie) -> String {
            cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
        for domain in domains {
            let group = valid.filter { normalizedDomain($0) == domain && $0.path == "/" }
            var values: [String: String] = [:]
            for name in CookieHeader.requiredAuthenticationNames {
                let matches = group.filter { $0.name == name }
                guard Set(matches.map(\.value)).count == 1 else { continue }
                values[name] = matches.first?.value
            }
            guard CookieHeader(values: values).isAuthenticated else { continue }
            let exCookies = valid.filter { normalizedDomain($0) == "exhentai.org" && $0.path == "/" }
            // An igneous belongs to the EX account pair, not just to the domain.
            if CookieHeader.requiredAuthenticationNames.allSatisfy({ name in
                let matches = exCookies.filter { $0.name == name }
                return !matches.isEmpty && matches.allSatisfy { $0.value == values[name] }
            }) {
                let matches = exCookies.filter { $0.name == CookieHeader.igneousName && CookieHeader.isValidIgneousValue($0.value) }
                if Set(matches.map(\.value)).count == 1 { values[CookieHeader.igneousName] = matches.first?.value }
            }
            return values
        }
        return [:]
    }

    private static func isExHentaiDomain(_ domain: String) -> Bool {
        let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized == "exhentai.org" || normalized.hasSuffix(".exhentai.org")
    }
}
