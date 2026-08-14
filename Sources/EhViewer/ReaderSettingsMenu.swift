import SwiftUI

struct ReaderSettingsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Menu("阅读选项", systemImage: "ellipsis.circle") {
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
                Picker("页面缩放", selection: $model.readingSettings.pageScaling) {
                    ForEach(ReaderPageScaling.allCases) { scaling in
                        Text(scaling.title).tag(scaling)
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
                Toggle("阅读时保持屏幕常亮", isOn: $model.readingSettings.keepScreenOn)
                Toggle("显示时钟", isOn: $model.readingSettings.showClock)
                Toggle("显示阅读进度", isOn: $model.readingSettings.showProgress)
#if os(iOS)
                Toggle("显示电量", isOn: $model.readingSettings.showBattery)
#endif
                Toggle("显示页码", isOn: $model.readingSettings.showPageInterval)
                Toggle("进入阅读器时全屏", isOn: $model.readingSettings.fullscreen)
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
