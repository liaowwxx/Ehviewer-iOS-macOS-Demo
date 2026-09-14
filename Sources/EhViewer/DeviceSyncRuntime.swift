/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

#if os(iOS)
import EHDeviceSync

@MainActor
final class DeviceSyncRuntime {
    private let backgroundTask: DeviceSyncBackgroundTaskController

    init(coordinator: DeviceSyncCoordinator) {
        backgroundTask = DeviceSyncBackgroundTaskController(coordinator: coordinator)
    }

    func prepareForUserInitiatedSync() -> Bool {
        backgroundTask.prepareForUserInitiatedSync()
    }

    func shutdown() {
        backgroundTask.shutdown()
    }
}
#endif
