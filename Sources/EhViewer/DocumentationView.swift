/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI

struct DocumentationView: View {
    @Environment(\.openURL) private var openURL
    @State private var document: DocumentationDocument

    init(document: DocumentationDocument = .help) {
        _document = State(initialValue: document)
    }

    private var html: String {
        let renderer = MarkdownHTMLRenderer { destination in
            guard let linkedDocument = DocumentationDocument.fromLinkDestination(destination) else {
                return destination
            }
            return linkedDocument.localURL?.absoluteString ?? destination
        }
        let content = renderer.render(DocumentationContent.markdown(for: document))
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <style>
                :root { color-scheme: light dark; }
                html, body { background: Canvas; color: CanvasText; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
                    margin: 0;
                    padding: 24px 20px 40px;
                    line-height: 1.55;
                    font-size: 17px;
                    -webkit-text-size-adjust: 100%;
                }
                article { max-width: 760px; margin: 0 auto; }
                h1, h2, h3, h4 { line-height: 1.2; margin: 1.5em 0 0.55em; }
                h1 { font-size: 2em; margin-top: 0; }
                h2 { font-size: 1.45em; }
                h3 { font-size: 1.2em; }
                p, ul, ol, blockquote, pre { margin: 0 0 1em; }
                ul, ol { padding-left: 1.4em; }
                li + li { margin-top: 0.35em; }
                a { color: LinkText; text-decoration-thickness: 1px; }
                blockquote {
                    border-left: 3px solid GrayText;
                    color: GrayText;
                    margin-left: 0;
                    padding-left: 14px;
                }
                code {
                    background: color-mix(in srgb, CanvasText 10%, Canvas);
                    border-radius: 5px;
                    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
                    font-size: 0.9em;
                    padding: 0.1em 0.3em;
                }
                pre {
                    background: color-mix(in srgb, CanvasText 10%, Canvas);
                    border-radius: 10px;
                    overflow-x: auto;
                    padding: 14px;
                }
                pre code { background: transparent; padding: 0; }
                hr { border: 0; border-top: 1px solid GrayText; margin: 1.8em 0; }
                img { max-width: 100%; height: auto; }
                @media (prefers-color-scheme: dark) {
                    body { background: #000; color: #fff; }
                }
            </style>
        </head>
        <body><article>\(content)</article></body>
        </html>
        """
    }

    var body: some View {
        DocumentationWebView(
            html: html,
            baseURL: Bundle.main.resourceURL,
            onExternalURL: { url in
                openURL(url)
            },
            onDocumentLink: { linkedDocument in
                document = linkedDocument
            }
        )
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(DocumentationDocument.allCases) { candidate in
                        Button {
                            document = candidate
                        } label: {
                            Label(candidate.title, systemImage: candidate == document ? "checkmark" : "doc.text")
                        }
                    }
                } label: {
                    Label("文档", systemImage: "doc.text")
                }
                .accessibilityIdentifier("documentation-menu")
            }
        }
        .accessibilityIdentifier("documentation-screen")
    }
}
