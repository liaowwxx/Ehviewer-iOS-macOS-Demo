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
import EHDomain

struct GalleryCardSettingsPreview: View {
    @Environment(AppModel.self) private var model
    let isCompactWidth: Bool

    private var gallery: GallerySummary {
        GallerySummary(
            key: GalleryKey(gid: 0, token: "settings-preview"),
            title: String(localized: "示例漫画"),
            japaneseTitle: "サンプル漫画",
            category: GalleryCategory.manga.rawValue,
            pageCount: 42,
            postedAt: .now.addingTimeInterval(-86_400),
            rating: 4.5,
            tags: ["artist:sample", "female:glasses", "language:chinese"]
        )
    }

    var body: some View {
        let settings = model.readingSettings.galleryCard
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("实时预览", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(settings.layoutMode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GalleryCard(
                gallery: gallery,
                displaySettings: settings,
                isCompactWidth: isCompactWidth,
                showsBackground: false
            )
            .frame(maxWidth: settings.layoutMode == .list ? 480 : 210)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("gallery-card-settings-preview")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}
