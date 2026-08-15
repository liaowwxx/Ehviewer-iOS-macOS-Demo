import Foundation
import ImageIO
import EHDomain

public enum DownloadMediaKind: Sendable {
    case image
    case video
}

public enum DownloadMediaValidator {
    public static func kind(of data: Data) -> DownloadMediaKind? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 0 {
            return .image
        }
        return hasSupportedVideoSignature(data) ? .video : nil
    }

    public static func validate(_ data: Data) throws {
        guard kind(of: data) != nil else {
            throw EHError.parsingFailed("下载结果不是有效图片或视频")
        }
    }

    private static func hasSupportedVideoSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        guard bytes.count >= 4 else { return false }

        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 {
            return true
        }
        if bytes[0...3].elementsEqual([0x1A, 0x45, 0xDF, 0xA3]) {
            return true
        }
        return bytes[0...3].elementsEqual([0x00, 0x00, 0x01, 0xBA])
    }
}
