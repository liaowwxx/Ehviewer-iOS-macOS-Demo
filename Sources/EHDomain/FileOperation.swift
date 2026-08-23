/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

public enum FileOperationPhase: String, Codable, Hashable, Sendable {
    case staging
    case inspecting
    case extracting
    case validating
    case committing
    case exporting
    case saving
}

public struct FileOperationProgress: Codable, Hashable, Sendable {
    public let phase: FileOperationPhase
    public let completedBytes: Int64
    public let totalBytes: Int64?
    public let completedItems: Int
    public let totalItems: Int?
    public let currentItem: String?

    public init(
        phase: FileOperationPhase,
        completedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        completedItems: Int = 0,
        totalItems: Int? = nil,
        currentItem: String? = nil
    ) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedItems = completedItems
        self.totalItems = totalItems
        self.currentItem = currentItem
    }

    public var fraction: Double? {
        if let totalBytes, totalBytes > 0 {
            return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
        }
        if let totalItems, totalItems > 0 {
            return min(1, max(0, Double(completedItems) / Double(totalItems)))
        }
        return nil
    }
}

public struct FileOperationIssue: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let galleryKey: GalleryKey?
    public let pageIndex: Int?
    public let phase: FileOperationPhase
    public let message: String

    public init(
        id: UUID = UUID(),
        galleryKey: GalleryKey? = nil,
        pageIndex: Int? = nil,
        phase: FileOperationPhase,
        message: String
    ) {
        self.id = id
        self.galleryKey = galleryKey
        self.pageIndex = pageIndex
        self.phase = phase
        self.message = message
    }
}

public enum FileOperationOutcome: Codable, Hashable, Sendable {
    case completed(completedItems: Int, issues: [FileOperationIssue])
    case partial(completedItems: Int, issues: [FileOperationIssue])
    case cancelled(completedItems: Int, issues: [FileOperationIssue])
    case failed(FileOperationIssue)
}
