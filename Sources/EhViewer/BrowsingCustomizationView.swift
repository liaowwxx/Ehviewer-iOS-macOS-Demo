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

struct BrowsingCustomizationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        @Bindable var model = model
        Form {
            Section("浏览") {
                Toggle("显示日文标题", isOn: $model.readingSettings.showJapaneseTitle)
                    .onChange(of: model.readingSettings.showJapaneseTitle) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-japanese-title-toggle")
                Toggle("显示标签翻译", isOn: $model.readingSettings.showTagTranslations)
                    .onChange(of: model.readingSettings.showTagTranslations) { _, _ in
                        model.persistReadingSettings()
                    }
                    .accessibilityIdentifier("show-tag-translations-toggle")
            }
            GalleryCardSettingsSection(isCompactWidth: horizontalSizeClass == .compact)
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            GalleryCardSettingsPreview(isCompactWidth: horizontalSizeClass == .compact)
        }
        .navigationTitle("自定义")
    }
}
