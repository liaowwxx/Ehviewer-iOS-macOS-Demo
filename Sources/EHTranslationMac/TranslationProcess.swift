#if os(macOS)
import Foundation

/// Owns a process group. A cancelled request drains and reaps its descendants.
actor TranslationProcess {
    private var process: Process?
    private let bridgeDirectory: URL?

    init(bridgeDirectory: URL? = nil) { self.bridgeDirectory = bridgeDirectory }

    func cancel() {
        guard let process, process.isRunning else { return }
        kill(-process.processIdentifier, SIGTERM)
        let pid = process.processIdentifier
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.process?.processIdentifier == pid, self.process?.isRunning == true { kill(-pid, SIGKILL) }
        }
    }

    func request(python: URL, payload: TranslationJSON, log: URL) async throws -> TranslationJSON {
        guard process == nil else { throw CocoaError(.executableLoad) }
        guard let bridge = bridgeDirectory ?? TranslationBridgeResources.directory else { throw CocoaError(.fileNoSuchFile) }
        let input = Pipe(), output = Pipe()
        let child = Process()
        child.executableURL = python
        // setsid inside the Python bootstrap makes cancellation cover the engine
        // and package-manager children, without spawning a shell.
        child.arguments = ["-B", "-c", "import os,runpy; os.setsid() if os.getpgrp()!=os.getpid() else None; runpy.run_module('bridge.service',run_name='__main__')"]
        child.currentDirectoryURL = bridge.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = bridge.deletingLastPathComponent().path
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["QT_QPA_PLATFORM"] = "offscreen"
        child.environment = environment
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let diagnostics = try FileHandle(forWritingTo: log)
        defer { try? diagnostics.close() }
        child.standardInput = input
        child.standardOutput = output
        child.standardError = diagnostics
        process = child
        defer { process = nil }
        return try await withTaskCancellationHandler {
            do {
                let data = try JSONEncoder().encode(payload) + Data([10])
                guard data.count <= 4 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                try child.run()
                // FileHandle writes can block; keep both directions off actor/main.
                let writer = Task.detached {
                    try input.fileHandleForWriting.write(contentsOf: data)
                    try input.fileHandleForWriting.close()
                }
                var result = Data()
                for try await byte in output.fileHandleForReading.bytes {
                    result.append(byte)
                    if result.count > 4 * 1024 * 1024 { cancel(); throw CocoaError(.fileReadTooLarge) }
                }
                try await writer.value
                await Task.detached { child.waitUntilExit() }.value
                try Task.checkCancellation()
                let message = try JSONDecoder().decode(TranslationJSON.self, from: result)
                if !message["error"].string.isEmpty {
                    throw TranslationBridgeError(message: message["error"].string)
                }
                return message["result"]
            } catch {
                // Never drop the process owner while a cancelled/malformed
                // helper still has descendants holding the output pipe open.
                if child.processIdentifier > 0 { kill(-child.processIdentifier, SIGKILL) }
                if child.isRunning { await Task.detached { child.waitUntilExit() }.value }
                throw error
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }
}

struct TranslationBridgeError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
#endif
