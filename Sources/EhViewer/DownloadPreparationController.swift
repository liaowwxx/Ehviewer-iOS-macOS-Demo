#if os(iOS)
import EHDownloads
import UIKit

/// A finite handoff window, independent of the lifetime of system transfers.
@MainActor
final class DownloadPreparationController {
    private let coordinator: DownloadCoordinator
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var observation: Task<Void, Never>?
    private var foregroundObservation: Task<Void, Never>?
    private var activeJobIDs: Set<String> = []
    private var expired = false
    private var isShutdown = false

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        Task { await coordinator.setPreparationEnabled(UIApplication.shared.applicationState == .active) }
        observation = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification)
            for await _ in notifications {
                guard let self else { return }
                self.enterBackground()
            }
        }
        foregroundObservation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                self?.enterForeground()
            }
        }
    }

    func update(_ event: DownloadEvent) {
        guard !isShutdown else { return }
        switch event {
        case .reset(let jobs): activeJobIDs = Set(jobs.filter { $0.state == .queued || $0.state == .running }.map { $0.key.id })
        case .changed(let job):
            if job.state == .queued || job.state == .running { activeJobIDs.insert(job.key.id) }
            else { activeJobIDs.remove(job.key.id) }
        case .removed(let key): activeJobIDs.remove(key.id)
        case .removedMany(let keys): activeJobIDs.subtract(keys.map(\.id))
        }
        if activeJobIDs.isEmpty { endWindow() }
        if UIApplication.shared.applicationState == .active {
            expired = false
            endWindow()
            Task { await coordinator.setPreparationEnabled(true) }
        } else if !activeJobIDs.isEmpty, !expired {
            enterBackground()
        }
    }

    func enterForeground() {
        guard !isShutdown else { return }
        expired = false
        endWindow()
        Task { await coordinator.setPreparationEnabled(true) }
    }

    func enterBackground() {
        guard !isShutdown, !activeJobIDs.isEmpty, !expired, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Prepare gallery downloads") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.expired = true
                await self.coordinator.setPreparationEnabled(false)
                self.endWindow()
            }
        }
        if backgroundTask == .invalid {
            expired = true
            Task { await coordinator.setPreparationEnabled(false) }
        }
    }

    func shutdown() {
        isShutdown = true
        observation?.cancel()
        foregroundObservation?.cancel()
        observation = nil
        endWindow()
    }

    private func endWindow() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
#endif
