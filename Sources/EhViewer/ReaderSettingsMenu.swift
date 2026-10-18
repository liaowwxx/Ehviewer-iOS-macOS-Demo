/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import EHDomain

struct ReaderSettingsMenu: View {
    @Environment(AppModel.self) private var model
    let key: GalleryKey
    @Binding var edition: ReadingEdition

    var body: some View {
        @Bindable var model = model

        Menu("阅读选项", systemImage: "ellipsis.circle") {
            Section("阅读") {
                if edition != .original || !(model.translationLibrary.versions[key] ?? []).isEmpty {
                    Picker("阅读版本", selection: $edition) {
                        Text("原件").tag(ReadingEdition.original)
                        ForEach(model.translationLibrary.versions[key] ?? []) { version in
                            Text("译件 · \(version.targetLanguage) · \(Date(timeIntervalSince1970: version.createdAt).formatted(date: .numeric, time: .shortened))")
                                .tag(ReadingEdition.translated(versionID: version.versionID))
                        }
                    }
                    .accessibilityIdentifier("reader-edition-picker")
                }
                Picker("阅读模式", selection: $model.readingSettings.readingMode) {
                    ForEach(ReadingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if model.readingSettings.readingMode == .paged {
                    Picker("翻页方向", selection: $model.readingSettings.readingDirection) {
                        ForEach(ReadingDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                }
                Picker("开始位置", selection: $model.readingSettings.startPosition) {
                    ForEach(ReaderStartPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
            }

            Section("显示") {
#if os(iOS)
                Picker("屏幕旋转", selection: $model.readingSettings.screenRotation) {
                    ForEach(ReaderScreenRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
#endif
            }

#if os(iOS)
            Section("控制") {
                Toggle("音量键翻页", isOn: $model.readingSettings.volumePage)
                Toggle("反转音量键方向", isOn: $model.readingSettings.reverseVolumePage)
                    .disabled(model.readingSettings.volumePage == false)
            }
#endif
        }
        .accessibilityIdentifier("reader-settings-menu")
    }
}
