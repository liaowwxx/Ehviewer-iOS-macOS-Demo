import Foundation
import EHDomain

/// One bounded stream into an invisible temporary page. Completed pages are
/// retained at stable paths across sync interruptions; partial pages never read.
public actor TranslationPageReceiver {
    private let page: GalleryTranslationManifest.Page
    private let temporary: URL
    private let target: URL
    private let handle: FileHandle
    private var count: Int64 = 0

    public init(directory: URL, page: GalleryTranslationManifest.Page) throws {
        self.page = page
        target = directory.appendingPathComponent(page.fileName)
        temporary = directory.appendingPathComponent("\(UUID().uuidString).part")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw EHError.diskSpaceLow }
        handle = try FileHandle(forWritingTo: temporary)
    }

    deinit { try? handle.close() }

    public func append(_ data: Data) throws {
        guard count + Int64(data.count) <= page.byteCount else { throw DeviceSyncManifestError.invalidPageByteCount }
        try handle.write(contentsOf: data)
        count += Int64(data.count)
    }

    public func finish() throws {
        try handle.synchronize()
        try handle.close()
        guard count == page.byteCount else { throw DeviceSyncManifestError.invalidPageByteCount }
        try TranslationFileStore.validateFile(temporary, page: page)
        if FileManager.default.fileExists(atPath: target.path) {
            try TranslationFileStore.validateFile(target, page: page)
        } else {
            try FileManager.default.moveItem(at: temporary, to: target)
        }
    }
}
