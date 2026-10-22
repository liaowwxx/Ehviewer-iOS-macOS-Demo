import Foundation
import EHDomain

/// A submitted transfer survives the lifetime of the task awaiting its result.
public struct DownloadTransferTicket: Codable, Hashable, Sendable {
    public let id: UUID
    public let batchID: UUID
    public let page: GalleryPageDescriptor
    public let image: GalleryPageImage
    public let attempt: Int
    public let taskIdentifier: Int

    public init(id: UUID = UUID(), batchID: UUID, page: GalleryPageDescriptor, image: GalleryPageImage, attempt: Int = 0, taskIdentifier: Int) {
        self.id = id
        self.batchID = batchID
        self.page = page
        self.image = image
        self.attempt = attempt
        self.taskIdentifier = taskIdentifier
    }

    public var retryPage: GalleryPageDescriptor {
        guard page.requiresPageResolution, let key = image.skipHathKey,
              var components = URLComponents(url: page.pageURL, resolvingAgainstBaseURL: false) else { return page }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "nl" }
        items.append(URLQueryItem(name: "nl", value: key))
        components.queryItems = items
        guard let url = components.url else { return page }
        return GalleryPageDescriptor(galleryKey: page.galleryKey, index: page.index, pageURL: url, previewURL: page.previewURL, previewClip: page.previewClip)
    }
}

public struct DownloadTransferBatch: Sendable {
    public let id: UUID
    public let tickets: [DownloadTransferTicket]

    public init(id: UUID, tickets: [DownloadTransferTicket]) {
        self.id = id
        self.tickets = tickets
    }
}

public protocol DownloadTransferService: Sendable {
    func begin(_ job: DownloadJob) async throws -> DownloadTransferBatch
    func prepare(_ page: GalleryPageDescriptor, batchID: UUID, attempt: Int) async throws -> DownloadTransferTicket
    /// Returns only after the file has been published and progress persisted.
    func finish(_ ticket: DownloadTransferTicket) async throws
    func cancel(_ key: GalleryKey, preservingStagedFiles: Bool) async
    func setPreparationEnabled(_ enabled: Bool) async
}

public extension DownloadTransferService {
    func cancel(_ key: GalleryKey) async {
        await cancel(key, preservingStagedFiles: true)
    }
}
