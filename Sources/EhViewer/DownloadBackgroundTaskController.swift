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
    private var lifecycle = ContinuedProcessingLifecycle()
    private var interrupted = false
    private var stopping = false
    private var isShutdown = false
    private var task: BGContinuedProcessingTask?

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        DownloadBackgroundTaskRegistry.shared.bind(self)
    }

    func update(_ event: DownloadEvent) {
        guard isShutdown == false else { return }
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
            guard stopping == false else { return }
            interrupted = false
            finish(success: batchKeys.allSatisfy { jobs[$0]?.state == .completed })
            return
        }
        if lifecycle.canSubmit, interrupted == false,
           UIApplication.shared.applicationState == .active,
           DownloadBackgroundTaskRegistry.shared.register() {
            let request = BGContinuedProcessingTaskRequest(
                identifier: Self.identifier,
                title: String(localized: "正在下载画廊"),
                subtitle: String(localized: "下载会在锁屏或进入后台后继续")
            )
            request.strategy = .fail
            lifecycle.submit()
            batchKeys.formUnion(active.map(\.key))
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                lifecycle.submissionFailed()
                batchKeys.removeAll()
                logger.error("Unable to start continued downloads: \(error.localizedDescription, privacy: .public)")
            }
        }
        if lifecycle.isProcessing {
            batchKeys.formUnion(active.map(\.key))
        }
        updateProgress()
    }

    func handle(_ task: BGContinuedProcessingTask) {
        if self.task === task { return }
        switch lifecycle.launch() {
        case .complete(let success):
            complete(task, success: success)
            // A new download may have arrived while the old launch was pending.
            update(.reset(Array(jobs.values)))
            return
        case .duplicate:
            complete(task, success: false)
            return
        case .run:
            break
        }
        self.task = task
        task.expirationHandler = { [weak self, weak task] in
            Task { @MainActor [weak self, weak task] in
                guard let self, let task, self.task === task else { return }
                self.interrupted = true
                self.stopping = true
                await self.coordinator.stopAll()
                self.stopping = false
                guard self.task === task else { return }
                self.finish(success: false)
            }
        }
        if jobs.values.contains(where: { $0.state == .running || $0.state == .queued }) {
            updateProgress()
        } else {
            finish(success: batchKeys.allSatisfy { jobs[$0]?.state == .completed })
        }
    }

    func shutdown() {
        isShutdown = true
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
        if lifecycle.finish(success: success), let task {
            self.task = nil
            complete(task, success: success)
        }
        batchKeys.removeAll()
    }

    private func complete(_ task: BGContinuedProcessingTask, success: Bool) {
        task.expirationHandler = nil
        if success {
            task.progress.totalUnitCount = max(1, task.progress.totalUnitCount)
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.updateTitle(String(localized: "下载已完成"), subtitle: "")
        } else {
            task.updateTitle(String(localized: "下载已停止"), subtitle: String(localized: "请在下载列表查看状态"))
        }
        // This ends the background execution/UI session. Download failures and
        // pauses remain in DownloadJob; reporting them as scheduler failures
        // leaves a system-owned failure card that the app cannot dismiss.
        task.setTaskCompleted(success: true)
    }
}
#endif
