/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

enum DocumentationDocument: String, CaseIterable, Identifiable, Sendable {
    case help = "HELP"
    case privacy = "PRIVACY"
    case changelog = "CHANGELOG"
    case readme = "README"

    var id: Self { self }

    var title: String {
        switch self {
        case .help: "使用说明"
        case .privacy: "隐私说明"
        case .changelog: "更新日志"
        case .readme: "项目 README"
        }
    }

    var resourceName: String { rawValue }

    var localURL: URL? {
        URL(string: "ehviewer-doc://\(rawValue.lowercased())")
    }

    static func fromLinkDestination(_ destination: String) -> DocumentationDocument? {
        let path = destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let path, path.hasSuffix(".md") else { return nil }
        return allCases.first { $0.resourceName.caseInsensitiveCompare(String(path.dropLast(3))) == .orderedSame }
    }
}

enum DocumentationContent {
    static func markdown(for document: DocumentationDocument, bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: document.resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            return "# \(document.title)\n\n文档暂时无法加载。"
        }
        return markdown
    }
}

struct MarkdownHTMLRenderer {
    private let resolveLink: (String) -> String

    init(resolveLink: @escaping (String) -> String = { $0 }) {
        self.resolveLink = resolveLink
    }

    func render(_ markdown: String) -> String {
        let lines = markdown
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var output: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") == false {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                let className = language.isEmpty ? "" : " class=\"language-\(attributeEscape(language))\""
                output.append("<pre><code\(className)>\(htmlEscape(codeLines.joined(separator: "\n")))</code></pre>")
                continue
            }

            if let heading = heading(from: trimmed) {
                output.append("<h\(heading.level) id=\"\(anchorID(for: heading.text))\">\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                output.append("<hr>")
                index += 1
                continue
            }

            if let item = unorderedItem(from: trimmed) {
                var items = [item]
                index += 1
                while index < lines.count, let nextItem = unorderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextItem)
                    index += 1
                }
                output.append("<ul>\(items.map { "<li>\(renderInline($0))</li>" }.joined())</ul>")
                continue
            }

            if let item = orderedItem(from: trimmed) {
                var items = [item]
                index += 1
                while index < lines.count, let nextItem = orderedItem(from: lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(nextItem)
                    index += 1
                }
                output.append("<ol>\(items.map { "<li>\(renderInline($0))</li>" }.joined())</ol>")
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                output.append("<blockquote>\(quoteLines.map(renderInline).joined(separator: "<br>"))</blockquote>")
                continue
            }

            var paragraphLines = [trimmed]
            index += 1
            while index < lines.count {
                let next = lines[index].trimmingCharacters(in: .whitespaces)
                guard next.isEmpty == false,
                      heading(from: next) == nil,
                      isHorizontalRule(next) == false,
                      unorderedItem(from: next) == nil,
                      orderedItem(from: next) == nil,
                      next.hasPrefix(">") == false,
                      next.hasPrefix("```") == false else { break }
                paragraphLines.append(next)
                index += 1
            }
            output.append("<p>\(paragraphLines.map(renderInline).joined(separator: " "))</p>")
        }

        return output.joined(separator: "\n")
    }

    private func renderInline(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "<", let anchor = rawAnchor(at: index, in: text) {
                result += "<a href=\"\(attributeEscape(resolveLink(anchor.destination)))\">\(renderInline(anchor.label))</a>"
                index = anchor.end
                continue
            }

            if text[index] == "`", let close = text[text.index(after: index)...].firstIndex(of: "`") {
                let codeStart = text.index(after: index)
                result += "<code>\(htmlEscape(String(text[codeStart..<close])))</code>"
                index = text.index(after: close)
                continue
            }

            if text[index...].hasPrefix("**"),
               let closeRange = text[text.index(index, offsetBy: 2)..<text.endIndex].range(of: "**") {
                let contentStart = text.index(index, offsetBy: 2)
                result += "<strong>\(renderInline(String(text[contentStart..<closeRange.lowerBound])))</strong>"
                index = closeRange.upperBound
                continue
            }

            if text[index] == "[",
               let closeBracket = text[text.index(after: index)...].firstIndex(of: "]") {
                let openParenthesis = text.index(after: closeBracket)
                if openParenthesis < text.endIndex, text[openParenthesis] == "(",
                   let closeParenthesis = text[text.index(after: openParenthesis)...].firstIndex(of: ")") {
                    let labelStart = text.index(after: index)
                    let destinationStart = text.index(after: openParenthesis)
                    let label = String(text[labelStart..<closeBracket])
                    let destination = String(text[destinationStart..<closeParenthesis])
                    result += "<a href=\"\(attributeEscape(resolveLink(destination)))\">\(renderInline(label))</a>"
                    index = text.index(after: closeParenthesis)
                    continue
                }
            }

            let character = text[index]
            result += htmlEscape(String(character))
            index = text.index(after: index)
        }

        return result
    }

    private func rawAnchor(at index: String.Index, in text: String) -> (destination: String, label: String, end: String.Index)? {
        guard let openingTagEnd = text[index...].firstIndex(of: ">") else { return nil }
        let openingTag = String(text[index...openingTagEnd])
        guard openingTag.lowercased().hasPrefix("<a") else { return nil }

        let nameEnd = openingTag.index(openingTag.startIndex, offsetBy: 2)
        guard nameEnd < openingTag.endIndex,
              openingTag[nameEnd].isWhitespace || openingTag[nameEnd] == ">",
              let destination = htmlAttribute(named: "href", in: openingTag) else {
            return nil
        }

        let labelStart = text.index(after: openingTagEnd)
        guard let closingTag = text.range(
            of: "</a>",
            options: .caseInsensitive,
            range: labelStart..<text.endIndex
        ) else {
            return nil
        }

        return (
            destination,
            String(text[labelStart..<closingTag.lowerBound]),
            closingTag.upperBound
        )
    }

    private func htmlAttribute(named name: String, in tag: String) -> String? {
        guard let nameRange = tag.range(of: name, options: .caseInsensitive) else { return nil }
        guard nameRange.lowerBound == tag.startIndex || tag[tag.index(before: nameRange.lowerBound)].isWhitespace else {
            return nil
        }

        var valueStart = nameRange.upperBound
        while valueStart < tag.endIndex, tag[valueStart].isWhitespace {
            valueStart = tag.index(after: valueStart)
        }
        guard valueStart < tag.endIndex, tag[valueStart] == "=" else { return nil }

        valueStart = tag.index(after: valueStart)
        while valueStart < tag.endIndex, tag[valueStart].isWhitespace {
            valueStart = tag.index(after: valueStart)
        }
        guard valueStart < tag.endIndex else { return nil }

        let quote = tag[valueStart]
        if quote == "\"" || quote == "'" {
            let contentStart = tag.index(after: valueStart)
            guard let contentEnd = tag[contentStart...].firstIndex(of: quote) else { return nil }
            return String(tag[contentStart..<contentEnd])
        }

        var contentEnd = valueStart
        while contentEnd < tag.endIndex, tag[contentEnd].isWhitespace == false, tag[contentEnd] != ">" {
            contentEnd = tag.index(after: contentEnd)
        }
        return String(tag[valueStart..<contentEnd])
    }

    private func heading(from line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count),
              line.dropFirst(hashes.count).first?.isWhitespace == true else { return nil }
        return (hashes.count, line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces))
    }

    private func unorderedItem(from line: String) -> String? {
        guard let marker = line.first, ["-", "*", "+"].contains(marker),
              line.dropFirst().first?.isWhitespace == true else { return nil }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private func orderedItem(from line: String) -> String? {
        let digits = line.prefix(while: { $0.isNumber })
        guard digits.isEmpty == false,
              line.dropFirst(digits.count).first == ".",
              line.dropFirst(digits.count + 1).first?.isWhitespace == true else { return nil }
        return line.dropFirst(digits.count + 1).trimmingCharacters(in: .whitespaces)
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        ["---", "***", "___"].contains(line)
    }

    private func anchorID(for text: String) -> String {
        let normalized = text
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func htmlEscape(_ value: String) -> String {
        value
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
            .replacing("\"", with: "&quot;")
            .replacing("'", with: "&#39;")
    }

    private func attributeEscape(_ value: String) -> String {
        htmlEscape(value)
    }
}
