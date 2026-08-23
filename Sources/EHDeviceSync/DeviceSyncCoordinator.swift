/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

@preconcurrency import Network
import CryptoKit
import Foundation
import Observation
import Security
#if os(iOS)
import UIKit
#endif
import EHDomain
import EHPersistence
import EHDownloads

public enum DeviceSyncError: Error, LocalizedError, Sendable, Equatable {
    case notReady
    case invalidPairingCode
    case pairingExpired
    case tooManyPairingAttempts
    case anotherConnectionPending
    case connectionTimeout
    case controlFrameTooLarge
    case unexpectedMessage
    case transferNotPlanned
    case peerRejected
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notReady:
            String(localized: "设备同步连接尚未准备好。")
        case .invalidPairingCode:
            String(localized: "验证码必须是 6 位数字。")
        case .pairingExpired:
            String(localized: "验证码已过期，请重新发起同步。")
        case .tooManyPairingAttempts:
            String(localized: "验证码尝试次数过多。")
        case .anotherConnectionPending:
            String(localized: "已有一个待确认的设备同步连接。")
        case .connectionTimeout:
            String(localized: "安全连接超时，请重试。")
        case .controlFrameTooLarge:
            String(localized: "设备同步控制消息过大。")
        case .unexpectedMessage:
            String(localized: "设备同步收到无法识别的消息。")
        case .transferNotPlanned:
            String(localized: "设备同步收到未计划的文件。")
        case .peerRejected:
            String(localized: "对方拒绝了设备同步。")
        case let .network(message):
            message
        }
    }
}

public struct DeviceSyncPeer: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct DeviceSyncPreview: Hashable, Sendable {
    public let plan: DeviceSyncPlan
    public let receiveGalleryCount: Int
    public let sendGalleryCount: Int
    public let receivePageCount: Int
    public let sendPageCount: Int
    public let receiveBytes: Int64
    public let sendBytes: Int64

    fileprivate init(plan: DeviceSyncPlan) {
        self.plan = plan
        receiveGalleryCount = plan.receiveGalleries.count
        sendGalleryCount = plan.sendGalleries.count
        receivePageCount = plan.receivePages.count
        sendPageCount = plan.sendPages.count
        receiveBytes = plan.receiveBytes
        sendBytes = plan.sendBytes
    }
}

public struct DeviceSyncProgress: Hashable, Sendable {
    public let completedPages: Int
    public let totalPages: Int
    public let completedBytes: Int64
    public let totalBytes: Int64

    fileprivate init(completedPages: Int, totalPages: Int, completedBytes: Int64, totalBytes: Int64) {
        self.completedPages = completedPages
        self.totalPages = totalPages
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double? {
        guard totalBytes > 0 else { return totalPages > 0 ? Double(completedPages) / Double(totalPages) : nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

public enum DeviceSyncState: Sendable, Equatable {
    case idle
    case discovering
    case awaitingPairingCode
    case connecting
    case awaitingRemoteConfirmation
    case awaitingConnectionConfirmation
    case awaitingSyncConfirmation(DeviceSyncPreview)
    case syncing(DeviceSyncProgress)
    case completed
    case failed(String)
}

@MainActor
@Observable
public final class DeviceSyncCoordinator {
    nonisolated public static let serviceType = "_ehviewer-sync._tcp"
    nonisolated public static let protocolVersion = 1
    nonisolated public static let maximumControlFrameBytes = 4 * 1024 * 1024
    nonisolated public static let pageChunkBytes = 64 * 1024
    private static let serviceInstanceTXTKey = "ehviewer-instance"

    public let persistence: PersistenceStore
    public let files: DownloadFileStore

    public private(set) var state: DeviceSyncState = .idle
    public private(set) var peers: [DeviceSyncPeer] = []
    public private(set) var pairingCode: String?
    public private(set) var localDeviceName: String
    public private(set) var remoteDeviceName = "EhViewer"

    /// Opaque per-coordinator identifier used only to filter this process's
    /// own Bonjour advertisement from browser results. It is not user data.
    private let serviceInstanceID = UUID().uuidString
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var endpoints: [String: NWEndpoint] = [:]
    private var pendingIncoming: NWConnection?
    private var wire: DeviceSyncWireConnection?
    private var sessionTask: Task<Void, Never>?
    private var pairingExpiryTask: Task<Void, Never>?
    private var pairingAttempts = 0
    private var secureListenerActive = false
    private var isInitiator = false
    private var localApproved = false
    private var peerApproved = false
    private var localSyncRequested = false
    private var localSyncStartSent = false
    private var peerSyncRequested = false
    private var localSyncConfirmationWaiter: CheckedContinuation<Void, Never>?
    private var localManifest: DeviceSyncManifest?
    private var localRecords: [GalleryKey: GalleryTransferRecord] = [:]
    private var remoteManifest: DeviceSyncManifest?
    private var currentPlan: DeviceSyncPlan?
    private var currentPreview: DeviceSyncPreview?

    public init(persistence: PersistenceStore, files: DownloadFileStore) {
        self.persistence = persistence
        self.files = files
        self.localDeviceName = Self.makeDeviceName()
    }

    /// Starts Bonjour browser/listener only while the sync screen is active.
    public func start() {
        stop()
        state = .discovering
        do {
            try installListener(using: makeListenerParameters(code: nil))

            let browseParameters = NWParameters.tcp
            browseParameters.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
                using: browseParameters
            )
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor [weak self] in
                    self?.updatePeers(results)
                }
            }
            browser.stateUpdateHandler = { [weak self] newState in
                guard case .failed(let error) = newState else { return }
                Task { @MainActor [weak self] in
                    self?.state = .failed(error.localizedDescription)
                }
            }
            browser.start(queue: .main)
            self.browser = browser
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        browser?.cancel()
        listener?.cancel()
        pendingIncoming?.cancel()
        wire?.cancel()
        browser = nil
        listener = nil
        pendingIncoming = nil
        wire = nil
        endpoints.removeAll()
        peers.removeAll()
        secureListenerActive = false
        pairingCode = nil
        remoteDeviceName = "EhViewer"
        localApproved = false
        peerApproved = false
        localSyncRequested = false
        localSyncStartSent = false
        peerSyncRequested = false
        resumeLocalSyncConfirmationWaiter()
        localManifest = nil
        localRecords.removeAll()
        remoteManifest = nil
        currentPlan = nil
        currentPreview = nil
        state = .idle
    }

    public func connect(to peer: DeviceSyncPeer) {
        guard let endpoint = endpoints[peer.id] else {
            state = .failed(DeviceSyncError.notReady.localizedDescription)
            return
        }
        guard wire == nil else {
            state = .failed(DeviceSyncError.anotherConnectionPending.localizedDescription)
            return
        }
        isInitiator = true
        pairingCode = Self.makePairingCode()
        localApproved = true
        state = .connecting
        pairingExpiryTask = makePairingExpiryTask()
        let code = pairingCode!
        sessionTask = Task { @MainActor [weak self] in
            do {
                try await self?.runInitiatorConnection(to: endpoint, code: code)
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Accepts the one pending inbound connection after the user enters the
    /// six-digit code. TLS is not started before this method succeeds.
    public func acceptPairing(code: String) {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            state = .failed(DeviceSyncError.invalidPairingCode.localizedDescription)
            return
        }
        guard pendingIncoming != nil else {
            state = .failed(DeviceSyncError.notReady.localizedDescription)
            return
        }
        guard pairingAttempts < 5 else {
            state = .failed(DeviceSyncError.tooManyPairingAttempts.localizedDescription)
            pendingIncoming?.cancel()
            return
        }
        pairingAttempts += 1
        isInitiator = false
        pairingCode = nil
        localApproved = false
        state = .connecting
        pendingIncoming?.cancel()
        pendingIncoming = nil
        pairingExpiryTask?.cancel()
        listener?.cancel()
        listener = nil
        do {
            secureListenerActive = true
            try installListener(using: makeListenerParameters(code: code))
            pairingExpiryTask = makePairingExpiryTask()
        } catch {
            secureListenerActive = false
            fail(error)
        }
    }

    /// Confirms the remote device after the code-verified TLS channel is ready.
    public func confirmConnection() {
        guard let wire, isInitiator == false else { return }
        localApproved = true
        sessionTask?.cancel()
        sessionTask = Task { @MainActor [weak self, wire] in
            do {
                try await wire.send(.approval, payload: Data())
                try await self?.runReceiverSession(wire: wire)
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error)
            }
        }
    }

    public func confirmSync() {
        guard let wire, currentPlan != nil, localSyncRequested == false else { return }
        localSyncRequested = true
        Task { @MainActor [weak self, wire] in
            do {
                try await wire.send(.syncStart, payload: Data())
                guard let self, self.wire === wire else { return }
                self.localSyncStartSent = true
                self.resumeLocalSyncConfirmationWaiter()
            } catch is CancellationError {
                return
            } catch {
                self?.fail(error)
            }
        }
    }

    public func cancelSync() {
        try? wire?.sendSynchronously(.cancel, payload: Data())
        stop()
    }

    private func handleIncoming(_ connection: NWConnection) {
        guard pendingIncoming == nil, wire == nil else {
            connection.cancel()
            return
        }
        pendingIncoming = connection
        if secureListenerActive {
            let wire = DeviceSyncWireConnection(connection: connection)
            self.wire = wire
            self.pendingIncoming = nil
            sessionTask = Task { @MainActor [weak self, wire] in
                do {
                    try await wire.start()
                    guard let self else { return }
                    let hello: DeviceSyncHello = try self.decodeControl(try await wire.receivePayload(expected: .hello))
                    guard hello.protocolVersion == Self.protocolVersion else {
                        throw DeviceSyncError.unexpectedMessage
                    }
                    self.remoteDeviceName = hello.deviceName
                    self.state = .awaitingConnectionConfirmation
                    // The receiver must explicitly call confirmConnection before
                    // any manifest is exchanged.
                } catch is CancellationError {
                    return
                } catch {
                    self?.fail(error)
                }
            }
        } else {
            pairingAttempts = 0
            state = .awaitingPairingCode
            pairingExpiryTask = makePairingExpiryTask()
        }
    }

    private func updatePeers(_ results: Set<NWBrowser.Result>) {
        var nextEndpoints = [String: NWEndpoint]()
        var nextPeers = [DeviceSyncPeer]()
        for result in results {
            guard isLocalService(result) == false else { continue }
            let id = result.endpoint.debugDescription
            nextEndpoints[id] = result.endpoint
            let name: String
            if case let .service(serviceName, _, _, _) = result.endpoint {
                name = serviceName.isEmpty ? "EhViewer" : serviceName
            } else {
                name = "EhViewer"
            }
            nextPeers.append(DeviceSyncPeer(id: id, displayName: name))
        }
        endpoints = nextEndpoints
        peers = nextPeers.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func isLocalService(_ result: NWBrowser.Result) -> Bool {
        guard case let .bonjour(txtRecord) = result.metadata,
              case let .string(instanceID) = txtRecord.getEntry(for: Self.serviceInstanceTXTKey) else {
            return false
        }
        return instanceID == serviceInstanceID
    }

    private func installListener(using parameters: NWParameters) throws {
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(
            name: localDeviceName,
            type: Self.serviceType,
            txtRecord: NWTXTRecord([Self.serviceInstanceTXTKey: serviceInstanceID])
        )
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.handleIncoming(connection)
            }
        }
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            guard case .failed(let error) = newState else { return }
            Task { @MainActor [weak self, weak listener] in
                guard let self, self.listener === listener else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func runInitiatorConnection(to endpoint: NWEndpoint, code: String) async throws {
        var lastError: Error = DeviceSyncError.connectionTimeout
        for attempt in 0..<60 {
            try Task.checkCancellation()
            let connection = try makeConnection(to: endpoint, code: code)
            let candidateWire = DeviceSyncWireConnection(connection: connection)
            wire = candidateWire
            do {
                try await candidateWire.start(timeout: .seconds(4))
                try await candidateWire.send(.hello, payload: try encodeControl(DeviceSyncHello(
                    protocolVersion: Self.protocolVersion,
                    deviceName: localDeviceName
                )))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                candidateWire.cancel()
                wire = nil
                guard attempt < 59 else { throw lastError }
                try await Task.sleep(for: .milliseconds(500))
                continue
            }
            state = .awaitingRemoteConfirmation
            try await waitForApproval(wire: candidateWire)
            try await runInitiatorSession(wire: candidateWire)
            return
        }
        throw lastError
    }

    private func makeConnection(to endpoint: NWEndpoint, code: String) throws -> NWConnection {
        NWConnection(to: endpoint, using: try makeClientParameters(code: code))
    }

    private func waitForApproval(wire: DeviceSyncWireConnection) async throws {
        let message = try await wire.receive()
        guard message.type == .approval else {
            throw DeviceSyncError.peerRejected
        }
        peerApproved = true
    }

    private func runInitiatorSession(wire: DeviceSyncWireConnection) async throws {
        guard peerApproved else { throw DeviceSyncError.peerRejected }
        let (manifest, records) = try await makeLocalManifest()
        localManifest = manifest
        localRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        try await wire.send(.manifest, payload: try encodeControl(manifest))
        let remote: DeviceSyncManifest = try decodeControl(try await wire.receivePayload(expected: .manifest))
        try await preparePreview(local: manifest, remote: remote)
        try await waitForPeerSyncStart(wire: wire)
        try await runTransfer(wire: wire)
    }

    private func runReceiverSession(wire: DeviceSyncWireConnection) async throws {
        guard localApproved else { throw DeviceSyncError.peerRejected }
        let remote: DeviceSyncManifest = try decodeControl(try await wire.receivePayload(expected: .manifest))
        let (manifest, records) = try await makeLocalManifest()
        localManifest = manifest
        localRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        try await wire.send(.manifest, payload: try encodeControl(manifest))
        try await preparePreview(local: manifest, remote: remote)
        try await waitForPeerSyncStart(wire: wire)
        try await runTransfer(wire: wire)
    }

    private func preparePreview(local: DeviceSyncManifest, remote: DeviceSyncManifest) async throws {
        let plan = DeviceSyncReconciler.plan(local: local, remote: remote)
        currentPlan = plan
        remoteManifest = remote
        let preview = DeviceSyncPreview(plan: plan)
        currentPreview = preview
        state = .awaitingSyncConfirmation(preview)
    }

    private func waitForPeerSyncStart(wire: DeviceSyncWireConnection) async throws {
        if peerSyncRequested == false {
            let message = try await wire.receive()
            guard message.type == .syncStart else {
                if message.type == .cancel { throw CancellationError() }
                throw DeviceSyncError.unexpectedMessage
            }
            peerSyncRequested = true
        }
        await waitForLocalSyncConfirmation()
        try Task.checkCancellation()
    }

    private func waitForLocalSyncConfirmation() async {
        guard localSyncStartSent == false else { return }
        await withCheckedContinuation { continuation in
            if self.localSyncStartSent {
                continuation.resume()
            } else {
                self.localSyncConfirmationWaiter = continuation
            }
        }
    }

    private func resumeLocalSyncConfirmationWaiter() {
        localSyncConfirmationWaiter?.resume()
        localSyncConfirmationWaiter = nil
    }

    private func runTransfer(wire: DeviceSyncWireConnection) async throws {
        guard let plan = currentPlan else { throw DeviceSyncError.notReady }
        state = .syncing(DeviceSyncProgress(
            completedPages: 0,
            totalPages: plan.sendPages.count + plan.receivePages.count,
            completedBytes: 0,
            totalBytes: plan.sendBytes + plan.receiveBytes
        ))
        if isInitiator {
            try await sendPlannedData(plan: plan, wire: wire)
            try await receivePlannedData(plan: plan, wire: wire)
        } else {
            try await receivePlannedData(plan: plan, wire: wire)
            try await sendPlannedData(plan: plan, wire: wire)
        }

        let (finalManifest, finalRecords) = try await makeLocalManifest()
        localManifest = finalManifest
        localRecords = Dictionary(uniqueKeysWithValues: finalRecords.map { ($0.stable.key, $0) })
        try await reconcileLocalDownloadState(manifest: finalManifest, records: finalRecords)
        try await wire.send(.manifest, payload: try encodeControl(finalManifest))
        let peerFinal: DeviceSyncManifest = try decodeControl(try await wire.receivePayload(expected: .manifest))
        let finalPlan = DeviceSyncReconciler.plan(local: finalManifest, remote: peerFinal)
        if finalPlan.receiveGalleries.isEmpty && finalPlan.sendGalleries.isEmpty
            && finalPlan.receivePages.isEmpty && finalPlan.sendPages.isEmpty
            && finalPlan.receiveMetadata.isEmpty && finalPlan.sendMetadata.isEmpty {
            state = .completed
        } else {
            currentPlan = finalPlan
            state = .awaitingSyncConfirmation(DeviceSyncPreview(plan: finalPlan))
        }
    }

    private func sendPlannedData(plan: DeviceSyncPlan, wire: DeviceSyncWireConnection) async throws {
        let keys = Set(plan.sendMetadata)
        let records = try await persistence.galleryTransferRecords(for: keys)
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        for key in plan.sendMetadata {
            guard let record = recordsByKey[key] else { throw DeviceSyncError.transferNotPlanned }
            try await wire.send(.metadata, payload: try encodeControl(record))
        }
        for page in plan.sendPages {
            try await sendPage(page, wire: wire)
        }
        try await wire.send(.transferFinished, payload: Data())
    }

    private func receivePlannedData(plan: DeviceSyncPlan, wire: DeviceSyncWireConnection) async throws {
        let expectedPages = Dictionary(uniqueKeysWithValues: plan.receivePages.map { ($0.id, $0) })
        var receivedPages = Set<String>()
        var receivedMetadata = Set<GalleryKey>()
        while true {
            let message = try await wire.receive()
            switch message.type {
            case .metadata:
                let record: GalleryTransferRecord = try decodeControl(message.payload)
                guard plan.receiveMetadata.contains(record.stable.key), receivedMetadata.insert(record.stable.key).inserted else {
                    throw DeviceSyncError.transferNotPlanned
                }
                guard record.dynamic.map({ $0.key == record.stable.key }) ?? true else {
                    throw DeviceSyncError.transferNotPlanned
                }
                try await persistence.mergeDeviceSyncMetadata(record)
                // Read back the merged record. The incoming record may have
                // been combined with fields already stored locally; using the
                // pre-merge value for the following page would otherwise be
                // able to overwrite equal-timestamp fields again.
                let mergedRecord = try await persistence.galleryTransferRecords(for: [record.stable.key]).first
                    ?? record
                localRecords[record.stable.key] = mergedRecord
                try await persistence.prepareDeviceSyncDownload(mergedRecord, pageIndexes: [])
            case .pageHeader:
                let header: DeviceSyncPageHeader = try decodeControl(message.payload)
                guard let expected = expectedPages[header.id], receivedPages.insert(header.id).inserted,
                      expected.key == header.key,
                      expected.byteCount == header.byteCount else {
                    throw DeviceSyncError.transferNotPlanned
                }
                let record = try await transferRecord(for: header.key)
                try await persistence.prepareDeviceSyncDownload(record, pageIndexes: [header.pageIndex])
                let receiveHandle = try await files.beginReceive(
                    for: header.key,
                    pageIndex: header.pageIndex,
                    expectedByteCount: header.byteCount,
                    expectedSHA256: header.sha256
                )
                do {
                    try await wire.receiveExactly(header.byteCount) { chunk in
                        try await self.files.appendReceiveChunk(chunk, to: receiveHandle)
                    }
                    _ = try await files.finishReceive(receiveHandle)
                    try await persistence.markDownloadPageCompleted(
                        for: header.key,
                        pageIndex: header.pageIndex,
                        bytes: header.byteCount
                    )
                    try await wire.expect(.pageFinished)
                } catch {
                    try? await files.discardReceive(receiveHandle)
                    throw error
                }
                updateProgress(completedPage: header.byteCount)
            case .transferFinished:
                guard receivedPages == Set(expectedPages.keys) else {
                    throw DeviceSyncError.transferNotPlanned
                }
                return
            case .cancel:
                throw CancellationError()
            default:
                throw DeviceSyncError.unexpectedMessage
            }
        }
    }

    private func sendPage(_ page: DeviceSyncPageTransfer, wire: DeviceSyncWireConnection) async throws {
        let hasher = PageHashAccumulator()
        try await files.readPageChunks(for: page.key, pageIndex: page.pageIndex, chunkSize: Self.pageChunkBytes) { chunk in
            try Task.checkCancellation()
            await hasher.update(data: chunk)
        }
        let (hashedBytes, digest) = await hasher.finalize()
        guard hashedBytes == page.byteCount else { throw DeviceSyncError.transferNotPlanned }
        let header = DeviceSyncPageHeader(
            key: page.key,
            pageIndex: page.pageIndex,
            byteCount: page.byteCount,
            sha256: digest
        )
        try await wire.send(.pageHeader, payload: try encodeControl(header))
        let sentBytes = PageByteCounter()
        try await files.readPageChunks(for: page.key, pageIndex: page.pageIndex, chunkSize: Self.pageChunkBytes) { chunk in
            await sentBytes.add(chunk.count)
            try await wire.sendRaw(chunk)
        }
        guard await sentBytes.value == page.byteCount else { throw DeviceSyncError.transferNotPlanned }
        try await wire.send(.pageFinished, payload: Data())
    }

    private func transferRecord(for key: GalleryKey) async throws -> GalleryTransferRecord {
        if let record = localRecords[key] { return record }
        guard let record = try await persistence.galleryTransferRecords(for: [key]).first else {
            throw DeviceSyncError.transferNotPlanned
        }
        localRecords[key] = record
        return record
    }

    private func makeLocalManifest() async throws -> (DeviceSyncManifest, [GalleryTransferRecord]) {
        let records = try await persistence.downloadedGalleryTransferRecords()
        var pagesByGallery = [GalleryKey: [DeviceSyncPageEntry]]()
        for record in records {
            let entries = await files.localPageEntries(for: record.stable.key).compactMap { entry in
                try? DeviceSyncPageEntry(pageIndex: entry.pageIndex, byteCount: entry.byteCount)
            }
            pagesByGallery[record.stable.key] = entries
        }
        return (try DeviceSyncManifest(records: records, pagesByGallery: pagesByGallery), records)
    }

    /// Synchronizes the download-job view with the same validated media set
    /// used by the final Manifest. This covers pages that were already local
    /// and therefore were not part of this transfer round.
    private func reconcileLocalDownloadState(
        manifest: DeviceSyncManifest,
        records: [GalleryTransferRecord]
    ) async throws {
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        for gallery in manifest.galleries {
            guard let record = recordsByKey[gallery.key] else { continue }
            try await persistence.prepareDeviceSyncDownload(
                record,
                pageIndexes: Set(gallery.pages.map(\.pageIndex))
            )
            for page in gallery.pages {
                try await persistence.markDownloadPageCompleted(
                    for: gallery.key,
                    pageIndex: page.pageIndex,
                    bytes: page.byteCount
                )
            }
        }
    }

    private func updateProgress(completedPage: Int64) {
        guard case let .syncing(progress) = state else { return }
        state = .syncing(DeviceSyncProgress(
            completedPages: progress.completedPages + 1,
            totalPages: progress.totalPages,
            completedBytes: progress.completedBytes + completedPage,
            totalBytes: progress.totalBytes
        ))
    }

    private func fail(_ error: Error) {
        if error is CancellationError { return }
        resumeLocalSyncConfirmationWaiter()
        sessionTask?.cancel()
        state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        wire?.cancel()
    }

    private func makePairingExpiryTask() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(120))
                guard let self, self.state == .awaitingPairingCode || self.state == .connecting else { return }
                self.pendingIncoming?.cancel()
                self.wire?.cancel()
                self.sessionTask?.cancel()
                self.pairingCode = nil
                self.state = .failed(DeviceSyncError.pairingExpired.localizedDescription)
            } catch {
                return
            }
        }
    }

    private static func makePairingCode() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    private func makeClientParameters(code: String) throws -> NWParameters {
        try makeTLSParameters(code: code)
    }

    private func makeListenerParameters(code: String?) throws -> NWParameters {
        guard let code else {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            return parameters
        }
        return try makeTLSParameters(code: code)
    }

    private func makeTLSParameters(code: String) throws -> NWParameters {
        let options = NWProtocolTLS.Options()
        let securityOptions = options.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv12)
        // TLS 1.3 PSK negotiation is not consistently available through
        // Network.framework on Apple platforms. Use the standard TLS 1.2 PSK
        // suite for a deterministic iOS/macOS pairing handshake.
        guard let pskCipherSuite = tls_ciphersuite_t(rawValue: 0x00A8) else {
            throw DeviceSyncError.network("当前系统不支持 TLS-PSK。")
        }
        sec_protocol_options_append_tls_ciphersuite(securityOptions, pskCipherSuite)
        addPSK(code: code, to: securityOptions)
        let parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        return parameters
    }

    private func addPSK(code: String, to options: sec_protocol_options_t) {
        let identity = Data("EhViewer".utf8)
        sec_protocol_options_add_pre_shared_key(options, Self.dispatchData(Self.psk(for: code)), Self.dispatchData(identity))
    }

    private static func psk(for code: String) -> Data {
        Data(SHA256.hash(data: Data("EhViewer-\(code)".utf8)))
    }

    private static func dispatchData(_ data: Data) -> __DispatchData {
        let dispatchData: DispatchData = data.withUnsafeBytes { raw in
            DispatchData(bytes: raw)
        }
        return dispatchData as __DispatchData
    }

    private func encodeControl<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= Self.maximumControlFrameBytes else { throw DeviceSyncError.controlFrameTooLarge }
        return data
    }

    private func decodeControl<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private static func makeDeviceName() -> String {
        #if os(iOS)
        let candidate = UIDevice.current.name
        #elseif os(macOS)
        let candidate = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        let candidate = ProcessInfo.processInfo.hostName
        #endif
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "EhViewer" }

        var result = ""
        for scalar in trimmed.unicodeScalars {
            let next = result + String(scalar)
            guard next.utf8.count <= 63 else { break }
            result = next
        }
        return result.isEmpty ? "EhViewer" : result
    }
}

private struct DeviceSyncPageHeader: Codable, Sendable {
    let key: GalleryKey
    let pageIndex: Int
    let byteCount: Int64
    let sha256: Data

    var id: String { "\(key.id)-\(pageIndex)" }
}

private struct DeviceSyncHello: Codable, Sendable {
    let protocolVersion: Int
    let deviceName: String
}

private actor PageHashAccumulator {
    private var hasher = SHA256()
    private var byteCount: Int64 = 0

    func update(data: Data) {
        hasher.update(data: data)
        byteCount += Int64(data.count)
    }

    func finalize() -> (Int64, Data) {
        (byteCount, Data(hasher.finalize()))
    }
}

private actor PageByteCounter {
    private(set) var value: Int64 = 0

    func add(_ byteCount: Int) {
        value += Int64(byteCount)
    }
}

/// Network.framework state callbacks can deliver more than one terminal
/// transition. This lock makes the checked continuation resume exactly once.
private final class StartContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func succeed(_ continuation: CheckedContinuation<Void, Error>) {
        guard claim() else { return }
        continuation.resume(returning: ())
    }

    func fail(_ continuation: CheckedContinuation<Void, Error>, error: Error) {
        guard claim() else { return }
        continuation.resume(throwing: error)
    }

    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard resumed == false else { return false }
        resumed = true
        return true
    }
}

@MainActor
private final class DeviceSyncWireConnection {
    private static let maximumRawChunk = 64 * 1024
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "EhViewer.DeviceSync.Connection")
    private var started = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() async throws {
        guard started == false else { return }
        started = true
        let gate = StartContinuationGate()
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self.connection.stateUpdateHandler = nil
                        gate.succeed(continuation)
                    case let .failed(error):
                        self.connection.stateUpdateHandler = nil
                        gate.fail(continuation, error: DeviceSyncError.network(error.localizedDescription))
                    case .cancelled:
                        self.connection.stateUpdateHandler = nil
                        gate.fail(continuation, error: CancellationError())
                    default:
                        break
                    }
                }
            }
            connection.start(queue: queue)
        }
    }

    func start(timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.start() }
            group.addTask {
                try await Task.sleep(for: timeout)
                await self.cancel()
                throw DeviceSyncError.connectionTimeout
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    func send(_ type: DeviceSyncMessageType, payload: Data) async throws {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        try await sendRaw(frame)
    }

    func sendSynchronously(_ type: DeviceSyncMessageType, payload: Data) throws {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: DeviceSyncError.network(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    func receive() async throws -> DeviceSyncWireFrame {
        let lengthData = try await receiveExactlyData(count: 4)
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard length <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        return try DeviceSyncWireFrame.decode(try await receiveExactlyData(count: Int(length)))
    }

    func receivePayload(expected: DeviceSyncMessageType) async throws -> Data {
        let message = try await receive()
        guard message.type == expected else { throw DeviceSyncError.unexpectedMessage }
        return message.payload
    }

    func expect(_ expected: DeviceSyncMessageType) async throws {
        let message = try await receive()
        guard message.type == expected else { throw DeviceSyncError.unexpectedMessage }
    }

    func receiveExactly(_ count: Int64, consume: (Data) async throws -> Void) async throws {
        var remaining = count
        while remaining > 0 {
            let chunk = try await receiveChunk(maximumLength: min(Self.maximumRawChunk, Int(remaining)))
            guard chunk.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            remaining -= Int64(chunk.count)
            try await consume(chunk)
        }
    }

    func cancel() {
        connection.cancel()
    }

    private func receiveExactlyData(count: Int) async throws -> Data {
        guard count >= 0, count <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let chunk = try await receiveChunk(maximumLength: count - result.count)
            guard chunk.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            result.append(chunk)
        }
        return result
    }

    private func receiveChunk(maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: max(1, maximumLength)
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: DeviceSyncError.network(error.localizedDescription))
                } else if let data, data.isEmpty == false {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: DeviceSyncError.network("连接已关闭"))
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

private enum DeviceSyncMessageType: String, Codable, Sendable {
    case hello
    case approval
    case manifest
    case metadata
    case pageHeader
    case pageFinished
    case transferFinished
    case syncStart
    case cancel
    case error
}

private struct DeviceSyncWireFrame: Codable, Sendable {
    let type: DeviceSyncMessageType
    let payload: Data

    init(type: DeviceSyncMessageType, payload: Data) throws {
        self.type = type
        self.payload = payload
    }

    func encoded() throws -> Data {
        let body = try JSONEncoder().encode(self)
        guard body.count <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        var length = UInt32(body.count).bigEndian
        var result = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        result.append(body)
        return result
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}
