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
