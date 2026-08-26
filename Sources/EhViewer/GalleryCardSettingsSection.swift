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

struct GalleryCardSettingsSection: View {
    @Environment(AppModel.self) private var model
    let isCompactWidth: Bool

    var body: some View {
        @Bindable var model = model
        Section("漫画卡片") {
            Toggle("作者", isOn: $model.readingSettings.galleryCard.showsAuthor)
                .accessibilityIdentifier("gallery-card-show-author-toggle")
            Toggle("普通标签", isOn: $model.readingSettings.galleryCard.showsOrdinaryTags)
                .accessibilityIdentifier("gallery-card-show-ordinary-tags-toggle")
            Toggle("彩色标签", isOn: $model.readingSettings.galleryCard.showsCategoryBadge)
                .accessibilityIdentifier("gallery-card-show-category-badge-toggle")
            Toggle("语言", isOn: $model.readingSettings.galleryCard.showsLanguage)
                .accessibilityIdentifier("gallery-card-show-language-toggle")
            Toggle("页数", isOn: $model.readingSettings.galleryCard.showsPageCount)
                .accessibilityIdentifier("gallery-card-show-page-count-toggle")
            Toggle("日期", isOn: $model.readingSettings.galleryCard.showsPostedAt)
                .accessibilityIdentifier("gallery-card-show-posted-at-toggle")
            Picker("日期显示方式", selection: $model.readingSettings.galleryCard.dateDisplayStyle) {
                ForEach(GalleryDateDisplayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .disabled(model.readingSettings.galleryCard.showsPostedAt == false)
            .accessibilityIdentifier("gallery-card-date-display-style-picker")
            Toggle("评分", isOn: $model.readingSettings.galleryCard.showsRating)
                .accessibilityIdentifier("gallery-card-show-rating-toggle")
            Picker("评分显示方式", selection: $model.readingSettings.galleryCard.ratingDisplayStyle) {
                ForEach(GalleryRatingDisplayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .disabled(model.readingSettings.galleryCard.showsRating == false)
            .accessibilityIdentifier("gallery-card-rating-display-style-picker")
            if isCompactWidth {
                Text("窄屏时，普通标签与可视化五星评分不能同时显示。开启五星评分会隐藏普通标签；重新开启普通标签会将评分显示改为数字。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("gallery-card-compact-conflict-note")
            }
        }
        .onChange(of: model.readingSettings.galleryCard) { previous, updated in
            resolveAndPersist(previous: previous, updated: updated)
        }
        .onChange(of: isCompactWidth) { _, isCompactWidth in
            guard isCompactWidth else { return }
            let current = model.readingSettings.galleryCard
            resolveAndPersist(previous: current, updated: current)
        }
    }

    private func resolveAndPersist(
        previous: GalleryCardDisplaySettings,
        updated: GalleryCardDisplaySettings
    ) {
        let resolved = GalleryCardDisplaySettings.resolving(
            previous: previous,
            updated: updated,
            isCompactWidth: isCompactWidth
        )
        if resolved != updated {
            model.readingSettings.galleryCard = resolved
        }
        model.persistReadingSettings()
    }
}
