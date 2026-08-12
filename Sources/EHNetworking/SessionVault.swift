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
            throw EHError.storageFailed("Keychain 读取失败（\(status)）")
        }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    public func saveCookieHeader(_ cookieHeader: String) throws {
        guard let parsed = CookieHeader.parse(cookieHeader) else { throw EHError.invalidCookie }
        let normalizedHeader = parsed.headerValue
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
                throw EHError.storageFailed("Keychain 写入失败（\(addStatus)）")
            }
        } else if status != errSecSuccess {
            throw EHError.storageFailed("Keychain 更新失败（\(status)）")
        }
        #endif
    }

    public func saveSetCookieHeaders(_ headers: [String], url: URL) throws {
        var responseHeaders: [String: String] = [:]
        responseHeaders["Set-Cookie"] = headers.joined(separator: ", ")
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaders, for: url)
        let cookieHeader = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        try saveCookieHeader(cookieHeader)
    }

    public func clear() throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EHError.storageFailed("Keychain 删除失败（\(status)）")
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
    public let values: [String: String]

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
        values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
    }
}
