import Foundation
import EHDomain

public enum BackgroundDownloadEvents {
    private final class CompletionBox: @unchecked Sendable {
        let completion: () -> Void

        init(_ completion: @escaping () -> Void) {
            self.completion = completion
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var completionHandler: CompletionBox?

    public static func register(_ completionHandler: @escaping () -> Void) {
        lock.lock()
        self.completionHandler = CompletionBox(completionHandler)
        lock.unlock()
    }

    fileprivate static func finish() {
        lock.lock()
        let handler = completionHandler
        completionHandler = nil
        lock.unlock()
        if let handler {
            Task { @MainActor in handler.completion() }
        }
    }
}

public actor BackgroundDownloadSession {
    public typealias TaskObserver = @Sendable (_ taskDescription: String, _ taskIdentifier: Int) async -> Void
    public typealias OrphanCompletion = @Sendable (_ taskDescription: String, _ data: Data, _ statusCode: Int) async -> Void

    private enum Event: Sendable {
        case finished(taskID: Int, taskDescription: String, data: Data, statusCode: Int)
        case completed(taskID: Int, taskDescription: String, statusCode: Int, errorDescription: String?)
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        var onEvent: (@Sendable (Event) -> Void)?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let taskDescription = downloadTask.taskDescription ?? ""
            let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                onEvent?(.finished(
                    taskID: downloadTask.taskIdentifier,
                    taskDescription: taskDescription,
                    data: try Data(contentsOf: location),
                    statusCode: statusCode
                ))
            } catch {
                onEvent?(.completed(
                    taskID: downloadTask.taskIdentifier,
                    taskDescription: taskDescription,
                    statusCode: 0,
                    errorDescription: error.localizedDescription
                ))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            onEvent?(.completed(
                taskID: task.taskIdentifier,
                taskDescription: task.taskDescription ?? "",
                statusCode: (task.response as? HTTPURLResponse)?.statusCode ?? 0,
                errorDescription: error?.localizedDescription
            ))
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            BackgroundDownloadEvents.finish()
        }
    }

    private let session: URLSession
    private let delegate: Delegate
    private let taskObserver: TaskObserver?
    private let orphanCompletion: OrphanCompletion?
    private var continuations: [Int: CheckedContinuation<Data, Error>] = [:]
    private var requestURLs: [Int: URL] = [:]
    private var finishedData: [Int: (Data, Int, String)] = [:]

    public init(
        identifier: String = "com.liao.ehviewer.background-downloads",
        taskObserver: TaskObserver? = nil,
        orphanCompletion: OrphanCompletion? = nil
    ) {
        let delegate = Delegate()
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
#if os(iOS)
        configuration.sessionSendsLaunchEvents = true
#endif
        self.delegate = delegate
        self.taskObserver = taskObserver
        self.orphanCompletion = orphanCompletion
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.onEvent = { [weak self] event in
            Task { await self?.handle(event) }
        }
    }

    public func data(for request: URLRequest, taskDescription: String = "") async throws -> Data {
        let url = request.url
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.downloadTask(with: request)
                task.taskDescription = taskDescription
                continuations[task.taskIdentifier] = continuation
                if let url { requestURLs[task.taskIdentifier] = url }
                task.resume()
                if let taskObserver {
                    Task { await taskObserver(taskDescription, task.taskIdentifier) }
                }
            }
        } onCancel: {
            Task { await self.cancel(url: url) }
        }
    }

    public func activeTaskIdentifiers() async -> [Int] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks.map(\.taskIdentifier))
            }
        }
    }

    private func cancel(url: URL?) {
        let identifiers = requestURLs.compactMap { identifier, requestURL in
            url == requestURL ? identifier : nil
        }
        for identifier in identifiers {
            session.getAllTasks { tasks in
                tasks.first(where: { $0.taskIdentifier == identifier })?.cancel()
            }
            continuations.removeValue(forKey: identifier)?.resume(throwing: CancellationError())
            requestURLs.removeValue(forKey: identifier)
            finishedData.removeValue(forKey: identifier)
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case let .finished(taskID, taskDescription, data, statusCode):
            finishedData[taskID] = (data, statusCode, taskDescription)
        case let .completed(taskID, taskDescription, statusCode, errorDescription):
            if let errorDescription {
                continuations.removeValue(forKey: taskID)?.resume(throwing: EHError.networkFailed(errorDescription))
                finishedData.removeValue(forKey: taskID)
            } else if let (data, storedStatus, storedDescription) = finishedData.removeValue(forKey: taskID) {
                let status = storedStatus == 0 ? statusCode : storedStatus
                let description = storedDescription.isEmpty ? taskDescription : storedDescription
                if let continuation = continuations.removeValue(forKey: taskID) {
                    if (200..<300).contains(status) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: EHError.httpStatus(status))
                    }
                } else if (200..<300).contains(status), let orphanCompletion, description.isEmpty == false {
                    Task { await orphanCompletion(description, data, status) }
                }
            } else {
                continuations.removeValue(forKey: taskID)?.resume(throwing: EHError.httpStatus(statusCode))
            }
            requestURLs.removeValue(forKey: taskID)
        }
    }
}
