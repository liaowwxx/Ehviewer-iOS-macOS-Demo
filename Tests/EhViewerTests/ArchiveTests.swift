import Foundation
import Testing
import EHDownloads

struct ArchiveTests {
    @Test("Local archive reader lists and extracts a ZIP entry")
    func zipRoundTrip() throws {
        let payload = Data("archive fixture".utf8)
        let fileName = "001.jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }

        try makeStoredZip(fileName: fileName, payload: payload).write(to: url, options: .atomic)
        let document = try LocalArchiveReader.open(url)
        #expect(document.format == .zip)
        #expect(document.imageEntries.map(\.path) == [fileName])
        let entry = try #require(document.imageEntries.first)
        #expect(try LocalArchiveReader.readData(for: entry, in: document) == payload)
    }

    private func makeStoredZip(fileName: String, payload: Data) -> Data {
        let name = Data(fileName.utf8)
        let crc = crc32(payload)
        var zip = Data()
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

        let centralDirectoryOffset = UInt32(zip.count)
        zip.appendLE(UInt32(0x02014b50))
        zip.appendLE(UInt16(20))
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
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt32(0))
        zip.appendLE(UInt32(0))
        zip.append(name)

        let centralDirectorySize = UInt32(zip.count) - centralDirectoryOffset
        zip.appendLE(UInt32(0x06054b50))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(0))
        zip.appendLE(UInt16(1))
        zip.appendLE(UInt16(1))
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
