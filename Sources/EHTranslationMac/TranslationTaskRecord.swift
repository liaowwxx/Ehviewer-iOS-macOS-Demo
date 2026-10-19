#if os(macOS)
import Foundation
import EHDomain

public struct TranslationInput: Codable, Sendable {
    public struct Page: Codable, Sendable {
        public let index: Int
        public let fileName: String
        public let byteCount: Int64
        public let sha256: String
    }
    public let formatVersion: Int
    public let requestID: String
    public let gallery: GalleryTranslationManifest.Gallery
    public let pageCount: Int
    public let pages: [Page]
}

public struct TranslationTaskRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let input: TranslationInput
    public let created: Date
    public var state: String
    public var completedPages: Int = 0
    public var targetLanguage = ""
    public var error: String?
    public var isActive: Bool { ["accepted", "preparing", "running", "rendering"].contains(state) }
    public var canStart: Bool { state == "queued" }
    public var canRetry: Bool { ["failed", "cancelled", "interrupted", "delivered"].contains(state) }
    public var stateTitle: String {
        switch state {
        case "queued": "等待开始"
        case "accepted": "排队中"
        case "preparing": "准备中"
        case "running": "翻译中"
        case "rendering": "生成译图"
        case "awaitingImport": "等待导入"
        case "delivered": "已保存译本"
        case "cancelled": "已取消"
        case "interrupted": "已中断"
        default: "失败"
        }
    }
}
#endif
