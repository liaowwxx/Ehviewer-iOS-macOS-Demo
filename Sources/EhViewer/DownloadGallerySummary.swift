/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import EHDomain
import EHDownloads

enum DownloadGallerySummary {
    static func resolve(job: DownloadJob, cached: GallerySummary?) -> GallerySummary {
        guard var summary = cached else {
            return GallerySummary(
                key: job.key, title: job.title, japaneseTitle: job.japaneseTitle,
                pageCount: job.pages.isEmpty ? nil : job.pages.count, tags: job.tags
            )
        }
        let completeness = summary.metadataCompleteness
        if completeness?.title == .notLoaded, job.title.isEmpty == false { summary.title = job.title }
        if completeness?.japaneseTitle == .notLoaded, summary.japaneseTitle == nil { summary.japaneseTitle = job.japaneseTitle }
        if completeness?.tags == .notLoaded, summary.tags.isEmpty { summary.tags = job.tags }
        if completeness?.pageCount == .notLoaded, summary.pageCount == nil, job.pages.isEmpty == false { summary.pageCount = job.pages.count }
        return summary
    }
}
