/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

#if os(iOS)
@preconcurrency import BackgroundTasks
import EHDeviceSync
import Foundation
import Observation
import OSLog

private let deviceSyncBackgroundLogger = Logger(
    subsystem: "com.liao.ehviewer",
    category: "device-sync-background"
)

@MainActor
final class DeviceSyncBackgroundTaskRegistry {
    static let shared = DeviceSyncBackgroundTaskRegistry()

    private var isRegistered = false
    private weak var controller: DeviceSyncBackgroundTaskController?
    private var pendingTask: BGContinuedProcessingTask?

    private init() {}

    @discardableResult
    func register() -> Bool {
        guard isRegistered == false else { return true }
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DeviceSyncBackgroundTaskController.identifier,
            using: DispatchQueue.main
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            DeviceSyncBackgroundTaskRegistry.shared.receive(task)
        }
        guard registered else {
            deviceSyncBackgroundLogger.error("Unable to register continued device sync task handler")
            return false
        }
        isRegistered = true
        return true
    }

    func bind(_ controller: DeviceSyncBackgroundTaskController) {
        self.controller = controller
        if let pendingTask {
            self.pendingTask = nil
            controller.handle(pendingTask)
        }
    }

    private func receive(_ task: BGContinuedProcessingTask) {
        if let controller {
            controller.handle(task)
        } else {
            pendingTask = task
        }
    }
}

@MainActor
final class DeviceSyncBackgroundTaskController {
    /// BGContinuedProcessingTask supplies the app's sole Live Activity UI.
    static let identifier = "com.liao.ehviewer.device-sync.continued-processing"

    private weak var coordinator: DeviceSyncCoordinator?
    private var submittedIdentifier: String?
    private var task: BGContinuedProcessingTask?

    init(coordinator: DeviceSyncCoordinator) {
        self.coordinator = coordinator
        DeviceSyncBackgroundTaskRegistry.shared.bind(self)
        observe(coordinator)
    }

    func prepareForUserInitiatedSync() -> Bool {
        guard task == nil, submittedIdentifier == nil else { return true }
        guard DeviceSyncBackgroundTaskRegistry.shared.register() else {
            return false
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier,
            title: "正在同步 EhViewer 数据",
            subtitle: "同步会在锁屏或进入后台后继续"
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            submittedIdentifier = Self.identifier
            return true
        } catch {
            deviceSyncBackgroundLogger.error(
                "Unable to submit continued device sync task: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func handle(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleExpiration()
            }
        }
        updateTaskProgress()
        handleState(coordinator?.state)
    }

    func shutdown() {
        if let submittedIdentifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submittedIdentifier)
        }
        submittedIdentifier = nil
        task?.setTaskCompleted(success: false)
        task = nil
    }

    private func observe(_ coordinator: DeviceSyncCoordinator) {
        withObservationTracking {
            _ = coordinator.state
            _ = coordinator.remoteDeviceName
            _ = coordinator.transportDescription
            _ = coordinator.transportInfo
        } onChange: { [weak self, weak coordinator] in
            Task { @MainActor [weak self, weak coordinator] in
                guard let self, let coordinator else { return }
                self.updateTaskProgress()
                self.handleState(coordinator.state)
                self.observe(coordinator)
            }
        }
    }

    private func handleState(_ state: DeviceSyncState?) {
        guard let state else { return }
        switch state {
        case .completed:
            finish(success: true)
        case .cancelled, .interrupted, .failed:
            finish(success: false)
        default:
            break
        }
    }

    private func handleExpiration() {
        guard task != nil else { return }
        deviceSyncBackgroundLogger.error("Continued device sync task expired")
        coordinator?.interruptForBackground()
        finish(success: false)
    }

    private func finish(success: Bool) {
        if let task {
            self.task = nil
            task.setTaskCompleted(success: success)
        }
        if let submittedIdentifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: submittedIdentifier)
            self.submittedIdentifier = nil
        }
    }

    private func updateTaskProgress() {
        guard let task, let state = coordinator?.state else { return }
        let presentation = makePresentation(for: state)
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = Int64(presentation.fraction * 100)
        task.updateTitle(presentation.title, subtitle: presentation.subtitle)
    }

    private struct TaskPresentation {
        let title: String
        let subtitle: String
        let fraction: Double
    }

    private func makePresentation(for state: DeviceSyncState) -> TaskPresentation {
        guard let coordinator else {
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "同步状态不可用",
                fraction: 0
            )
        }

        switch state {
        case .connecting:
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "正在连接 \(coordinator.remoteDeviceName)",
                fraction: 0
            )
        case .awaitingRemoteConfirmation:
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "等待 \(coordinator.remoteDeviceName) 确认",
                fraction: 0
            )
        case .awaitingConnectionConfirmation:
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "等待 \(coordinator.remoteDeviceName) 确认连接",
                fraction: 0
            )
        case .preparing(let phase):
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: phaseTitle(phase),
                fraction: 0
            )
        case .awaitingSyncConfirmation(let preview):
            let galleryCount = preview.sendGalleryCount + preview.receiveGalleryCount
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: galleryCount > 0 ? "待同步 \(galleryCount) 个画廊" : "没有需要同步的内容",
                fraction: 0
            )
        case .syncing(let progress):
            let fraction = min(1, max(0, progress.fraction ?? 0))
            let percent = Int((fraction * 100).rounded())
            let direction: String
            switch progress.direction {
            case .sending: direction = "发送"
            case .receiving: direction = "接收"
            case nil: direction = "处理"
            }
            let detail: String
            if let currentGalleryTitle = progress.currentGalleryTitle,
               currentGalleryTitle.isEmpty == false {
                detail = compactTitle(currentGalleryTitle)
            } else {
                detail = coordinator.remoteDeviceName
            }
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "\(direction) · \(percent)% · \(detail)",
                fraction: fraction
            )
        case .completed:
            return TaskPresentation(
                title: "同步已完成",
                subtitle: coordinator.remoteDeviceName,
                fraction: 1
            )
        case .cancelled:
            return TaskPresentation(
                title: "同步已取消",
                subtitle: coordinator.remoteDeviceName,
                fraction: 0
            )
        case .interrupted:
            return TaskPresentation(
                title: "同步已中断",
                subtitle: coordinator.remoteDeviceName,
                fraction: 0
            )
        case .failed(let message):
            return TaskPresentation(
                title: "同步失败",
                subtitle: compactTitle(message),
                fraction: 0
            )
        case .idle, .indexRequired, .discovering, .awaitingPairingCode:
            return TaskPresentation(
                title: "同步 EhViewer 数据",
                subtitle: "正在准备设备同步",
                fraction: 0
            )
        }
    }

    private func phaseTitle(_ phase: DeviceSyncPhase) -> String {
        switch phase {
        case .generatingManifest: "正在生成同步清单"
        case .waitingForConfirmation: "等待双方确认"
        case .sending: "准备发送数据"
        case .receiving: "准备接收数据"
        case .committing: "正在提交同步结果"
        case .comparingResults: "正在再次比对结果"
        }
    }

    private func compactTitle(_ title: String) -> String {
        let limit = 36
        guard title.count > limit else { return title }
        return String(title.prefix(limit - 1)) + "…"
    }
}
#endif
