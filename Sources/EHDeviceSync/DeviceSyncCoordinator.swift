/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

@preconcurrency import Network
import CryptoKit
import Foundation
import Observation
import OSLog
import Security
#if os(iOS)
import UIKit
#endif
import EHDomain
import EHPersistence
import EHDownloads

private let deviceSyncLogger = Logger(subsystem: "com.liao.ehviewer", category: "device-sync")

public enum DeviceSyncError: Error, LocalizedError, Sendable, Equatable {
    case notReady
    case invalidPairingCode
    case pairingExpired
    case tooManyPairingAttempts
    case anotherConnectionPending
    case connectionTimeout
    case idleTimeout
    case peerCancelled
    case appEnteredBackground
    case protocolVersionMismatch(local: Int, remote: Int)
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
        case .idleTimeout:
            String(localized: "设备同步超过 30 秒没有收到数据，连接已中断。")
        case .peerCancelled:
            String(localized: "对方取消了设备同步。")
        case .appEnteredBackground:
            String(localized: "应用进入后台，设备同步已安全中断。")
        case let .protocolVersionMismatch(local, remote):
            String(localized: "设备同步协议版本不匹配（本机 \(local)，对方 \(remote)）。")
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

public enum DeviceSyncPhase: String, Hashable, Sendable {
    case generatingManifest
    case waitingForConfirmation
    case sending
    case receiving
    case verifying
    case committing
    case comparingResults
}

public enum DeviceSyncDirection: String, Hashable, Sendable {
    case sending
    case receiving
}

public struct DeviceSyncProgress: Hashable, Sendable {
    public let phase: DeviceSyncPhase
    public let direction: DeviceSyncDirection?
    public let sentPages: Int
    public let totalSendPages: Int
    public let receivedPages: Int
    public let totalReceivePages: Int
    public let sentBytes: Int64
    public let totalSendBytes: Int64
    public let receivedBytes: Int64
    public let totalReceiveBytes: Int64
    public let completedGalleries: Int
    public let totalGalleries: Int
    public let currentGalleryTitle: String?
    public let currentPageIndex: Int?
    public let bytesPerSecond: Double?
    public let estimatedRemainingSeconds: TimeInterval?

    public var completedPages: Int { sentPages + receivedPages }
    public var totalPages: Int { totalSendPages + totalReceivePages }
    public var completedBytes: Int64 { sentBytes + receivedBytes }
    public var totalBytes: Int64 { totalSendBytes + totalReceiveBytes }

    public var fraction: Double? {
        guard totalBytes > 0 else { return totalPages > 0 ? Double(completedPages) / Double(totalPages) : nil }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

public struct DeviceSyncInterruption: Hashable, Sendable {
    public let reason: String
    public let completedGalleryCount: Int
    public let rolledBackGalleryCount: Int
}

public struct DeviceSyncResult: Hashable, Sendable {
    public let sentGalleryCount: Int
    public let receivedGalleryCount: Int
    public let sentPageCount: Int
    public let receivedPageCount: Int
    public let sentBytes: Int64
    public let receivedBytes: Int64
}

public struct DeviceSyncRecoveryResult: Hashable, Sendable {
    public let completedGalleryCount: Int
    public let rolledBackGalleryCount: Int

    public var recoveredAnything: Bool {
        completedGalleryCount > 0 || rolledBackGalleryCount > 0
    }
}

public enum DeviceSyncState: Sendable, Equatable {
    case idle
    case discovering
    case awaitingPairingCode
    case connecting
    case awaitingRemoteConfirmation
    case awaitingConnectionConfirmation
    case preparing(DeviceSyncPhase)
    case awaitingSyncConfirmation(DeviceSyncPreview)
    case syncing(DeviceSyncProgress)
    case interrupted(DeviceSyncInterruption)
    case cancelled(DeviceSyncResult)
    case completed(DeviceSyncResult)
    case failed(String)
}

@MainActor
@Observable
public final class DeviceSyncCoordinator {
    nonisolated public static let serviceType = "_ehviewer-sync._tcp"
    nonisolated public static let protocolVersion = 3
    nonisolated public static let maximumControlFrameBytes = 4 * 1024 * 1024
    nonisolated public static let pageChunkBytes = 256 * 1024
    nonisolated public static let maximumPageChunkBytes = 512 * 1024
    nonisolated public static let sendWindowBytes = 4 * 1024 * 1024
    nonisolated public static let progressUpdateBytes = 1 * 1024 * 1024
    private static let serviceInstanceTXTKey = "ehviewer-instance"

    public let persistence: PersistenceStore
    public let files: DownloadFileStore

    public private(set) var state: DeviceSyncState = .idle
    public private(set) var peers: [DeviceSyncPeer] = []
    public private(set) var pairingCode: String?
    public private(set) var localDeviceName: String
    public private(set) var remoteDeviceName = "EhViewer"
    public private(set) var transportDescription: String?

    /// Opaque per-coordinator identifier used only to filter this process's
    /// own Bonjour advertisement from browser results. It is not user data.
    private let serviceInstanceID = UUID().uuidString
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var endpoints: [String: NWEndpoint] = [:]
    private var pendingIncoming: NWConnection?
    private var wire: DeviceSyncWireConnection?
    private var sessionTask: Task<Void, Never>?
    private var interruptionFinalizationTask: Task<Void, Never>?
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
    private let progressClock = ContinuousClock()
    private var progressStartedAt: ContinuousClock.Instant?
    private var progressLastSampleAt: ContinuousClock.Instant?
    private var progressLastPublishAt: ContinuousClock.Instant?
    private var progressLastSampleBytes: Int64 = 0
    private var progressSpeed: Double?
    private var progressCompletedGalleries = 0
    private var progressRolledBackGalleries = 0
    private var progressSentPages = 0
    private var progressReceivedPages = 0
    private var progressSentBytes: Int64 = 0
    private var progressReceivedBytes: Int64 = 0
    private var progressPlan: DeviceSyncPlan?
    private var progressPhase: DeviceSyncPhase = .generatingManifest
    private var progressDirection: DeviceSyncDirection?
    private var progressGalleryTitle: String?
    private var progressPageIndex: Int?
    private var activeTransaction: DeviceSyncTransactionJournal?
    private var activeTransactionURL: URL?
    private var activeTransactionLogHandle: FileHandle?
    #if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    public init(persistence: PersistenceStore, files: DownloadFileStore) {
        self.persistence = persistence
        self.files = files
        self.localDeviceName = Self.makeDeviceName()
    }

    nonisolated public static func preferredPageChunkBytes(forPageByteCount byteCount: Int64) -> Int {
        byteCount >= 8 * 1024 * 1024 ? maximumPageChunkBytes : pageChunkBytes
    }

    /// Resolves the small transaction journals left by a force-quit. A
    /// gallery that reached the committing phase is completed idempotently;
    /// an earlier gallery is rolled back using the hashes of this round's
    /// newly-created pages.
    public func recoverInterruptedTransfers() async -> DeviceSyncRecoveryResult {
        let root = Self.transactionRootURL
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return DeviceSyncRecoveryResult(completedGalleryCount: 0, rolledBackGalleryCount: 0)
        }
        var completed = 0
        var rolledBack = 0
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let journal = Self.decodeTransactionJournal(data) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            if journal.phase == .committing, let record = journal.record {
                do {
                    let localPages = Dictionary(uniqueKeysWithValues: await files.localPageEntries(for: journal.key)
                        .map { ($0.pageIndex, $0.byteCount) })
                    guard journal.pages.allSatisfy({ localPages[$0.pageIndex] == $0.byteCount }) else {
                        throw DeviceSyncError.transferNotPlanned
                    }
                    try await persistence.commitDeviceSyncGallery(
                        record,
                        completedPages: Dictionary(
                            journal.pages.map { ($0.pageIndex, $0.byteCount) },
                            uniquingKeysWith: { first, _ in first }
                        )
                    )
                    completed += 1
                    try? fileManager.removeItem(at: url)
                    continue
                } catch {
                    // Fall through to rollback. A partially completed
                    // persistence transaction is safe to merge again later,
                    // but no page from this interrupted gallery may remain.
                }
            }
            for page in journal.pages {
                try? await files.rollbackReceivedPage(
                    for: journal.key,
                    pageIndex: page.pageIndex,
                    sha256: page.sha256
                )
            }
            rolledBack += 1
            try? fileManager.removeItem(at: url)
        }
        return DeviceSyncRecoveryResult(
            completedGalleryCount: completed,
            rolledBackGalleryCount: rolledBack
        )
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
        interruptionFinalizationTask?.cancel()
        interruptionFinalizationTask = nil
#if os(iOS)
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
#endif
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
        transportDescription = nil
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
        progressPlan = nil
        progressStartedAt = nil
        progressLastSampleAt = nil
        progressLastPublishAt = nil
        progressSpeed = nil
        progressCompletedGalleries = 0
        progressRolledBackGalleries = 0
        progressSentPages = 0
        progressReceivedPages = 0
        progressSentBytes = 0
        progressReceivedBytes = 0
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
        let cancellationResult = currentPlan.map(result(for:)) ?? DeviceSyncResult(
            sentGalleryCount: 0,
            receivedGalleryCount: 0,
            sentPageCount: 0,
            receivedPageCount: 0,
            sentBytes: 0,
            receivedBytes: 0
        )
        try? wire?.sendSynchronously(.cancel, payload: Data())
        stop()
        state = .cancelled(cancellationResult)
        Task { @MainActor [weak self] in
            _ = await self?.rollbackActiveTransaction()
        }
    }

    public func interruptForBackground() {
        guard wire != nil || sessionTask != nil else { return }
        #if os(iOS)
        if backgroundTaskIdentifier == .invalid {
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "EhViewer.DeviceSync.Cleanup")
        }
        #endif
        try? wire?.sendSynchronously(.cancel, payload: Data())
        sessionTask?.cancel()
        wire?.cancel()
        pendingIncoming?.cancel()
        browser?.cancel()
        listener?.cancel()
        sessionTask = nil
        wire = nil
        pendingIncoming = nil
        browser = nil
        listener = nil
        finalizeInterruption(reason: DeviceSyncError.appEnteredBackground.localizedDescription)
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
                    self.recordTransportDescription(await wire.transportDescription())
                    let hello: DeviceSyncHello = try self.decodeControl(try await wire.receivePayload(expected: .hello))
                    guard hello.protocolVersion == Self.protocolVersion else {
                        throw DeviceSyncError.protocolVersionMismatch(
                            local: Self.protocolVersion,
                            remote: hello.protocolVersion
                        )
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
                recordTransportDescription(await candidateWire.transportDescription())
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
        state = .preparing(.generatingManifest)
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
        state = .preparing(.generatingManifest)
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
                if message.type == .cancel { throw DeviceSyncError.peerCancelled }
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
        beginProgress(plan: plan)
        if isInitiator {
            try await sendPlannedData(plan: plan, wire: wire)
            try await receivePlannedData(plan: plan, wire: wire)
        } else {
            try await receivePlannedData(plan: plan, wire: wire)
            try await sendPlannedData(plan: plan, wire: wire)
        }

        publishProgress(phase: .verifying, force: true)
        // Each device validates its own files and download state locally. Do
        // not exchange a second manifest here: the transport phase already
        // exchanged per-gallery results, and waiting for a peer final manifest
        // can leave both devices blocked when either side has already failed.
        _ = try await verifyLocalTransferState()
        state = .completed(result(for: plan))
    }

    private func sendPlannedData(plan: DeviceSyncPlan, wire: DeviceSyncWireConnection) async throws {
        let galleryKeys = Set(plan.sendMetadata).union(plan.sendPages.map(\.key))
        let records = try await persistence.galleryTransferRecords(for: galleryKeys)
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        for key in galleryKeys.sorted(by: Self.galleryKeyLessThan) {
            let pages = plan.sendPages.filter { $0.key == key }.sorted { $0.pageIndex < $1.pageIndex }
            let includesMetadata = plan.sendMetadata.contains(key)
            let title = recordsByKey[key]?.stable.title
            publishProgress(
                phase: .sending,
                direction: .sending,
                galleryTitle: title,
                force: true
            )
            try await wire.send(.galleryBegin, payload: try encodeControl(DeviceSyncGalleryBegin(
                key: key,
                pageIndexes: pages.map(\.pageIndex),
                includesMetadata: includesMetadata
            )))
            if includesMetadata {
                guard let record = recordsByKey[key] else { throw DeviceSyncError.transferNotPlanned }
                try await wire.send(.metadata, payload: try encodeControl(record))
            }
            for page in pages {
                try await sendPage(page, title: title, wire: wire)
            }
            let finishFlush = try await wire.enqueue(
                .galleryFinished,
                payload: try encodeControl(DeviceSyncGalleryFinished(key: key))
            )
            addProgressBytes(finishFlush, direction: .sending)
            addProgressBytes(try await wire.flush(), direction: .sending)
            let galleryResult: DeviceSyncGalleryResult = try decodeControl(
                try await wire.receivePayload(expected: .galleryResult)
            )
            let resultIndexes = galleryResult.pageResults.map(\.pageIndex)
            guard galleryResult.key == key,
                  galleryResult.pageResults.allSatisfy({ $0.key == key }),
                  Set(resultIndexes) == Set(pages.map(\.pageIndex)),
                  resultIndexes.count == pages.count else {
                throw DeviceSyncError.unexpectedMessage
            }
            if galleryResult.succeeded {
                guard galleryResult.pageResults.allSatisfy({ $0.succeeded }) else {
                    throw DeviceSyncError.unexpectedMessage
                }
                addCompletedPages(pages.count, direction: .sending)
                progressCompletedGalleries += 1
                publishProgress(phase: .sending, direction: .sending, galleryTitle: title, force: true)
            }
        }
        try await wire.send(.transferFinished, payload: Data())
    }

    private func receivePlannedData(plan: DeviceSyncPlan, wire: DeviceSyncWireConnection) async throws {
        let expectedGalleryKeys = Set(plan.receiveMetadata).union(plan.receivePages.map(\.key))
        var receivedGalleryKeys = Set<GalleryKey>()
        while true {
            let message = try await wire.receive()
            switch message.type {
            case .galleryBegin:
                let begin: DeviceSyncGalleryBegin = try decodeControl(message.payload)
                guard expectedGalleryKeys.contains(begin.key),
                      receivedGalleryKeys.insert(begin.key).inserted,
                      begin.includesMetadata == plan.receiveMetadata.contains(begin.key) else {
                    throw DeviceSyncError.transferNotPlanned
                }
                do {
                    try await receiveGallery(begin, plan: plan, wire: wire)
                } catch {
                    let rolledBack = await rollbackActiveTransaction()
                    if rolledBack { progressRolledBackGalleries += 1 }
                    throw error
                }
            case .transferFinished:
                guard receivedGalleryKeys == expectedGalleryKeys else {
                    throw DeviceSyncError.transferNotPlanned
                }
                return
            case .cancel:
                throw DeviceSyncError.peerCancelled
            default:
                throw DeviceSyncError.unexpectedMessage
            }
        }
    }

    private func receiveGallery(
        _ begin: DeviceSyncGalleryBegin,
        plan: DeviceSyncPlan,
        wire: DeviceSyncWireConnection
    ) async throws {
        let expectedPages = Dictionary(uniqueKeysWithValues: plan.receivePages
            .filter { $0.key == begin.key }
            .map { ($0.pageIndex, $0) })
        guard Set(begin.pageIndexes) == Set(expectedPages.keys),
              begin.pageIndexes.count == expectedPages.count else {
            throw DeviceSyncError.transferNotPlanned
        }
        var incomingRecord: GalleryTransferRecord?
        var receivedIndexes = Set<Int>()
        var validatedPages: [(pageIndex: Int, byteCount: Int64)] = []
        var committedPages: [(pageIndex: Int, byteCount: Int64, sha256: Data)] = []
        var pageResults: [DeviceSyncPageResult] = []
        var galleryFailed = false
        let title = localRecords[begin.key]?.stable.title
        try beginTransaction(for: begin.key, record: localRecords[begin.key])
        publishProgress(
            phase: .receiving,
            direction: .receiving,
            galleryTitle: title,
            force: true
        )

        while true {
            let message = try await wire.receive()
            switch message.type {
            case .metadata:
                let record: GalleryTransferRecord = try decodeControl(message.payload)
                guard begin.includesMetadata,
                      incomingRecord == nil,
                      record.stable.key == begin.key,
                      record.dynamic.map({ $0.key == begin.key }) ?? true else {
                    throw DeviceSyncError.transferNotPlanned
                }
                incomingRecord = record
                try updateActiveTransaction(record: record)
            case .pageHeader:
                let header: DeviceSyncPageHeader = try decodeControl(message.payload)
                guard let expected = expectedPages[header.pageIndex],
                      receivedIndexes.insert(header.pageIndex).inserted,
                      header.key == begin.key,
                      header.byteCount == expected.byteCount else {
                    throw DeviceSyncError.transferNotPlanned
                }
                let receiveHandle: DownloadReceiveHandle?
                let initialErrorMessage: String?
                do {
                    receiveHandle = try await files.beginReceive(
                        for: header.key,
                        pageIndex: header.pageIndex,
                        expectedByteCount: header.byteCount
                    )
                    initialErrorMessage = nil
                } catch {
                    receiveHandle = nil
                    initialErrorMessage = error.localizedDescription
                }
                let pageReceiver = DeviceSyncPageReceiver(
                    files: files,
                    handle: receiveHandle,
                    initialErrorMessage: initialErrorMessage
                )
                publishProgress(
                    phase: .receiving,
                    direction: .receiving,
                    galleryTitle: title,
                    pageIndex: header.pageIndex,
                    force: true
                )
                do {
                    try await wire.receiveExactly(header.byteCount) { chunk in
                        let completedBytes = await pageReceiver.consume(chunk)
                        if completedBytes > 0 {
                            await MainActor.run {
                                self.addProgressBytes(completedBytes, direction: .receiving)
                            }
                        }
                    }
                    let finished: DeviceSyncPageFinished = try decodeControl(
                        try await wire.receivePayload(expected: .pageFinished)
                    )
                    guard finished.key == header.key,
                          finished.pageIndex == header.pageIndex else {
                        throw DeviceSyncError.unexpectedMessage
                    }
                    let outcome = await pageReceiver.finish(expectedSHA256: finished.sha256)
                    addProgressBytes(outcome.trailingProgressBytes, direction: .receiving)
                    let succeeded = outcome.result != nil
                    pageResults.append(DeviceSyncPageResult(
                        key: header.key,
                        pageIndex: header.pageIndex,
                        succeeded: succeeded,
                        message: outcome.errorMessage
                    ))
                    guard let result = outcome.result else {
                        galleryFailed = true
                        continue
                    }
                    validatedPages.append((header.pageIndex, header.byteCount))
                    if case .committed = result {
                        committedPages.append((header.pageIndex, header.byteCount, finished.sha256))
                        try appendActiveTransactionPage(
                            pageIndex: header.pageIndex,
                            byteCount: header.byteCount,
                            sha256: finished.sha256
                        )
                    }
                } catch {
                    await pageReceiver.discard()
                    throw error
                }
            case .galleryFinished:
                let finished: DeviceSyncGalleryFinished = try decodeControl(message.payload)
                guard finished.key == begin.key else { throw DeviceSyncError.unexpectedMessage }
                for missingIndex in Set(expectedPages.keys).subtracting(receivedIndexes).sorted() {
                    pageResults.append(DeviceSyncPageResult(
                        key: begin.key,
                        pageIndex: missingIndex,
                        succeeded: false,
                        message: DeviceSyncError.transferNotPlanned.localizedDescription
                    ))
                }
                if galleryFailed == false {
                    galleryFailed = receivedIndexes != Set(expectedPages.keys)
                        || (begin.includesMetadata && incomingRecord == nil)
                }
                if galleryFailed == false {
                    do {
                        publishProgress(
                            phase: .committing,
                            direction: .receiving,
                            galleryTitle: incomingRecord?.stable.title ?? title,
                            force: true
                        )
                        let record: GalleryTransferRecord
                        if let incomingRecord {
                            record = incomingRecord
                        } else {
                            record = try await transferRecord(for: begin.key)
                        }
                        try markActiveTransactionCommitting(record: record)
                        try await persistence.commitDeviceSyncGallery(
                            record,
                            completedPages: Dictionary(
                                validatedPages.map { ($0.pageIndex, $0.byteCount) },
                                uniquingKeysWith: { first, _ in first }
                            )
                        )
                        let mergedRecord = try await persistence.galleryTransferRecords(for: [begin.key]).first
                            ?? record
                        localRecords[begin.key] = mergedRecord
                        progressCompletedGalleries += 1
                        addCompletedPages(validatedPages.count, direction: .receiving)
                    } catch {
                        galleryFailed = true
                    }
                }
                if galleryFailed {
                    for page in committedPages {
                        try? await files.rollbackReceivedPage(
                            for: begin.key,
                            pageIndex: page.pageIndex,
                            sha256: page.sha256
                        )
                    }
                    progressRolledBackGalleries += 1
                    pageResults = pageResults.map { result in
                        DeviceSyncPageResult(
                            key: result.key,
                            pageIndex: result.pageIndex,
                            succeeded: false,
                            message: result.message ?? String(localized: "画廊未能完整提交，已回滚本轮页面。")
                        )
                    }
                }
                finishActiveTransaction()
                try await wire.send(.galleryResult, payload: try encodeControl(DeviceSyncGalleryResult(
                    key: begin.key,
                    succeeded: galleryFailed == false,
                    pageResults: pageResults.sorted { $0.pageIndex < $1.pageIndex }
                )))
                publishProgress(
                    phase: .receiving,
                    direction: .receiving,
                    galleryTitle: incomingRecord?.stable.title ?? title,
                    force: true
                )
                return
            case .cancel:
                for page in committedPages {
                    try? await files.rollbackReceivedPage(
                        for: begin.key,
                        pageIndex: page.pageIndex,
                        sha256: page.sha256
                    )
                }
                if committedPages.isEmpty == false { progressRolledBackGalleries += 1 }
                finishActiveTransaction()
                throw DeviceSyncError.peerCancelled
            default:
                throw DeviceSyncError.unexpectedMessage
            }
        }
    }

    private func sendPage(
        _ page: DeviceSyncPageTransfer,
        title: String?,
        wire: DeviceSyncWireConnection
    ) async throws {
        let header = DeviceSyncPageHeader(
            key: page.key,
            pageIndex: page.pageIndex,
            byteCount: page.byteCount
        )
        let headerFlush = try await wire.enqueue(.pageHeader, payload: try encodeControl(header))
        addProgressBytes(headerFlush, direction: .sending)
        publishProgress(
            phase: .sending,
            direction: .sending,
            galleryTitle: title,
            pageIndex: page.pageIndex,
            force: true
        )
        let streamResult = try await files.readPageChunksAndHash(
            for: page.key,
            pageIndex: page.pageIndex,
            chunkSize: Self.preferredPageChunkBytes(forPageByteCount: page.byteCount)
        ) { chunk in
            let flushed = try await wire.enqueueRaw(chunk)
            if flushed > 0 {
                await MainActor.run {
                    self.addProgressBytes(flushed, direction: .sending)
                }
            }
        }
        guard streamResult.byteCount == page.byteCount else { throw DeviceSyncError.transferNotPlanned }
        let finishFlush = try await wire.enqueue(.pageFinished, payload: try encodeControl(DeviceSyncPageFinished(
            key: page.key,
            pageIndex: page.pageIndex,
            sha256: streamResult.sha256
        )))
        addProgressBytes(finishFlush, direction: .sending)
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
        var recordsWithMedia: [GalleryTransferRecord] = []
        for record in records {
            let entries = await files.localPageEntries(for: record.stable.key).compactMap { entry in
                try? DeviceSyncPageEntry(pageIndex: entry.pageIndex, byteCount: entry.byteCount)
            }
            guard entries.isEmpty == false else { continue }
            recordsWithMedia.append(record)
            pagesByGallery[record.stable.key] = entries
        }
        return (
            try DeviceSyncManifest(records: recordsWithMedia, pagesByGallery: pagesByGallery),
            recordsWithMedia
        )
    }

    /// Performs the one library-wide validation pass after transport has
    /// stopped. Per-page hash/media checks remain internal commit guards and
    /// never switch the public progress phase away from sending/receiving.
    private func verifyLocalTransferState() async throws -> (DeviceSyncManifest, [GalleryTransferRecord]) {
        let (manifest, records) = try await makeLocalManifest()
        localManifest = manifest
        localRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        try await reconcileLocalDownloadState(manifest: manifest, records: records)
        return (manifest, records)
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
            try await persistence.commitDeviceSyncGallery(
                record,
                completedPages: Dictionary(
                    gallery.pages.map { ($0.pageIndex, $0.byteCount) },
                    uniquingKeysWith: { first, _ in first }
                )
            )
        }
    }

    private func beginProgress(plan: DeviceSyncPlan) {
        progressPlan = plan
        progressStartedAt = progressClock.now
        progressLastSampleAt = progressStartedAt
        progressLastPublishAt = nil
        progressLastSampleBytes = 0
        progressSpeed = nil
        progressCompletedGalleries = 0
        progressRolledBackGalleries = 0
        progressSentPages = 0
        progressReceivedPages = 0
        progressSentBytes = 0
        progressReceivedBytes = 0
        progressPhase = .waitingForConfirmation
        progressDirection = nil
        progressGalleryTitle = nil
        progressPageIndex = nil
        publishProgress(phase: .waitingForConfirmation, force: true)
    }

    private func addProgressBytes(_ byteCount: Int64, direction: DeviceSyncDirection) {
        guard byteCount > 0 else { return }
        switch direction {
        case .sending: progressSentBytes += byteCount
        case .receiving: progressReceivedBytes += byteCount
        }
        publishProgress(phase: direction == .sending ? .sending : .receiving, direction: direction)
    }

    private func addCompletedPages(_ count: Int, direction: DeviceSyncDirection) {
        switch direction {
        case .sending: progressSentPages += count
        case .receiving: progressReceivedPages += count
        }
        publishProgress(phase: direction == .sending ? .sending : .receiving, direction: direction, force: true)
    }

    private func publishProgress(
        phase: DeviceSyncPhase,
        direction: DeviceSyncDirection? = nil,
        galleryTitle: String? = nil,
        pageIndex: Int? = nil,
        force: Bool = false
    ) {
        guard let plan = progressPlan else { return }
        let now = progressClock.now
        progressPhase = phase
        if let direction { progressDirection = direction }
        if let galleryTitle { progressGalleryTitle = galleryTitle }
        if let pageIndex { progressPageIndex = pageIndex }

        let totalTransferred = progressSentBytes + progressReceivedBytes
        if let sampleAt = progressLastSampleAt {
            let sampleSeconds = Self.seconds(from: sampleAt.duration(to: now))
            if sampleSeconds >= 0.25 {
                let delta = totalTransferred - progressLastSampleBytes
                if delta >= 0, sampleSeconds > 0 {
                    let instantaneous = Double(delta) / sampleSeconds
                    progressSpeed = progressSpeed.map { $0 * 0.75 + instantaneous * 0.25 } ?? instantaneous
                }
                progressLastSampleAt = now
                progressLastSampleBytes = totalTransferred
            }
        }

        if force == false,
           let lastPublish = progressLastPublishAt,
           Self.seconds(from: lastPublish.duration(to: now)) < 0.25 {
            return
        }
        progressLastPublishAt = now

        let elapsed = progressStartedAt.map { Self.seconds(from: $0.duration(to: now)) } ?? 0
        let remaining = max(0, plan.sendBytes + plan.receiveBytes - totalTransferred)
        let eta: TimeInterval?
        if (phase == .sending || phase == .receiving),
           elapsed >= 1,
           let speed = progressSpeed,
           speed > 1,
           remaining > 0 {
            eta = Double(remaining) / speed
        } else {
            eta = nil
        }

        state = .syncing(DeviceSyncProgress(
            phase: progressPhase,
            direction: progressDirection,
            sentPages: progressSentPages,
            totalSendPages: plan.sendPages.count,
            receivedPages: progressReceivedPages,
            totalReceivePages: plan.receivePages.count,
            sentBytes: progressSentBytes,
            totalSendBytes: plan.sendBytes,
            receivedBytes: progressReceivedBytes,
            totalReceiveBytes: plan.receiveBytes,
            completedGalleries: progressCompletedGalleries,
            totalGalleries: Set(plan.sendMetadata).union(plan.sendPages.map(\.key))
                .union(plan.receiveMetadata).union(plan.receivePages.map(\.key)).count,
            currentGalleryTitle: progressGalleryTitle,
            currentPageIndex: progressPageIndex,
            bytesPerSecond: progressSpeed,
            estimatedRemainingSeconds: eta
        ))
    }

    private func result(for plan: DeviceSyncPlan) -> DeviceSyncResult {
        DeviceSyncResult(
            sentGalleryCount: Set(plan.sendMetadata).union(plan.sendPages.map(\.key)).count,
            receivedGalleryCount: Set(plan.receiveMetadata).union(plan.receivePages.map(\.key)).count,
            sentPageCount: progressSentPages,
            receivedPageCount: progressReceivedPages,
            sentBytes: progressSentBytes,
            receivedBytes: progressReceivedBytes
        )
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static func galleryKeyLessThan(_ lhs: GalleryKey, _ rhs: GalleryKey) -> Bool {
        if lhs.gid != rhs.gid { return lhs.gid < rhs.gid }
        return lhs.token < rhs.token
    }

    private func beginTransaction(for key: GalleryKey, record: GalleryTransferRecord?) throws {
        let fileManager = FileManager.default
        var root = Self.transactionRootURL
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        let url = root.appendingPathComponent("\(UUID().uuidString).json")
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw DeviceSyncError.transferNotPlanned
        }
        activeTransaction = DeviceSyncTransactionJournal(
            key: key,
            record: record,
            pages: [],
            phase: .receiving
        )
        activeTransactionURL = url
        activeTransactionLogHandle = try FileHandle(forWritingTo: url)
        try appendActiveTransactionEvent(DeviceSyncTransactionEvent(
            kind: .begin,
            key: key,
            record: record,
            page: nil
        ))
    }

    private func updateActiveTransaction(record: GalleryTransferRecord) throws {
        guard var transaction = activeTransaction else { return }
        transaction.record = record
        activeTransaction = transaction
        try appendActiveTransactionEvent(DeviceSyncTransactionEvent(
            kind: .metadata,
            key: nil,
            record: record,
            page: nil
        ))
    }

    private func appendActiveTransactionPage(
        pageIndex: Int,
        byteCount: Int64,
        sha256: Data
    ) throws {
        guard var transaction = activeTransaction else { return }
        let page = DeviceSyncTransactionPage(
            pageIndex: pageIndex,
            byteCount: byteCount,
            sha256: sha256
        )
        transaction.pages.append(page)
        activeTransaction = transaction
        try appendActiveTransactionEvent(DeviceSyncTransactionEvent(
            kind: .page,
            key: nil,
            record: nil,
            page: page
        ))
    }

    private func markActiveTransactionCommitting(record: GalleryTransferRecord) throws {
        guard var transaction = activeTransaction else { return }
        transaction.record = record
        transaction.phase = .committing
        activeTransaction = transaction
        try appendActiveTransactionEvent(DeviceSyncTransactionEvent(
            kind: .committing,
            key: nil,
            record: record,
            page: nil
        ))
        try activeTransactionLogHandle?.synchronize()
    }

    private func appendActiveTransactionEvent(_ event: DeviceSyncTransactionEvent) throws {
        guard let handle = activeTransactionLogHandle else { return }
        var data = try JSONEncoder().encode(event)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    @discardableResult
    private func rollbackActiveTransaction() async -> Bool {
        guard let transaction = activeTransaction else { return false }
        for page in transaction.pages {
            try? await files.rollbackReceivedPage(
                for: transaction.key,
                pageIndex: page.pageIndex,
                sha256: page.sha256
            )
        }
        finishActiveTransaction()
        return transaction.pages.isEmpty == false
    }

    private func finishActiveTransaction() {
        try? activeTransactionLogHandle?.close()
        activeTransactionLogHandle = nil
        if let url = activeTransactionURL {
            try? FileManager.default.removeItem(at: url)
        }
        activeTransaction = nil
        activeTransactionURL = nil
    }

    private nonisolated static func decodeTransactionJournal(_ data: Data) -> DeviceSyncTransactionJournal? {
        if let legacy = try? JSONDecoder().decode(DeviceSyncTransactionJournal.self, from: data) {
            return legacy
        }
        var key: GalleryKey?
        var record: GalleryTransferRecord?
        var pages: [DeviceSyncTransactionPage] = []
        var phase: DeviceSyncTransactionPhase = .receiving
        for line in data.split(separator: 0x0A) {
            guard let event = try? JSONDecoder().decode(DeviceSyncTransactionEvent.self, from: Data(line)) else {
                continue
            }
            switch event.kind {
            case .begin:
                key = event.key
                record = event.record
            case .metadata:
                if let nextRecord = event.record { record = nextRecord }
            case .page:
                if let page = event.page { pages.append(page) }
            case .committing:
                if let nextRecord = event.record { record = nextRecord }
                phase = .committing
            }
        }
        guard let key else { return nil }
        return DeviceSyncTransactionJournal(key: key, record: record, pages: pages, phase: phase)
    }

    nonisolated private static var transactionRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/DeviceSync/Transactions", isDirectory: true)
    }

    private func fail(_ error: Error) {
        if error is CancellationError { return }
        resumeLocalSyncConfirmationWaiter()
        sessionTask?.cancel()
        sessionTask = nil
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        wire?.cancel()
        if progressPlan != nil {
            finalizeInterruption(reason: message)
        } else if error as? DeviceSyncError == .peerCancelled {
            state = .interrupted(DeviceSyncInterruption(
                reason: message,
                completedGalleryCount: progressCompletedGalleries,
                rolledBackGalleryCount: progressRolledBackGalleries
            ))
        } else {
            state = .failed(message)
        }
    }

    private func finalizeInterruption(reason: String) {
        interruptionFinalizationTask?.cancel()
        publishProgress(phase: .verifying, force: true)
        interruptionFinalizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.rollbackActiveTransaction() {
                self.progressRolledBackGalleries += 1
            }

            var finalReason = reason
            do {
                _ = try await self.verifyLocalTransferState()
            } catch is CancellationError {
                return
            } catch {
                finalReason += String(localized: " 中断后的本地校验未能完成：\(error.localizedDescription)")
            }
            guard Task.isCancelled == false else { return }
            self.state = .interrupted(DeviceSyncInterruption(
                reason: finalReason,
                completedGalleryCount: self.progressCompletedGalleries,
                rolledBackGalleryCount: self.progressRolledBackGalleries
            ))
            self.interruptionFinalizationTask = nil
            #if os(iOS)
            if self.backgroundTaskIdentifier != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
            #endif
        }
    }

    private func makePairingExpiryTask() -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(300))
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
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: options, tcp: tcpOptions)
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

    private func recordTransportDescription(_ description: String) {
        transportDescription = description
        deviceSyncLogger.info("Device sync transport ready: \(description, privacy: .public)")
    }
}

private struct DeviceSyncPageHeader: Codable, Sendable {
    let key: GalleryKey
    let pageIndex: Int
    let byteCount: Int64

    var id: String { "\(key.id)-\(pageIndex)" }
}

private struct DeviceSyncGalleryBegin: Codable, Sendable {
    let key: GalleryKey
    let pageIndexes: [Int]
    let includesMetadata: Bool
}

private struct DeviceSyncGalleryFinished: Codable, Sendable {
    let key: GalleryKey
}

private struct DeviceSyncGalleryResult: Codable, Sendable {
    let key: GalleryKey
    let succeeded: Bool
    let pageResults: [DeviceSyncPageResult]
}

private struct DeviceSyncPageFinished: Codable, Sendable {
    let key: GalleryKey
    let pageIndex: Int
    let sha256: Data
}

private struct DeviceSyncPageResult: Codable, Sendable {
    let key: GalleryKey
    let pageIndex: Int
    let succeeded: Bool
    let message: String?
}

private struct DeviceSyncHello: Codable, Sendable {
    let protocolVersion: Int
    let deviceName: String
}

private enum DeviceSyncTransactionPhase: String, Codable, Sendable {
    case receiving
    case committing
}

private struct DeviceSyncTransactionPage: Codable, Sendable {
    let pageIndex: Int
    let byteCount: Int64
    let sha256: Data
}

private struct DeviceSyncTransactionJournal: Codable, Sendable {
    let key: GalleryKey
    var record: GalleryTransferRecord?
    var pages: [DeviceSyncTransactionPage]
    var phase: DeviceSyncTransactionPhase
}

private enum DeviceSyncTransactionEventKind: String, Codable, Sendable {
    case begin
    case metadata
    case page
    case committing
}

private struct DeviceSyncTransactionEvent: Codable, Sendable {
    let kind: DeviceSyncTransactionEventKind
    let key: GalleryKey?
    let record: GalleryTransferRecord?
    let page: DeviceSyncTransactionPage?
}

private struct DeviceSyncPageReceiveOutcome: Sendable {
    let result: DownloadReceiveResult?
    let errorMessage: String?
    let trailingProgressBytes: Int64
}

/// Keeps page writes and progress coalescing off the main actor. A local write
/// failure is remembered while the wire continues draining the declared page
/// length, allowing protocol v3 to report all failures once per gallery.
private actor DeviceSyncPageReceiver {
    private let files: DownloadFileStore
    private var handle: DownloadReceiveHandle?
    private var errorMessage: String?
    private var unreportedBytes: Int64 = 0

    init(
        files: DownloadFileStore,
        handle: DownloadReceiveHandle?,
        initialErrorMessage: String? = nil
    ) {
        self.files = files
        self.handle = handle
        self.errorMessage = initialErrorMessage
    }

    func consume(_ data: Data) async -> Int64 {
        unreportedBytes += Int64(data.count)
        if errorMessage == nil, let handle {
            do {
                try await files.appendReceiveChunk(data, to: handle)
            } catch {
                errorMessage = error.localizedDescription
                try? await files.discardReceive(handle)
                self.handle = nil
            }
        }
        guard unreportedBytes >= DeviceSyncCoordinator.progressUpdateBytes else { return 0 }
        let result = unreportedBytes
        unreportedBytes = 0
        return result
    }

    func finish(expectedSHA256: Data) async -> DeviceSyncPageReceiveOutcome {
        let trailingBytes = unreportedBytes
        unreportedBytes = 0
        guard errorMessage == nil, let handle else {
            return DeviceSyncPageReceiveOutcome(
                result: nil,
                errorMessage: errorMessage ?? DeviceSyncError.transferNotPlanned.localizedDescription,
                trailingProgressBytes: trailingBytes
            )
        }
        self.handle = nil
        do {
            return DeviceSyncPageReceiveOutcome(
                result: try await files.finishReceive(handle, expectedSHA256: expectedSHA256),
                errorMessage: nil,
                trailingProgressBytes: trailingBytes
            )
        } catch {
            return DeviceSyncPageReceiveOutcome(
                result: nil,
                errorMessage: error.localizedDescription,
                trailingProgressBytes: trailingBytes
            )
        }
    }

    func discard() async {
        if let handle {
            try? await files.discardReceive(handle)
            self.handle = nil
        }
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

private actor DeviceSyncWireConnection {
    private struct PendingSend: Sendable {
        let data: Data
        let mediaByteCount: Int64
    }

    private static let maximumRawChunk = DeviceSyncCoordinator.maximumPageChunkBytes
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "EhViewer.DeviceSync.Connection")
    private var started = false
    private var pendingSends: [PendingSend] = []
    private var pendingByteCount = 0
    private var pendingMediaByteCount: Int64 = 0

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() async throws {
        guard started == false else { return }
        started = true
        let gate = StartContinuationGate()
        try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.succeed(continuation)
                case let .failed(error):
                    gate.fail(continuation, error: DeviceSyncError.network(error.localizedDescription))
                case .cancelled:
                    gate.fail(continuation, error: CancellationError())
                default:
                    break
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
                self.cancel()
                throw DeviceSyncError.connectionTimeout
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    @discardableResult
    func send(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64 {
        let flushedMediaBytes = try await flush()
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        try await sendBatch([PendingSend(data: frame, mediaByteCount: 0)])
        return flushedMediaBytes
    }

    /// Enqueues a framed control message in the same bounded window as raw
    /// page bytes. This preserves stream ordering while avoiding a completion
    /// callback for every small page header and footer.
    func enqueue(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64 {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        return try await enqueue(PendingSend(data: frame, mediaByteCount: 0))
    }

    nonisolated func sendSynchronously(_ type: DeviceSyncMessageType, payload: Data) throws {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func enqueueRaw(_ data: Data) async throws -> Int64 {
        guard data.isEmpty == false,
              data.count <= DeviceSyncCoordinator.maximumPageChunkBytes else {
            throw DeviceSyncError.transferNotPlanned
        }
        return try await enqueue(PendingSend(data: data, mediaByteCount: Int64(data.count)))
    }

    func flush() async throws -> Int64 {
        guard pendingSends.isEmpty == false else { return 0 }
        let sends = pendingSends
        let mediaByteCount = pendingMediaByteCount
        pendingSends.removeAll(keepingCapacity: true)
        pendingByteCount = 0
        pendingMediaByteCount = 0
        try await sendBatch(sends)
        return mediaByteCount
    }

    private func enqueue(_ send: PendingSend) async throws -> Int64 {
        pendingSends.append(send)
        pendingByteCount += send.data.count
        pendingMediaByteCount += send.mediaByteCount
        guard pendingByteCount >= DeviceSyncCoordinator.sendWindowBytes else { return 0 }
        return try await flush()
    }

    private func sendBatch(_ sends: [PendingSend]) async throws {
        guard sends.isEmpty == false else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.sendBatchUnbounded(sends) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                self.cancel()
                throw DeviceSyncError.idleTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { return }
            return result
        }
    }

    private func sendBatchUnbounded(_ sends: [PendingSend]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.batch {
                for send in sends.dropLast() {
                    connection.send(content: send.data, completion: .idempotent)
                }
                guard let last = sends.last else {
                    continuation.resume(returning: ())
                    return
                }
                connection.send(content: last.data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: DeviceSyncError.network(error.localizedDescription))
                    } else {
                        continuation.resume(returning: ())
                    }
                })
            }
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

    func receiveExactly(
        _ count: Int64,
        consume: @Sendable (Data) async throws -> Void
    ) async throws {
        var remaining = count
        while remaining > 0 {
            let maximumLength = min(Self.maximumRawChunk, Int(remaining))
            let chunk = try await receiveChunk(
                minimumLength: min(64 * 1024, maximumLength),
                maximumLength: maximumLength
            )
            guard chunk.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            remaining -= Int64(chunk.count)
            try await consume(chunk)
        }
    }

    nonisolated func cancel() {
        connection.cancel()
    }

    func transportDescription() -> String {
        guard let path = connection.currentPath else { return "unknown" }
        let interfaceNames = path.availableInterfaces.map(\.name).sorted()
        let kind: String
        if interfaceNames.contains(where: { $0.lowercased().hasPrefix("awdl") }) {
            kind = "peer-to-peer"
        } else if path.usesInterfaceType(.wifi) {
            kind = "Wi-Fi"
        } else if path.usesInterfaceType(.wiredEthernet) {
            kind = "Ethernet"
        } else {
            kind = "local-network"
        }
        guard interfaceNames.isEmpty == false else { return kind }
        return "\(kind) [\(interfaceNames.joined(separator: ", "))]"
    }

    private func receiveExactlyData(count: Int) async throws -> Data {
        guard count >= 0, count <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let chunk = try await receiveChunk(minimumLength: 1, maximumLength: count - result.count)
            guard chunk.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            result.append(chunk)
        }
        return result
    }

    private func receiveChunk(minimumLength: Int, maximumLength: Int) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await self.receiveChunkUnbounded(
                    minimumLength: minimumLength,
                    maximumLength: maximumLength
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                self.cancel()
                throw DeviceSyncError.idleTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw DeviceSyncError.network("连接已关闭")
            }
            return result
        }
    }

    private func receiveChunkUnbounded(minimumLength: Int, maximumLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: max(1, min(minimumLength, maximumLength)),
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
    case galleryBegin
    case metadata
    case pageHeader
    case pageFinished
    case galleryFinished
    case galleryResult
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
