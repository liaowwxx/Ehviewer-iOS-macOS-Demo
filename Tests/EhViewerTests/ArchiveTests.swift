import Foundation
import Testing
import EHDomain
import EHDownloads

struct ArchiveTests {
    @Test("Local archive reader lists and extracts a ZIP entry")
    func zipRoundTrip() throws {
        let payload = Data("archive fixture".utf8)
        let fileName = "001.jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }

        try makeStoredZip(entries: [(fileName, payload)]).write(to: url, options: .atomic)
        let document = try LocalArchiveReader.open(url)
        #expect(document.format == .zip)
        #expect(document.imageEntries.map(\.path) == [fileName])
        let entry = try #require(document.imageEntries.first)
        #expect(try LocalArchiveReader.readData(for: entry, in: document) == payload)
    }

    @Test("Legacy download backup inspector reads VERSION2 metadata and imports numbered images")
    func legacyDownloadBackupRoundTrip() async throws {
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let spiderInfo = Data("VERSION2\n00000000\n123\ntoken-123\n1\n1\n20\n2\n0 page-token-1\n1 page-token-2\n".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-legacy-\(UUID().uuidString).zip")
        let downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-imported-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: downloadRoot)
        }

        try makeStoredZip(entries: [
            ("backup/data/settings.db", Data("ignored".utf8)),
            ("backup/download/123-title/.ehviewer", spiderInfo),
            ("backup/download/123-title/00000001.png", imageData),
            ("backup/download/123-title/00000002.jpg", imageData),
            ("backup/download/123-title/cover.jpg", imageData),
            ("../download/999-unsafe/.ehviewer", spiderInfo)
        ]).write(to: url, options: .atomic)

        let inspection = try await LegacyDownloadArchive.inspect(url)
        let candidate = try #require(inspection.candidates.first)
        #expect(inspection.candidates.count == 1)
        #expect(candidate.key == GalleryKey(gid: 123, token: "token-123"))
        #expect(candidate.declaredPageCount == 2)
        #expect(candidate.pageTokens == [0: "page-token-1", 1: "page-token-2"])
        #expect(candidate.images.map(\.pageIndex) == [0, 1])

        let selections = candidate.images.map {
            LegacyDownloadPageSelection(
                archivePath: $0.archivePath,
                key: candidate.key,
                pageIndex: $0.pageIndex
            )
        }
        let extraction = try await LegacyDownloadArchive.extractPages(from: url, selections: selections)
        defer { try? FileManager.default.removeItem(at: extraction.temporaryDirectory) }
        #expect(extraction.failedPageCount == 0)
        #expect(extraction.pages.count == 2)

        let store = DownloadFileStore(root: downloadRoot, minimumFreeBytes: 1)
        for page in extraction.pages {
            _ = try await store.importFile(at: page.fileURL, for: page.key, pageIndex: page.pageIndex)
        }
        #expect(try await store.data(for: candidate.key, pageIndex: 0) == imageData)
        #expect(try await store.data(for: candidate.key, pageIndex: 1) == imageData)
    }

    @Test("Legacy download backup inspector accepts unversioned VERSION1 metadata")
    func legacyVersionOneSpiderInfo() async throws {
        let spiderInfo = Data("00000000\n321\nlegacy-token\n1\n1\n20\n1\n".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-legacy-v1-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try makeStoredZip(entries: [
            ("download/321-title/.ehviewer", spiderInfo)
        ]).write(to: url, options: .atomic)

        let inspection = try await LegacyDownloadArchive.inspect(url)
        let candidate = try #require(inspection.candidates.first)
        #expect(candidate.key == GalleryKey(gid: 321, token: "legacy-token"))
        #expect(candidate.declaredPageCount == 1)
    }

    @Test("Download archive exporter writes a restorable mixed-media backup with progress")
    func downloadArchiveExportRoundTrip() async throws {
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let videoData = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x70, 0x34, 0x32])
        let key = GalleryKey(gid: 654, token: "archive-token")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-export-source-\(UUID().uuidString)")
        let importedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-export-destination-\(UUID().uuidString)")
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-export-\(UUID().uuidString).zip")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: importedRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }

        let store = DownloadFileStore(root: root, minimumFreeBytes: 1)
        _ = try await store.write(imageData, for: key, pageIndex: 0)
        _ = try await store.write(videoData, for: key, pageIndex: 1)
        let item = DownloadArchiveExportItem(
            key: key,
            title: "导出/测试画廊",
            totalPageCount: 2,
            pageTokens: [0: "page-token"]
        )
        let progress = ProgressProbe()
        let result = try await DownloadArchiveExporter.export(
            items: [item],
            files: store,
            to: archiveURL
        ) { update in
            await progress.record(update)
        }

        #expect(result.completedFiles == 2)
        #expect(await progress.isMonotonic)
        #expect(await progress.values.last == 1)

        let inspection = try await LegacyDownloadArchive.inspect(archiveURL)
        let candidate = try #require(inspection.candidates.first)
        #expect(candidate.key == key)
        #expect(candidate.declaredPageCount == 2)
        #expect(candidate.images.map(\.pageIndex) == [0, 1])
        #expect(candidate.pageTokens == [0: "page-token"])
        #expect(candidate.images.contains { $0.archivePath.hasSuffix("00000002.mp4") })

        let selections = candidate.images.map {
            LegacyDownloadPageSelection(archivePath: $0.archivePath, key: key, pageIndex: $0.pageIndex)
        }
        let extraction = try await LegacyDownloadArchive.extractPages(from: archiveURL, selections: selections)
        defer { try? FileManager.default.removeItem(at: extraction.temporaryDirectory) }
        let importedStore = DownloadFileStore(root: importedRoot, minimumFreeBytes: 1)
        for page in extraction.pages {
            _ = try await importedStore.importFile(at: page.fileURL, for: page.key, pageIndex: page.pageIndex)
        }
        #expect(try await importedStore.data(for: key, pageIndex: 0) == imageData)
        #expect(try await importedStore.data(for: key, pageIndex: 1) == videoData)
    }

    private func makeStoredZip(entries: [(String, Data)]) -> Data {
        var zip = Data()
        var records: [(name: Data, payload: Data, crc: UInt32, offset: UInt32)] = []
        for (fileName, payload) in entries {
            let name = Data(fileName.utf8)
            let crc = crc32(payload)
            let offset = UInt32(zip.count)
            zip.appendLE(UInt32(0x04034b50))
            zip.appendLE(UInt16(20))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(crc)
            zip.appendLE(UInt32(payload.count))
            zip.appendLE(UInt32(payload.count))
            zip.appendLE(UInt16(name.count))
            zip.appendLE(UInt16(0))
            zip.append(name)
            zip.append(payload)
            records.append((name, payload, crc, offset))
        }

        let centralDirectoryOffset = UInt32(zip.count)
        for record in records {
            zip.appendLE(UInt32(0x02014b50))
            zip.appendLE(UInt16(20))
            zip.appendLE(UInt16(20))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(record.crc)
            zip.appendLE(UInt32(record.payload.count))
            zip.appendLE(UInt32(record.payload.count))
            zip.appendLE(UInt16(record.name.count))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt16(0))
            zip.appendLE(UInt32(0))
            zip.appendLE(record.offset)
            zip.append(record.name)
        }

        let centralDirectorySize = UInt32(zip.count) - centralDirectoryOffset
        zip.appendLE(UInt32(0x06054b50))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(records.count))
        zip.appendLE(UInt16(records.count))
        zip.appendLE(centralDirectorySize)
        zip.appendLE(centralDirectoryOffset)
        zip.appendLE(UInt16(0))
        return zip
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private actor ProgressProbe {
    private(set) var values: [Double] = []

    var isMonotonic: Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }

    func record(_ progress: DownloadArchiveExportProgress) {
        values.append(progress.fraction)
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
