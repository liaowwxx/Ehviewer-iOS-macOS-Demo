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

import SwiftUI
import UniformTypeIdentifiers

struct MigrationDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    static let writableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct MigrationExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .zip]
    static let writableContentTypes: [UTType] = [.json, .zip]

    let sourceURL: URL?
    let data: Data

    init(data: Data) {
        sourceURL = nil
        self.data = data
    }

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        data = Data()
    }

    init(configuration: ReadConfiguration) throws {
        sourceURL = nil
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceURL {
            return try FileWrapper(url: sourceURL, options: [])
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
