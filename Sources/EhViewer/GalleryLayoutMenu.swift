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

struct GalleryLayoutMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.readingSettings.galleryCard.layoutMode
        Button(current.next.title, systemImage: current.next.systemImage) {
            model.readingSettings.galleryCard.layoutMode = current.next
            model.persistReadingSettings()
        }
        .labelStyle(.titleAndIcon)
        .accessibilityValue(current.title)
        .accessibilityHint("切换到\(current.next.title)")
        .accessibilityIdentifier("gallery-layout-menu")
    }
}
