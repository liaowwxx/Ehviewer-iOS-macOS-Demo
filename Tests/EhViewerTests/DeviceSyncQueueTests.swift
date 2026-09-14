import Foundation
import Network
import Testing
@testable import EHDeviceSync
import EHDomain
import EHDownloads

struct DeviceSyncQueueTests {
    @Test("Legacy TCP transport drains a send window larger than 16 MiB", .timeLimit(.minutes(1)))
    func legacyTransportDrainsLargeWindow() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        let listenerReady = DeviceSyncContinuationGate<NWEndpoint.Port>()
        let acceptedConnection = DeviceSyncContinuationGate<NWConnection>()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port {
                    listenerReady.succeed(port)
                } else {
                    listenerReady.fail(DeviceSyncError.notReady)
                }
            case let .failed(error):
                listenerReady.fail(error)
                acceptedConnection.fail(error)
            case .cancelled:
                listenerReady.fail(CancellationError())
                acceptedConnection.fail(CancellationError())
            default:
                break
            }
        }
        listener.newConnectionHandler = { acceptedConnection.succeed($0) }
        listener.start(queue: DispatchQueue(label: "EhViewerTests.DeviceSync.Listener"))
        defer { listener.cancel() }

        let port = try await withCheckedThrowingContinuation { listenerReady.install($0) }
        let clientConnection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let client = DeviceSyncWireConnection(connection: clientConnection)
        async let clientStarted: Void = client.start(timeout: .seconds(5))
        let serverConnection = try await withCheckedThrowingContinuation { acceptedConnection.install($0) }
        let server = DeviceSyncWireConnection(connection: serverConnection)
        async let serverStarted: Void = server.start(timeout: .seconds(5))
        try await clientStarted
        try await serverStarted
        defer {
            client.cancel()
            server.cancel()
        }

        let chunkCount = 20
        let chunk = Data(repeating: 0xA5, count: DeviceSyncCoordinator.maximumPageChunkBytes)
        let expectedByteCount = Int64(chunk.count * chunkCount)
        let receivedProgress = DeviceSyncProgressBuffer(threshold: .max)

        async let received: Void = server.receiveExactly(expectedByteCount) { data in
            _ = await receivedProgress.add(data.count)
        }
        for _ in 0..<chunkCount {
            _ = try await client.enqueueRaw(chunk)
        }
        _ = try await client.flush()
        try await received

        #expect(await receivedProgress.totalByteCount == expectedByteCount)
    }

    @Test("Continuation gate preserves cancellation that wins before callback installation")
    func continuationGatePreservesEarlyCancellation() async {
        let gate = DeviceSyncContinuationGate<Int>()
        gate.fail(CancellationError())
        gate.succeed(42)

        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
            }
        }
    }

    @Test("Continuation gate ignores a late cancellation after callback success")
    func continuationGatePreservesFirstResult() async throws {
        let gate = DeviceSyncContinuationGate<Int>()
        gate.succeed(42)
        gate.fail(CancellationError())

        let result = try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
        }
        #expect(result == 42)
    }

    @Test("Bounded byte queue preserves order and resumes a blocked producer")
    func preservesOrderWithBackpressure() async throws {
        let queue = DeviceSyncBoundedByteQueue(capacity: 4)
        let first = Data([1, 2, 3])
        let second = Data([4, 5, 6])
        try await queue.send(first)

        let producer = Task { try await queue.send(second) }
        #expect(await queue.byteCount == first.count)
        #expect(try await queue.receive() == first)
        try await producer.value
        #expect(await queue.byteCount == second.count)
        await queue.finish()
        #expect(try await queue.receive() == second)
        #expect(try await queue.receive() == nil)
    }

    @Test("Queue failure wakes a suspended consumer with the same reason")
    func failureWakesConsumer() async {
        let queue = DeviceSyncBoundedByteQueue(capacity: 4)
        let consumer = Task { try await queue.receive() }
        await Task.yield()
        await queue.fail(DeviceSyncBoundedByteQueue.QueueError.failed("disconnected"))

        await #expect(throws: DeviceSyncBoundedByteQueue.QueueError.failed("disconnected")) {
            try await consumer.value
        }
    }

    @Test("Cancelling a blocked queue operation never leaves it suspended")
    func cancellationWakesBlockedOperation() async {
        let queue = DeviceSyncBoundedByteQueue(capacity: 4)
        let consumer = Task { try await queue.receive() }
        await Task.yield()
        consumer.cancel()

        await #expect(throws: CancellationError.self) {
            try await consumer.value
        }
    }

    @Test("An element larger than capacity is rejected without buffering")
    func rejectsOversizedElement() async {
        let queue = DeviceSyncBoundedByteQueue(capacity: 4)
        await #expect(throws: DeviceSyncBoundedByteQueue.QueueError.elementExceedsCapacity) {
            try await queue.send(Data(repeating: 0, count: 5))
        }
        #expect(await queue.byteCount == 0)
    }

    @Test("Network staging leaves the formal download directory untouched until no-validation commit")
    func stagingIsolatedUntilCommit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ehviewer-v4-staging-\(UUID().uuidString)")
        let downloadRoot = root.appendingPathComponent("Downloads")
        let transactionRoot = root.appendingPathComponent("Transactions")
        let files = DownloadFileStore(root: downloadRoot, minimumFreeBytes: 1)
        let staging = DeviceSyncStagingStore(root: transactionRoot)
        let key = GalleryKey(gid: 9001, token: "staged")
        let payload = Data([0x00, 0x01, 0x02, 0x03])
        let sessionID = try await staging.create(plan: [
            DeviceSyncStagingGalleryPlan(
                key: key,
                pages: [DeviceSyncStagingPage(pageIndex: 0, byteCount: Int64(payload.count))],
                requiresMetadata: false
            )
        ])
        let pageID = try await staging.beginPage(
            for: key,
            pageIndex: 0,
            byteCount: Int64(payload.count),
            sessionID: sessionID
        )
        try await staging.append(payload, to: pageID)
        try await staging.finishPage(pageID)
        try await staging.finishGallery(key, sessionID: sessionID)

        #expect(await files.contains(key, pageIndex: 0) == false)
        let stagedURL = await staging.pageURL(for: key, pageIndex: 0, sessionID: sessionID)
        _ = try await files.commitDeviceSyncStagedFile(at: stagedURL, for: key, pageIndex: 0)
        #expect(await files.contains(key, pageIndex: 0))

        await staging.removeSession(sessionID)
        try await files.remove(key)
    }

    @Test("v4 binary control frames survive every stream split without base64 wrapping")
    func binaryFrameFragmentation() throws {
        let payload = Data((0..<251).map(UInt8.init))
        let encoded = try DeviceSyncWireFrame(type: .metadata, payload: payload).encoded()
        #expect(encoded.count == payload.count + DeviceSyncWireFrame.headerByteCount)
        #expect(Data(encoded.suffix(payload.count)) == payload)

        for split in 0...encoded.count {
            var reassembled = Data(encoded.prefix(split))
            reassembled.append(encoded.suffix(encoded.count - split))
            let decoded = try DeviceSyncWireFrame.decodeEncoded(reassembled)
            #expect(decoded.type == .metadata)
            #expect(decoded.payload == payload)
        }
    }
}
