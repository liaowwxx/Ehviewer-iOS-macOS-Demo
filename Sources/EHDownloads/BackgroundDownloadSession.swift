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

import Foundation
import EHDomain
import EHNetworking

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
        case finished(taskID: Int, taskDescription: String, data: Data, statusCode: Int, siteError: EHError?)
        case completed(taskID: Int, taskDescription: String, statusCode: Int, errorDescription: String?)
    }

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        var onEvent: (@Sendable (Event) -> Void)?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            let taskDescription = downloadTask.taskDescription ?? ""
            let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            do {
                let data = try Data(contentsOf: location)
                let response = downloadTask.response as? HTTPURLResponse
                let siteError: EHError?
                if response?.value(forHTTPHeaderField: "Content-Disposition")?.contains("sadpanda.jpg") == true {
                    siteError = .exHentaiAccessDenied
                } else if String(data: data, encoding: .utf8)?.contains("exhentai.org/img/kokomade.jpg") == true {
                    siteError = .siteAccessLimited
                } else {
                    siteError = nil
                }
                onEvent?(.finished(
                    taskID: downloadTask.taskIdentifier,
                    taskDescription: taskDescription,
                    data: data,
                    statusCode: statusCode,
                    siteError: siteError
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

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var redirected = request
            if request.url.map(CookieHeader.isTrustedURL) != true {
                redirected.setValue(nil, forHTTPHeaderField: "Cookie")
            }
            completionHandler(redirected)
        }
    }

    private let session: URLSession
    private let delegate: Delegate
    private let taskObserver: TaskObserver?
    private let orphanCompletion: OrphanCompletion?
    private var continuations: [Int: CheckedContinuation<Data, Error>] = [:]
    private var requestURLs: [Int: URL] = [:]
    private var finishedData: [Int: (Data, Int, String, EHError?)] = [:]

    public init(
        identifier: String = "com.liao.ehviewer.background-downloads",
        taskObserver: TaskObserver? = nil,
        orphanCompletion: OrphanCompletion? = nil
    ) {
        let delegate = Delegate()
#if os(iOS)
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
#else
        // AppKit does not support background URLSession relaunch events. A
        // default session also avoids requiring the macOS application
        // identifier entitlement for a feature macOS cannot provide.
        let configuration = URLSessionConfiguration.default
#endif
        configuration.waitsForConnectivity = true
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
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

    /// Cancels every task owned by this runtime and resumes any suspended
    /// callers. Profile switching uses a distinct session identifier, so this
    /// never reaches another profile's downloads.
    public func cancelAll() async {
        let continuations = self.continuations
        self.continuations.removeAll()
        requestURLs.removeAll()
        finishedData.removeAll()
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
            }
        }
        continuations.values.forEach { $0.resume(throwing: CancellationError()) }
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
        case let .finished(taskID, taskDescription, data, statusCode, siteError):
            finishedData[taskID] = (data, statusCode, taskDescription, siteError)
        case let .completed(taskID, taskDescription, statusCode, errorDescription):
            if let errorDescription {
                continuations.removeValue(forKey: taskID)?.resume(throwing: EHError.networkFailed(errorDescription))
                finishedData.removeValue(forKey: taskID)
            } else if let (data, storedStatus, storedDescription, siteError) = finishedData.removeValue(forKey: taskID) {
                let status = storedStatus == 0 ? statusCode : storedStatus
                let description = storedDescription.isEmpty ? taskDescription : storedDescription
                if let continuation = continuations.removeValue(forKey: taskID) {
                    if let siteError, (200..<300).contains(status) {
                        continuation.resume(throwing: siteError)
                    } else if (200..<300).contains(status) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: EHError.httpStatus(status))
                    }
                } else if (200..<300).contains(status), siteError == nil, let orphanCompletion, description.isEmpty == false {
                    Task { await orphanCompletion(description, data, status) }
                }
            } else {
                continuations.removeValue(forKey: taskID)?.resume(throwing: EHError.httpStatus(statusCode))
            }
            requestURLs.removeValue(forKey: taskID)
        }
    }
}
