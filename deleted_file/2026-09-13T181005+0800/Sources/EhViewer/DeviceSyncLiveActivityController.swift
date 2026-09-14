/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

#if os(iOS)
@preconcurrency import ActivityKit
import EHDeviceSync
import EHDomain
import Foundation
import Observation
import OSLog

private let deviceSyncActivityLogger = Logger(
    subsystem: "com.liao.ehviewer",
    category: "device-sync-live-activity"
)

@MainActor
final class DeviceSyncLiveActivityController {
    private weak var coordinator: DeviceSyncCoordinator?
    private var activity: Activity<DeviceSyncLiveActivityAttributes>?
    private var updateTask: Task<Void, Never>?

    init(coordinator: DeviceSyncCoordinator) {
        self.coordinator = coordinator
        if coordinator.hasActiveSession {
            activity = Activity<DeviceSyncLiveActivityAttributes>.activities.first
        } else if let staleActivity = Activity<DeviceSyncLiveActivityAttributes>.activities.first {
            Task { await staleActivity.end(nil, dismissalPolicy: .immediate) }
        }
        observe(coordinator)
        handle(coordinator.state)
    }

    func shutdown() {
        updateTask?.cancel()
        updateTask = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func observe(_ coordinator: DeviceSyncCoordinator) {
        withObservationTracking {
            _ = coordinator.state
            _ = coordinator.remoteDeviceName
            _ = coordinator.transportInfo
        } onChange: { [weak self, weak coordinator] in
            Task { @MainActor [weak self, weak coordinator] in
                guard let self, let coordinator else { return }
                self.handle(coordinator.state)
                self.observe(coordinator)
            }
        }
    }

    private func handle(_ state: DeviceSyncState) {
        switch state {
        case .connecting,
             .awaitingRemoteConfirmation,
             .awaitingConnectionConfirmation,
             .preparing,
             .awaitingSyncConfirmation,
             .syncing:
            if activity == nil {
                startActivity(for: state)
            }
            updateActivity(for: state)
        case .completed:
            endActivity(with: makeContentState(for: state), dismissalPolicy: .default)
            deviceSyncActivityLogger.info("Device sync live activity completed")
        case .cancelled, .interrupted, .failed:
            endActivity(with: makeContentState(for: state), dismissalPolicy: .default)
        case .idle, .indexRequired, .discovering, .awaitingPairingCode:
            break
        }
    }

    private func startActivity(for state: DeviceSyncState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            deviceSyncActivityLogger.info("Live Activities are disabled by the user")
            return
        }
        guard let coordinator else { return }
        do {
            activity = try Activity.request(
                attributes: DeviceSyncLiveActivityAttributes(
                    localDeviceName: coordinator.localDeviceName
                ),
                content: ActivityContent(
                    state: makeContentState(for: state),
                    staleDate: Date().addingTimeInterval(300)
                ),
                pushType: nil,
                style: .standard
            )
        } catch {
            deviceSyncActivityLogger.error(
                "Unable to start device sync live activity: (error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func updateActivity(for state: DeviceSyncState) {
        guard let activity else { return }
        let content = ActivityContent(
            state: makeContentState(for: state),
            staleDate: Date().addingTimeInterval(300)
        )
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self, activity] in
            await activity.update(content)
            guard let self, self.activity?.id == activity.id else { return }
            self.updateTask = nil
        }
    }

    private func endActivity(
        with state: DeviceSyncActivityContentState,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) {
        guard let activity else { return }
        updateTask?.cancel()
        updateTask = nil
        self.activity = nil
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: dismissalPolicy) }
    }

    private func makeContentState(for state: DeviceSyncState) -> DeviceSyncActivityContentState {
        guard let coordinator else {
            return DeviceSyncActivityContentState(
                phase: .failed,
                remoteDeviceName: "EhViewer",
                message: "同步状态不可用"
            )
        }

        switch state {
        case .connecting:
            return DeviceSyncActivityContentState(
                phase: .connecting,
                remoteDeviceName: coordinator.remoteDeviceName,
                transportDescription: coordinator.transportDescription,
                message: "正在建立安全连接…"
            )
        case .awaitingRemoteConfirmation, .awaitingConnectionConfirmation:
            return DeviceSyncActivityContentState(
                phase: .waitingForConfirmation,
                remoteDeviceName: coordinator.remoteDeviceName,
                transportDescription: coordinator.transportDescription,
                message: "等待设备确认安全连接…"
            )
        case .preparing(let phase):
            return DeviceSyncActivityContentState(
                phase: activityPhase(for: phase),
                remoteDeviceName: coordinator.remoteDeviceName,
                transportDescription: coordinator.transportDescription,
                message: phaseTitle(phase)
            )
        case .awaitingSyncConfirmation(let preview):
            return DeviceSyncActivityContentState(
                phase: .waitingForConfirmation,
                remoteDeviceName: coordinator.remoteDeviceName,
                completedGalleries: 0,
                totalGalleries: preview.receiveGalleryCount + preview.sendGalleryCount,
                completedBytes: 0,
                totalBytes: preview.receiveBytes + preview.sendBytes,
                transportDescription: coordinator.transportDescription,
                message: "等待双方确认同步内容…"
            )
        case .syncing(let progress):
            return DeviceSyncActivityContentState(
                phase: activityPhase(for: progress.phase),
                direction: progress.direction.map(activityDirection(for:)),
                remoteDeviceName: coordinator.remoteDeviceName,
                completedGalleries: progress.completedGalleries,
                totalGalleries: progress.totalGalleries,
                completedBytes: progress.completedBytes,
                totalBytes: progress.totalBytes,
                currentGalleryTitle: progress.currentGalleryTitle,
                currentPageIndex: progress.currentPageIndex,
                estimatedRemainingSeconds: progress.estimatedRemainingSeconds,
                transportDescription: progress.transportInfo?.label ?? coordinator.transportDescription,
                message: phaseTitle(progress.phase)
            )
        case .completed(let result):
            return DeviceSyncActivityContentState(
                phase: .completed,
                remoteDeviceName: coordinator.remoteDeviceName,
                completedGalleries: result.sentGalleryCount + result.receivedGalleryCount,
                totalGalleries: result.plannedSentGalleryCount + result.plannedReceivedGalleryCount,
                completedBytes: result.sentBytes + result.receivedBytes,
                totalBytes: result.sentBytes + result.receivedBytes,
                transportDescription: coordinator.transportDescription,
                message: "同步完成"
            )
        case .cancelled(let result):
            return terminalContentState(
                phase: .cancelled,
                result: result,
                remoteDeviceName: coordinator.remoteDeviceName,
                message: "同步已取消"
            )
        case .interrupted(let interruption):
            return terminalContentState(
                phase: .interrupted,
                result: interruption.result,
                remoteDeviceName: coordinator.remoteDeviceName,
                message: interruption.reason
            )
        case .failed(let message):
            return DeviceSyncActivityContentState(
                phase: .failed,
                remoteDeviceName: coordinator.remoteDeviceName,
                transportDescription: coordinator.transportDescription,
                message: message
            )
        case .idle, .indexRequired, .discovering, .awaitingPairingCode:
            return DeviceSyncActivityContentState(
                phase: .failed,
                remoteDeviceName: coordinator.remoteDeviceName,
                message: "同步未开始"
            )
        }
    }

    private func terminalContentState(
        phase: DeviceSyncActivityPhase,
        result: DeviceSyncResult,
        remoteDeviceName: String,
        message: String
    ) -> DeviceSyncActivityContentState {
        DeviceSyncActivityContentState(
            phase: phase,
            remoteDeviceName: remoteDeviceName,
            completedGalleries: result.sentGalleryCount + result.receivedGalleryCount,
            totalGalleries: result.plannedSentGalleryCount + result.plannedReceivedGalleryCount,
            completedBytes: result.sentBytes + result.receivedBytes,
            totalBytes: result.sentBytes + result.receivedBytes,
            transportDescription: coordinator?.transportDescription,
            message: message
        )
    }

    private func activityPhase(for phase: DeviceSyncPhase) -> DeviceSyncActivityPhase {
        switch phase {
        case .generatingManifest: .generatingManifest
        case .waitingForConfirmation: .waitingForConfirmation
        case .sending: .sending
        case .receiving: .receiving
        case .verifying: .verifying
        case .committing: .committing
        case .comparingResults: .comparingResults
        }
    }

    private func activityDirection(for direction: DeviceSyncDirection) -> DeviceSyncActivityDirection {
        switch direction {
        case .sending: .sending
        case .receiving: .receiving
        }
    }

    private func phaseTitle(_ phase: DeviceSyncPhase) -> String {
        switch phase {
        case .generatingManifest: "正在生成同步清单…"
        case .waitingForConfirmation: "等待确认…"
        case .sending: "正在发送…"
        case .receiving: "正在接收…"
        case .verifying: "正在校验…"
        case .committing: "正在提交…"
        case .comparingResults: "正在再次比对…"
        }
    }
}
#endif
