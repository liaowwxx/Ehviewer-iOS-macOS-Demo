# Archived files

- Archived at: 2026-08-17T00:30:55+08:00
  - Original path: `Sources/EHPersistence/MigrationSnapshot.swift`
  - Archived path: `deleted_file/2026-08-17T003055+0800/Sources/EHPersistence/MigrationSnapshot.swift`
  - Source/use: legacy broad JSON migration schema for galleries, local state, downloads, searches, filters, settings, and tag translations.
  - Reason: replaced by the metadata-only `.ehgallery` synchronization format at the user's request; retaining this implementation risks accidentally restoring the old full-state import path.
  - SHA-256 before archive: `98563ceb8fb0b2edda66fc5b396e7526093ad6311ee664c9424e3a1a8b2ece1c`
  - Restore: move the archived file back to its original relative path and restore the deprecated `PersistenceStore` APIs/tests if full-state migration is deliberately reintroduced.

- Archived at: 2026-08-29T17:07:25+08:00
  - Original path: `Sources/EhViewer/Resources/HELP.md`
  - Archived path: `deleted_file/2026-08-29T170725+0800/Sources/EhViewer/Resources/HELP.md`
  - Source/use: duplicate bundled usage guide left after consolidating app documentation resources under `Sources/EhViewer/Resources/Documentation/`.
  - Reason: consolidate the app's Markdown documentation into one editable resource directory at the user's request; the file content is retained in the new `Documentation/HELP.md` and this archive.
  - SHA-256 before archive: `b4ed855399c95b8350bb93be7e6bbc9904bb901c59461d82b495baa38d33a678`
  - Restore: move the archived file back to `Sources/EhViewer/Resources/HELP.md` and update the app resource reference if the legacy flat resource layout is deliberately restored.

- Archived at: 2026-09-13T18:10:05+08:00
  - Original paths: `Sources/EHDomain/DeviceSyncLiveActivity.swift`, `Sources/EhViewer/DeviceSyncLiveActivityController.swift`, `Sources/EhViewerLiveActivity/DeviceSyncLiveActivityWidget.swift`, `Sources/EhViewerLiveActivity/Info.plist`, and `Tests/EhViewerTests/DeviceSyncLiveActivityTests.swift`
  - Archived paths: `deleted_file/2026-09-13T181005+0800/Sources/EHDomain/DeviceSyncLiveActivity.swift`, `deleted_file/2026-09-13T181005+0800/Sources/EhViewer/DeviceSyncLiveActivityController.swift`, `deleted_file/2026-09-13T181005+0800/Sources/EhViewerLiveActivity/DeviceSyncLiveActivityWidget.swift`, `deleted_file/2026-09-13T181005+0800/Sources/EhViewerLiveActivity/Info.plist`, and `deleted_file/2026-09-13T181005+0800/Tests/EhViewerTests/DeviceSyncLiveActivityTests.swift`
  - Source/use: custom ActivityKit Live Activity model, controller, WidgetKit Extension, and focused tests for device synchronization.
  - Reason: the custom ActivityKit activity duplicated the system Live Activity automatically supplied by `BGContinuedProcessingTask`; retain only the system activity so the user sees one progress surface.
  - SHA-256 before archive: `Sources/EHDomain/DeviceSyncLiveActivity.swift` `722f7943f73b0ec55745a2f236cd159492abf0e36ada94221bdc239040312f90`; `Sources/EhViewer/DeviceSyncLiveActivityController.swift` `0175533c514ee1493619305bb99c016104e1db33ba450ba6fddd39d2be26cd4d`; `Sources/EhViewerLiveActivity/DeviceSyncLiveActivityWidget.swift` `d1dd50d07d572a02a0153869404756661adf6b5ec6e08188bbe956a5c7d3e682`; `Sources/EhViewerLiveActivity/Info.plist` `3be5ab7924bbcc73853b6b78f9909670051829b067183ab56929c7a9c4ca8b66`; `Tests/EhViewerTests/DeviceSyncLiveActivityTests.swift` `7eb3da84c0b840ad208ee1b24243dd15e0bb9f97558f18709a6fed9c934c809c`
  - Restore: move each archived file back to its original path, restore the WidgetKit Extension target and app embedding references in `EhViewer.xcodeproj/project.pbxproj`, restore the ActivityKit linker setting in `Package.swift`, and reconnect `DeviceSyncRuntime` to the custom controller.

## 2026-10-04T18:06:34.356370+08:00

- 原始路径：`Sources/EhViewer/SearchBackgroundInteraction.swift`
- 归档路径：`deleted_file/2026-10-04T180634+0800/Sources/EhViewer/SearchBackgroundInteraction.swift`
- 来源及用途：本轮 iPad 搜索历史滑动修复中新增的实验性 UIKit 辅助代码。
- 原因与任务背景：用户指出改动偏离范围，停止测试并撤回本轮实验性修改。
- SHA-256：`58beea22050335b9708695ff237796b4997de212e0e088288bff43e8b4a3aeec`
- 恢复方法：如需恢复，将归档文件移动回原始路径；本轮添加的 Xcode 工程引用已撤回。
