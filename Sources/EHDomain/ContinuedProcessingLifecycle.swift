/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

/// Keeps a submitted request alive until its launch callback has been handled,
/// even when the foreground work finishes before that callback arrives.
public struct ContinuedProcessingLifecycle: Sendable {
    public enum LaunchDisposition: Sendable, Equatable {
        case run
        case complete(success: Bool)
        case duplicate
    }

    private enum State: Sendable {
        case idle
        case submitted
        case running
        case awaitingCompletion(success: Bool)
    }

    private var state: State = .idle

    public init() {}

    public var canSubmit: Bool {
        if case .idle = state { return true }
        return false
    }

    public var isProcessing: Bool {
        switch state {
        case .submitted, .running: true
        case .idle, .awaitingCompletion: false
        }
    }

    @discardableResult
    public mutating func submit() -> Bool {
        guard canSubmit else { return false }
        state = .submitted
        return true
    }

    public mutating func submissionFailed() {
        if case .submitted = state { state = .idle }
    }

    public mutating func launch() -> LaunchDisposition {
        switch state {
        case .submitted:
            state = .running
            return .run
        case .awaitingCompletion(let success):
            state = .idle
            return .complete(success: success)
        case .running:
            return .duplicate
        case .idle:
            return .complete(success: false)
        }
    }

    /// Returns whether a running system task needs its completion reported now.
    @discardableResult
    public mutating func finish(success: Bool) -> Bool {
        switch state {
        case .submitted:
            state = .awaitingCompletion(success: success)
            return false
        case .running:
            state = .idle
            return true
        case .idle, .awaitingCompletion:
            // The first terminal result is authoritative.
            return false
        }
    }
}
