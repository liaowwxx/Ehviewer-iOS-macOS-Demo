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
        return DocumentationHTML.document(content: content)
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
