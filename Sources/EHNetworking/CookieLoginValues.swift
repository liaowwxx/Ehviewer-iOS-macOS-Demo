import Foundation

/// Values entered into the three fixed-name Cookie login fields.
public struct CookieLoginValues: Sendable {
    public var memberID: String
    public var passwordHash: String
    public var igneous: String

    public init(memberID: String = "", passwordHash: String = "", igneous: String = "") {
        self.memberID = memberID
        self.passwordHash = passwordHash
        self.igneous = igneous
    }

    public static func normalized(_ input: String, name: String) -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equal = value.firstIndex(of: "="),
              value[..<equal].trimmingCharacters(in: .whitespaces) == name else { return value }
        return value[value.index(after: equal)...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func error(for name: String) -> String? {
        let input = switch name {
        case CookieHeader.memberIDName: memberID
        case CookieHeader.passwordHashName: passwordHash
        default: igneous
        }
        let value = Self.normalized(input, name: name)
        if input.contains(";") || input.contains(where: { $0.isNewline }) {
            return String(localized: "请只填写该项的值")
        }
        if let equal = value.firstIndex(of: "="),
           CookieHeader.persistedCookieNames.contains(String(value[..<equal]).trimmingCharacters(in: .whitespaces)) {
            return String(localized: "请只填写该项的值")
        }
        if name == CookieHeader.igneousName, !value.isEmpty, !CookieHeader.isValidIgneousValue(value) {
            return String(localized: "igneous 不能是 mystery 或 null，请填写有效值或留空")
        }
        return nil
    }

    public var cookieHeader: String? {
        guard CookieHeader.persistedCookieNames.allSatisfy({ error(for: $0) == nil }) else { return nil }
        var values = [
            CookieHeader.memberIDName: Self.normalized(memberID, name: CookieHeader.memberIDName),
            CookieHeader.passwordHashName: Self.normalized(passwordHash, name: CookieHeader.passwordHashName)
        ]
        guard values.values.allSatisfy({ !$0.isEmpty }) else { return nil }
        let optional = Self.normalized(igneous, name: CookieHeader.igneousName)
        if !optional.isEmpty { values[CookieHeader.igneousName] = optional }
        return CookieHeader(values: values).sessionHeaderValue
    }
}
