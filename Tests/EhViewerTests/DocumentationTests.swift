import Testing

@testable import EhViewerPreview

struct DocumentationTests {
    @Test("Usage documentation uses the bundled help resource")
    func usageDocumentationResource() {
        #expect(DocumentationDocument.help.resourceName == "HELP")
        #expect(DocumentationDocument.help.localURL?.absoluteString == "ehviewer-doc://help")
        #expect(DocumentationContent.resourceSubdirectory == "Documentation")
    }

    @Test("Markdown converts headings, lists, inline emphasis and links to HTML")
    func markdownRendersSafeHTML() {
        let renderer = MarkdownHTMLRenderer { destination in
            DocumentationDocument.fromLinkDestination(destination)?.localURL?.absoluteString ?? destination
        }
        let html = renderer.render("""
        # 使用说明

        **重点**：请先阅读 `快速开始`。

        - 第一项
        - 第二项

        [外部链接](https://example.com)
        [隐私说明](PRIVACY.md)
        <a href="https://example.org">HTML 外部链接</a>
        """)

        #expect(html.contains("<h1 id=\"使用说明\">使用说明</h1>"))
        #expect(html.contains("<strong>重点</strong>"))
        #expect(html.contains("<code>快速开始</code>"))
        #expect(html.contains("<ul><li>第一项</li><li>第二项</li></ul>"))
        #expect(html.contains("href=\"https://example.com\""))
        #expect(html.contains("href=\"ehviewer-doc://privacy\""))
        #expect(html.contains("<a href=\"https://example.org\">HTML 外部链接</a>"))
        #expect(html.contains("&lt;a") == false)
        #expect(html.contains("&lt;" ) == false)
    }

    @Test("Markdown document links resolve to local document routes")
    func documentLinksResolve() throws {
        let privacy = try #require(DocumentationDocument.fromLinkDestination("PRIVACY.md#本地保存的数据"))
        #expect(privacy == .privacy)
        #expect(DocumentationDocument.fromLinkDestination("#快速开始") == nil)
        #expect(DocumentationDocument.fromLinkDestination("https://example.com/page.md") == nil)
    }

    @Test("Documentation HTML matches the website visual language and adapts to width")
    func documentationHTMLUsesResponsiveTheme() {
        let html = DocumentationHTML.document(content: "<h1>使用说明</h1>")

        #expect(html.contains("viewport-fit=cover"))
        #expect(html.contains("--accent: #429488"))
        #expect(html.contains("grid-template-columns: minmax(164px, 220px) minmax(0, 880px)"))
        #expect(html.contains("<aside class=\"toc\""))
        #expect(html.contains("id=\"toc\""))
        #expect(html.contains("IntersectionObserver"))
        #expect(html.contains("overflow-wrap: anywhere"))
        #expect(html.contains("@media (max-width: 560px)"))
        #expect(html.contains("@media (max-width: 980px)"))
        #expect(html.contains("prefers-color-scheme: dark"))
    }
}
