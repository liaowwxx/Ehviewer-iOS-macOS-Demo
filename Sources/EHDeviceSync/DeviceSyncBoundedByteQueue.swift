/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

/// Bridges a single callback to Swift concurrency without relying on the
/// underlying API to invoke its callback after cancellation. Cancellation may
/// race with continuation installation or with the callback; exactly one
/// result wins and every installed continuation is resumed.
final class DeviceSyncContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var pendingResult: Result<Value, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let result: Result<Value, Error>?
        lock.lock()
        if let pendingResult {
            self.pendingResult = nil
            result = pendingResult
        } else {
            precondition(self.continuation == nil, "Continuation installed more than once")
            self.continuation = continuation
            result = nil
        }
        lock.unlock()

        if let result {
            continuation.resume(with: result)
        }
    }

    func succeed(_ value: Value) {
        resolve(.success(value))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<Value, Error>) {
        let continuation: CheckedContinuation<Value, Error>?
        lock.lock()
        guard isResolved == false else {
            lock.unlock()
            return
        }
        isResolved = true
        if let installed = self.continuation {
            self.continuation = nil
            continuation = installed
        } else {
            pendingResult = result
            continuation = nil
        }
        lock.unlock()

        continuation?.resume(with: result)
    }
}

/// A lossless, byte-counted queue used between the network reader and the
/// staging-file writer. There is exactly one producer and one consumer per
/// page. Suspended operations are resumed on every terminal path.
actor DeviceSyncBoundedByteQueue {
    enum QueueError: Error, Sendable, Equatable {
        case closed
        case elementExceedsCapacity
        case failed(String)
    }

    private struct PendingSend {
        let id: UUID
        let data: Data
        let continuation: CheckedContinuation<Void, Error>
    }

    private let capacity: Int
    private var values: [Data] = []
    private var head = 0
    private var bufferedBytes = 0
    private var pendingSend: PendingSend?
    private var pendingReceive: (id: UUID, continuation: CheckedContinuation<Data?, Error>)?
    private var terminalError: QueueError?
    private var finished = false

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    var byteCount: Int { bufferedBytes }

    func send(_ data: Data) async throws {
        guard data.isEmpty == false else { return }
        guard data.count <= capacity else { throw QueueError.elementExceedsCapacity }
        try throwIfTerminal()

        if let receiver = pendingReceive, values.isEmpty {
            pendingReceive = nil
            receiver.continuation.resume(returning: data)
            return
        }
        if bufferedBytes + data.count <= capacity {
            values.append(data)
            bufferedBytes += data.count
            return
        }
        guard pendingSend == nil else {
            throw QueueError.failed("Device sync queue has more than one producer")
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                pendingSend = PendingSend(id: id, data: data, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancelSend(id) }
        }
    }

    func receive() async throws -> Data? {
        if head < values.count {
            let value = values[head]
            head += 1
            bufferedBytes -= value.count
            compactIfNeeded()
            admitPendingSendIfPossible()
            return value
        }
        if let terminalError { throw terminalError }
        if finished { return nil }
        guard pendingReceive == nil else {
            throw QueueError.failed("Device sync queue has more than one consumer")
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pendingReceive = (id, continuation)
            }
        } onCancel: {
            Task { await self.cancelReceive(id) }
        }
    }

    func finish() {
        guard finished == false, terminalError == nil else { return }
        finished = true
        if values.isEmpty {
            pendingReceive?.continuation.resume(returning: nil)
            pendingReceive = nil
        }
        pendingSend?.continuation.resume(throwing: QueueError.closed)
        pendingSend = nil
    }

    func fail(_ error: Error) {
        guard terminalError == nil else { return }
        let queueError = (error as? QueueError) ?? .failed(error.localizedDescription)
        terminalError = queueError
        values.removeAll(keepingCapacity: false)
        head = 0
        bufferedBytes = 0
        pendingSend?.continuation.resume(throwing: queueError)
        pendingSend = nil
        pendingReceive?.continuation.resume(throwing: queueError)
        pendingReceive = nil
    }

    private func throwIfTerminal() throws {
        if let terminalError { throw terminalError }
        if finished { throw QueueError.closed }
    }

    private func admitPendingSendIfPossible() {
        guard let pendingSend,
              finished == false,
              terminalError == nil,
              bufferedBytes + pendingSend.data.count <= capacity else { return }
        self.pendingSend = nil
        values.append(pendingSend.data)
        bufferedBytes += pendingSend.data.count
        pendingSend.continuation.resume(returning: ())
    }

    private func cancelSend(_ id: UUID) {
        guard pendingSend?.id == id else { return }
        pendingSend?.continuation.resume(throwing: CancellationError())
        pendingSend = nil
    }

    private func cancelReceive(_ id: UUID) {
        guard pendingReceive?.id == id else { return }
        pendingReceive?.continuation.resume(throwing: CancellationError())
        pendingReceive = nil
    }

    private func compactIfNeeded() {
        guard head > 64, head * 2 >= values.count else { return }
        values.removeFirst(head)
        head = 0
    }
}

actor DeviceSyncProgressBuffer {
    private let threshold: Int64
    private var pending: Int64 = 0
    private var total: Int64 = 0

    init(threshold: Int64) {
        self.threshold = max(1, threshold)
    }

    func add(_ byteCount: Int) -> Int64 {
        total += Int64(byteCount)
        pending += Int64(byteCount)
        guard pending >= threshold else { return 0 }
        let result = pending
        pending = 0
        return result
    }

    func drain() -> Int64 {
        defer { pending = 0 }
        return pending
    }

    var totalByteCount: Int64 { total }
}
