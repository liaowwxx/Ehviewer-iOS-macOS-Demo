/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

#if os(iOS)
@preconcurrency import BackgroundTasks
import EHDomain
import EHDownloads
import OSLog
import UIKit

@MainActor
final class DownloadBackgroundTaskRegistry {
    static let shared = DownloadBackgroundTaskRegistry()
    private var registered = false
    private weak var controller: DownloadBackgroundTaskController?
    private var pendingTask: BGContinuedProcessingTask?

    @discardableResult
    func register() -> Bool {
        if registered { return true }
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: DownloadBackgroundTaskController.identifier,
            using: DispatchQueue.main
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            if let controller = self.controller {
                controller.handle(task)
            } else {
                self.pendingTask = task
            }
        }
        return registered
    }

    func bind(_ controller: DownloadBackgroundTaskController) {
        self.controller = controller
        if let pendingTask {
            self.pendingTask = nil
            controller.handle(pendingTask)
        }
    }
}

/// The system supplies both background execution time and the Live Activity.
@MainActor
final class DownloadBackgroundTaskController {
    static let identifier = "com.liao.ehviewer.downloads.continued-processing"
    private let coordinator: DownloadCoordinator
    private let logger = Logger(subsystem: "com.liao.ehviewer", category: "download-background")
    private var jobs: [GalleryKey: DownloadJob] = [:]
    private var batchKeys: Set<GalleryKey> = []
    private var submitted = false
    private var interrupted = false
    private var task: BGContinuedProcessingTask?

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        DownloadBackgroundTaskRegistry.shared.bind(self)
    }

    func update(_ event: DownloadEvent) {
        switch event {
        case .reset(let jobs):
            self.jobs = Dictionary(uniqueKeysWithValues: jobs.map { ($0.key, $0) })
        case .changed(let job): jobs[job.key] = job
        case .removed(let key): jobs[key] = nil
        case .removedMany(let keys):
            for key in keys { jobs[key] = nil }
        }
        let active = jobs.values.filter { $0.state == .queued || $0.state == .running }
        guard active.isEmpty == false else {
            interrupted = false
            finish(success: batchKeys.allSatisfy { jobs[$0]?.state == .completed })
            return
        }
        batchKeys.formUnion(active.map(\.key))
        if task == nil, submitted == false, interrupted == false,
           UIApplication.shared.applicationState == .active,
           DownloadBackgroundTaskRegistry.shared.register() {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.identifier,
                title: String(localized: "正在下载画廊"),
                subtitle: String(localized: "下载会在锁屏或进入后台后继续")
            )
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
                submitted = true
            } catch {
                logger.error("Unable to start continued downloads: \(error.localizedDescription, privacy: .public)")
            }
        }
        updateProgress()
    }

    func handle(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.task != nil else { return }
                self.interrupted = true
                // Stop before completing so cancellation cannot restart a queue.
                await self.coordinator.stopAll()
                self.finish(success: false)
            }
        }
        if jobs.values.contains(where: { $0.state == .running || $0.state == .queued }) {
            updateProgress()
        } else {
            finish(success: false)
        }
    }

    func shutdown() {
        interrupted = true
        finish(success: false)
        jobs.removeAll()
    }

    private func updateProgress() {
        guard let task else { return }
        let batch = batchKeys.compactMap { jobs[$0] }
        task.progress.totalUnitCount = max(1, Int64(batch.reduce(0) { $0 + $1.pages.count }))
        task.progress.completedUnitCount = Int64(batch.reduce(0) { $0 + $1.completedPageIndexes.count })
        let current = batch.first { $0.state == .running } ?? batch.first { $0.state == .queued }
        let completed = task.progress.completedUnitCount
        let total = task.progress.totalUnitCount
        task.updateTitle(String(localized: "正在下载画廊"), subtitle: "\(completed)/\(total) · \(current?.title.prefix(36) ?? "")")
    }

    private func finish(success: Bool) {
        if success, let task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        task?.setTaskCompleted(success: success)
        task = nil
        if submitted {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
        }
        submitted = false
        batchKeys.removeAll()
    }
}
#endif
