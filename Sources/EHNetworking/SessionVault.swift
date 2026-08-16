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
#if canImport(Security)
import Security
#endif

public actor SessionVault {
    private let service: String
    private let account: String

    public init(service: String = "com.liao.ehviewer", account: String = "session-cookie") {
        self.service = service
        self.account = account
    }

    public func loadCookieHeader() throws -> String? {
        #if canImport(Security)
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw EHError.storageFailed(String(localized: "Keychain 读取失败（\(status)）"))
        }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    public func loadAuthenticatedCookieHeader() throws -> String? {
        guard let storedHeader = try loadCookieHeader(),
              let parsed = CookieHeader.parse(storedHeader),
              parsed.isAuthenticated else { return nil }
        return parsed.sessionHeaderValue
    }

    public func hasExHentaiSession() throws -> Bool {
        guard let storedHeader = try loadCookieHeader(),
              let parsed = CookieHeader.parse(storedHeader) else { return false }
        return parsed.isExHentaiAuthenticated
    }

    public func saveCookieHeader(_ cookieHeader: String) throws {
        guard let parsed = CookieHeader.parse(cookieHeader), parsed.isAuthenticated else {
            throw EHError.invalidCookie
        }
        if parsed.values[CookieHeader.igneousName] != nil, parsed.hasValidIgneous == false {
            throw EHError.invalidCookie
        }
        let normalizedHeader = parsed.sessionHeaderValue
        #if canImport(Security)
        let data = Data(normalizedHeader.utf8)
        let query = baseQuery as CFDictionary
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw EHError.storageFailed(String(localized: "Keychain 写入失败（\(addStatus)）"))
            }
        } else if status != errSecSuccess {
            throw EHError.storageFailed(String(localized: "Keychain 更新失败（\(status)）"))
        }
        #endif
    }

    @discardableResult
    public func saveSetCookieHeaders(_ headers: [String], url: URL) throws -> Bool {
        let previous = try loadCookieHeader().flatMap(CookieHeader.parse)
        var values = previous?.values ?? [:]
        let previousHeader = previous?.sessionHeaderValue
        var foundSessionCookie = false
        for header in headers {
            let cookies = HTTPCookie.cookies(
                withResponseHeaderFields: ["Set-Cookie": header],
                for: url
            )
            for cookie in cookies where CookieHeader.persistedCookieNames.contains(cookie.name) {
                foundSessionCookie = true
                if cookie.value.isEmpty
                    || cookie.expiresDate.map({ $0 <= Date() }) == true
                    || (cookie.name == CookieHeader.igneousName
                        && CookieHeader.isValidIgneousValue(cookie.value) == false) {
                    values.removeValue(forKey: cookie.name)
                } else {
                    values[cookie.name] = cookie.value
                }
            }
        }
        guard foundSessionCookie else { return false }

        let merged = CookieHeader(values: values)
        guard merged.isAuthenticated else {
            if previous?.isAuthenticated == true { try clear() }
            throw EHError.invalidCookie
        }
        let hadRejectedIgneous = previous?.values[CookieHeader.igneousName]
            .map { CookieHeader.isValidIgneousValue($0) == false } == true
        guard merged.sessionHeaderValue != previousHeader || hadRejectedIgneous else { return false }
        try saveCookieHeader(merged.sessionHeaderValue)
        return true
    }

    @discardableResult
    public func clearIgneous() throws -> Bool {
        guard let storedHeader = try loadCookieHeader(),
              let parsed = CookieHeader.parse(storedHeader),
              parsed.values[CookieHeader.igneousName] != nil else { return false }
        var values = parsed.values
        values.removeValue(forKey: CookieHeader.igneousName)
        let updated = CookieHeader(values: values)
        guard updated.isAuthenticated else {
            try clear()
            return true
        }
        try saveCookieHeader(updated.sessionHeaderValue)
        return true
    }

    public func hasAuthenticatedSession() throws -> Bool {
        try loadAuthenticatedCookieHeader() != nil
    }

    public func clear() throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EHError.storageFailed(String(localized: "Keychain 删除失败（\(status)）"))
        }
        #endif
    }

    #if canImport(Security)
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    #endif
}

public struct CookieHeader: Hashable, Sendable {
    public static let memberIDName = "ipb_member_id"
    public static let passwordHashName = "ipb_pass_hash"
    public static let igneousName = "igneous"
    public static let requiredAuthenticationNames: Set<String> = [memberIDName, passwordHashName]
    public static let persistedCookieNames: Set<String> = requiredAuthenticationNames.union([igneousName])

    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public static func parse(_ header: String) -> CookieHeader? {
        var values: [String: String] = [:]
        for pair in header.split(separator: ";") {
            let components = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard components.count == 2 else { continue }
            let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, value.isEmpty == false else { continue }
            values[name] = value
        }
        return values.isEmpty ? nil : CookieHeader(values: values)
    }

    public var headerValue: String {
        values.keys.sorted().compactMap { name in
            values[name].map { "\(name)=\($0)" }
        }.joined(separator: "; ")
    }

    public var sessionHeaderValue: String {
        values.keys
            .filter { name in
                guard Self.persistedCookieNames.contains(name) else { return false }
                guard name == Self.igneousName else { return true }
                return Self.isValidIgneousValue(values[name])
            }
            .sorted()
            .compactMap { name in values[name].map { "\(name)=\($0)" } }
            .joined(separator: "; ")
    }

    public var isAuthenticated: Bool {
        Self.requiredAuthenticationNames.allSatisfy { name in
            values[name]?.isEmpty == false
        }
    }

    public var hasValidIgneous: Bool {
        Self.isValidIgneousValue(values[Self.igneousName])
    }

    public var isExHentaiAuthenticated: Bool {
        isAuthenticated && hasValidIgneous
    }

    public static func isValidIgneousValue(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              normalized.isEmpty == false else { return false }
        return normalized != "mystery" && normalized != "null"
    }
}
