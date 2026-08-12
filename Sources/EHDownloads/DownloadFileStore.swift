import Foundation
import ImageIO
import EHDomain

public actor DownloadFileStore {
    private let root: URL
    private let minimumFreeBytes: Int64

    public init(root: URL? = nil, minimumFreeBytes: Int64 = 1_024 * 1_024 * 1_024) {
        var resolvedRoot = root ?? Self.defaultRoot
        self.root = resolvedRoot
        self.minimumFreeBytes = minimumFreeBytes
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resolvedRoot.setResourceValues(values)
    }

    public func finalURL(for key: GalleryKey, pageIndex: Int) -> URL {
        directory(for: key).appendingPathComponent("page-\(pageIndex + 1).bin")
    }

    public func contains(_ key: GalleryKey, pageIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: finalURL(for: key, pageIndex: pageIndex).path)
    }

    public func readablePageIndexes(for key: GalleryKey, pageIndexes: [Int]) -> Set<Int> {
        Set(pageIndexes.filter { pageIndex in
            let url = finalURL(for: key, pageIndex: pageIndex)
            guard FileManager.default.fileExists(atPath: url.path),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
            return CGImageSourceGetCount(source) > 0
        })
    }

    public func data(for key: GalleryKey, pageIndex: Int) throws -> Data {
        do {
            return try Data(contentsOf: finalURL(for: key, pageIndex: pageIndex), options: .mappedIfSafe)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public func write(_ data: Data, for key: GalleryKey, pageIndex: Int) throws -> URL {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw EHError.parsingFailed("下载结果不是有效图片")
        }
        if let available = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < minimumFreeBytes {
            throw EHError.diskSpaceLow
        }

        var directory = directory(for: key)
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directory.setResourceValues(directoryValues)

            let finalURL = finalURL(for: key, pageIndex: pageIndex)
            let partialURL = finalURL.appendingPathExtension("part")
            try data.write(to: partialURL, options: .atomic)
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partialURL, to: finalURL)
            return finalURL
        } catch let error as EHError {
            throw error
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    public func remove(_ key: GalleryKey) throws {
        let directory = directory(for: key)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            throw EHError.storageFailed(error.localizedDescription)
        }
    }

    private func directory(for key: GalleryKey) -> URL {
        let encoded = Data(key.id.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return root.appendingPathComponent(encoded, isDirectory: true)
    }

    private static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/Downloads", isDirectory: true)
    }
}
