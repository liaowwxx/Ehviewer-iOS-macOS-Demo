/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import EHDownloads

/// The deliberately compact download state shown on remote gallery cards.
/// Detailed paused and failed states remain available in the download manager.
enum GalleryCardDownloadStatus: Hashable, Sendable {
    case notDownloaded
    case downloading
    case downloaded

    init(job: DownloadJob?) {
        guard let job else {
            self = .notDownloaded
            return
        }
        self = job.state == .completed ? .downloaded : .downloading
    }

    var title: String {
        switch self {
        case .notDownloaded: String(localized: "未下载")
        case .downloading: String(localized: "下载中")
        case .downloaded: String(localized: "已下载")
        }
    }

    var systemImage: String {
        switch self {
        case .notDownloaded: "arrow.down.circle"
        case .downloading: "arrow.down.circle.fill"
        case .downloaded: "checkmark.circle.fill"
        }
    }
}

struct GalleryCardDownloadStatusBadge: View {
    let status: GalleryCardDownloadStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(0.25))
            }
            .accessibilityHidden(true)
    }
}
