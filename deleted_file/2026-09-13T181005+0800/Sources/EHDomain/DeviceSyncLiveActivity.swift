/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

public enum DeviceSyncActivityPhase: String, Codable, Hashable, Sendable {
    case connecting
    case waitingForConfirmation
    case generatingManifest
    case sending
    case receiving
    case verifying
    case committing
    case comparingResults
    case completed
    case cancelled
    case interrupted
    case failed
}

public enum DeviceSyncActivityDirection: String, Codable, Hashable, Sendable {
    case sending
    case receiving
}

public struct DeviceSyncActivityContentState: Codable, Hashable, Sendable {
    public let phase: DeviceSyncActivityPhase
    public let direction: DeviceSyncActivityDirection?
    public let remoteDeviceName: String
    public let completedGalleries: Int
    public let totalGalleries: Int
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let currentGalleryTitle: String?
    public let currentPageIndex: Int?
    public let estimatedRemainingSeconds: TimeInterval?
    public let transportDescription: String?
    public let message: String?

    public init(
        phase: DeviceSyncActivityPhase,
        direction: DeviceSyncActivityDirection? = nil,
        remoteDeviceName: String,
        completedGalleries: Int = 0,
        totalGalleries: Int = 0,
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        currentGalleryTitle: String? = nil,
        currentPageIndex: Int? = nil,
        estimatedRemainingSeconds: TimeInterval? = nil,
        transportDescription: String? = nil,
        message: String? = nil
    ) {
        self.phase = phase
        self.direction = direction
        self.remoteDeviceName = remoteDeviceName
        self.completedGalleries = max(0, completedGalleries)
        self.totalGalleries = max(0, totalGalleries)
        self.completedBytes = max(0, completedBytes)
        self.totalBytes = max(0, totalBytes)
        self.currentGalleryTitle = currentGalleryTitle
        self.currentPageIndex = currentPageIndex
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
        self.transportDescription = transportDescription
        self.message = message
    }

    public var fraction: Double? {
        guard totalBytes > 0 else {
            guard totalGalleries > 0 else { return nil }
            return min(1, max(0, Double(completedGalleries) / Double(totalGalleries)))
        }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

#if os(iOS)
import ActivityKit

@available(iOS 26.0, *)
public struct DeviceSyncLiveActivityAttributes: ActivityAttributes, Hashable, Sendable {
    public typealias ContentState = DeviceSyncActivityContentState

    public let localDeviceName: String

    public init(localDeviceName: String) {
        self.localDeviceName = localDeviceName
    }
}
#endif
