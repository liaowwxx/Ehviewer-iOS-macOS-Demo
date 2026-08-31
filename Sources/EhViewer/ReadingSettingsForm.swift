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

/// The persistent counterpart of the reader's compact options menu. Both
/// surfaces bind to `AppModel.readingSettings`, so a change is immediate in an
/// open reader and is retained for future reading sessions.
struct ReadingSettingsForm: View {
    @Environment(AppModel.self) private var model
    @State private var showingProgressResetConfirmation = false

    var body: some View {
        @Bindable var model = model

        Form {
            Section("阅读") {
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

#if os(iOS)
            Section("显示") {
                Picker("屏幕旋转", selection: $model.readingSettings.screenRotation) {
                    ForEach(ReaderScreenRotation.allCases) { rotation in
                        Text(rotation.title).tag(rotation)
                    }
                }
            }

            Section("控制") {
                Toggle("音量键翻页", isOn: $model.readingSettings.volumePage)
                Toggle("反转音量键方向", isOn: $model.readingSettings.reverseVolumePage)
                    .disabled(model.readingSettings.volumePage == false)
            }
#endif

            Section("阅读进度") {
                Button("重置下载内容的阅读进度", role: .destructive) {
                    showingProgressResetConfirmation = true
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("reset-download-reading-progress-action")
                .confirmationDialog(
                    "重置所有下载内容的阅读进度？",
                    isPresented: $showingProgressResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("重置进度", role: .destructive) {
                        Task { await model.resetAllDownloadReadingProgress() }
                    }
                    Button("取消", role: .cancel) {}
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("阅读设置")
        .onChange(of: model.readingSettings) { _, _ in
            model.persistReadingSettings()
        }
    }
}
