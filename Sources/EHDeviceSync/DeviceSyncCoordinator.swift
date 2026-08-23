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
    nonisolated public static let protocolVersion = 2
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
    #if os(iOS)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif

    public init(persistence: PersistenceStore, files: DownloadFileStore) {
        self.persistence = persistence
        self.files = files
        self.localDeviceName = Self.makeDeviceName()
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
                  let journal = try? JSONDecoder().decode(DeviceSyncTransactionJournal.self, from: data) else {
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
        state = .interrupted(DeviceSyncInterruption(
            reason: DeviceSyncError.appEnteredBackground.localizedDescription,
            completedGalleryCount: progressCompletedGalleries,
            rolledBackGalleryCount: progressRolledBackGalleries
        ))
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.rollbackActiveTransaction() {
                self.progressRolledBackGalleries += 1
                self.state = .interrupted(DeviceSyncInterruption(
                    reason: DeviceSyncError.appEnteredBackground.localizedDescription,
                    completedGalleryCount: self.progressCompletedGalleries,
                    rolledBackGalleryCount: self.progressRolledBackGalleries
                ))
            }
            #if os(iOS)
            if self.backgroundTaskIdentifier != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
            #endif
        }
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

        publishProgress(phase: .comparingResults, force: true)
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
            state = .completed(result(for: plan))
        } else {
            currentPlan = finalPlan
            state = .awaitingSyncConfirmation(DeviceSyncPreview(plan: finalPlan))
        }
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
            var gallerySucceeded = true
            for page in pages {
                guard gallerySucceeded else { break }
                gallerySucceeded = try await sendPage(page, title: title, wire: wire)
            }
            try await wire.send(.galleryFinished, payload: try encodeControl(DeviceSyncGalleryFinished(key: key)))
            let galleryResult: DeviceSyncGalleryResult = try decodeControl(
                try await wire.receivePayload(expected: .galleryResult)
            )
            guard galleryResult.key == key else { throw DeviceSyncError.unexpectedMessage }
            if gallerySucceeded && galleryResult.succeeded {
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
                guard galleryFailed == false else { throw DeviceSyncError.unexpectedMessage }
                let header: DeviceSyncPageHeader = try decodeControl(message.payload)
                guard let expected = expectedPages[header.pageIndex],
                      receivedIndexes.insert(header.pageIndex).inserted,
                      header.key == begin.key,
                      header.byteCount == expected.byteCount else {
                    throw DeviceSyncError.transferNotPlanned
                }
                let receiveHandle = try await files.beginReceive(
                    for: header.key,
                    pageIndex: header.pageIndex,
                    expectedByteCount: header.byteCount
                )
                do {
                    publishProgress(
                        phase: .receiving,
                        direction: .receiving,
                        galleryTitle: title,
                        pageIndex: header.pageIndex,
                        force: true
                    )
                    try await wire.receiveExactly(header.byteCount) { chunk in
                        try await self.files.appendReceiveChunk(chunk, to: receiveHandle)
                        await MainActor.run {
                            self.addProgressBytes(Int64(chunk.count), direction: .receiving)
                        }
                    }
                    publishProgress(
                        phase: .verifying,
                        direction: .receiving,
                        galleryTitle: title,
                        pageIndex: header.pageIndex,
                        force: true
                    )
                    let finished: DeviceSyncPageFinished = try decodeControl(
                        try await wire.receivePayload(expected: .pageFinished)
                    )
                    guard finished.key == header.key,
                          finished.pageIndex == header.pageIndex else {
                        throw DeviceSyncError.unexpectedMessage
                    }
                    let result = try await files.finishReceive(
                        receiveHandle,
                        expectedSHA256: finished.sha256
                    )
                    validatedPages.append((header.pageIndex, header.byteCount))
                    if case .committed = result {
                        committedPages.append((header.pageIndex, header.byteCount, finished.sha256))
                        try appendActiveTransactionPage(
                            pageIndex: header.pageIndex,
                            byteCount: header.byteCount,
                            sha256: finished.sha256
                        )
                    }
                    try await wire.send(.pageResult, payload: try encodeControl(DeviceSyncPageResult(
                        key: header.key,
                        pageIndex: header.pageIndex,
                        succeeded: true,
                        message: nil
                    )))
                } catch {
                    try? await files.discardReceive(receiveHandle)
                    galleryFailed = true
                    try? await wire.send(.pageResult, payload: try encodeControl(DeviceSyncPageResult(
                        key: header.key,
                        pageIndex: header.pageIndex,
                        succeeded: false,
                        message: error.localizedDescription
                    )))
                }
            case .galleryFinished:
                let finished: DeviceSyncGalleryFinished = try decodeControl(message.payload)
                guard finished.key == begin.key else { throw DeviceSyncError.unexpectedMessage }
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
                }
                finishActiveTransaction()
                try await wire.send(.galleryResult, payload: try encodeControl(DeviceSyncGalleryResult(
                    key: begin.key,
                    succeeded: galleryFailed == false
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
    ) async throws -> Bool {
        let hasher = PageHashAccumulator()
        let header = DeviceSyncPageHeader(
            key: page.key,
            pageIndex: page.pageIndex,
            byteCount: page.byteCount
        )
        try await wire.send(.pageHeader, payload: try encodeControl(header))
        publishProgress(
            phase: .sending,
            direction: .sending,
            galleryTitle: title,
            pageIndex: page.pageIndex,
            force: true
        )
        try await files.readPageChunks(for: page.key, pageIndex: page.pageIndex, chunkSize: Self.pageChunkBytes) { chunk in
            await hasher.update(data: chunk)
            try await wire.sendRaw(chunk)
            await MainActor.run {
                self.addProgressBytes(Int64(chunk.count), direction: .sending)
            }
        }
        let (sentBytes, digest) = await hasher.finalize()
        guard sentBytes == page.byteCount else { throw DeviceSyncError.transferNotPlanned }
        try await wire.send(.pageFinished, payload: try encodeControl(DeviceSyncPageFinished(
            key: page.key,
            pageIndex: page.pageIndex,
            sha256: digest
        )))
        let result: DeviceSyncPageResult = try decodeControl(
            try await wire.receivePayload(expected: .pageResult)
        )
        guard result.key == page.key, result.pageIndex == page.pageIndex else {
            throw DeviceSyncError.unexpectedMessage
        }
        if result.succeeded {
            addCompletedPages(1, direction: .sending)
        }
        return result.succeeded
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
        activeTransaction = DeviceSyncTransactionJournal(
            key: key,
            record: record,
            pages: [],
            phase: .receiving
        )
        activeTransactionURL = url
        try persistActiveTransaction()
    }

    private func updateActiveTransaction(record: GalleryTransferRecord) throws {
        guard var transaction = activeTransaction else { return }
        transaction.record = record
        activeTransaction = transaction
        try persistActiveTransaction()
    }

    private func appendActiveTransactionPage(
        pageIndex: Int,
        byteCount: Int64,
        sha256: Data
    ) throws {
        guard var transaction = activeTransaction else { return }
        transaction.pages.append(DeviceSyncTransactionPage(
            pageIndex: pageIndex,
            byteCount: byteCount,
            sha256: sha256
        ))
        activeTransaction = transaction
        try persistActiveTransaction()
    }

    private func markActiveTransactionCommitting(record: GalleryTransferRecord) throws {
        guard var transaction = activeTransaction else { return }
        transaction.record = record
        transaction.phase = .committing
        activeTransaction = transaction
        try persistActiveTransaction()
    }

    private func persistActiveTransaction() throws {
        guard let transaction = activeTransaction,
              let url = activeTransactionURL else { return }
        try JSONEncoder().encode(transaction).write(to: url, options: .atomic)
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
        if let url = activeTransactionURL {
            try? FileManager.default.removeItem(at: url)
        }
        activeTransaction = nil
        activeTransactionURL = nil
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
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if progressPlan != nil || error as? DeviceSyncError == .peerCancelled {
            state = .interrupted(DeviceSyncInterruption(
                reason: message,
                completedGalleryCount: progressCompletedGalleries,
                rolledBackGalleryCount: progressRolledBackGalleries
            ))
        } else {
            state = .failed(message)
        }
        wire?.cancel()
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

    func send(_ type: DeviceSyncMessageType, payload: Data) async throws {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        try await sendRaw(frame)
    }

    nonisolated func sendSynchronously(_ type: DeviceSyncMessageType, payload: Data) throws {
        let frame = try DeviceSyncWireFrame(type: type, payload: payload).encoded()
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    func sendRaw(_ data: Data) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.sendRawUnbounded(data) }
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

    private func sendRawUnbounded(_ data: Data) async throws {
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

    func receiveExactly(
        _ count: Int64,
        consume: @Sendable (Data) async throws -> Void
    ) async throws {
        var remaining = count
        while remaining > 0 {
            let chunk = try await receiveChunk(maximumLength: min(Self.maximumRawChunk, Int(remaining)))
            guard chunk.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            remaining -= Int64(chunk.count)
            try await consume(chunk)
        }
    }

    nonisolated func cancel() {
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
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await self.receiveChunkUnbounded(maximumLength: maximumLength) }
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

    private func receiveChunkUnbounded(maximumLength: Int) async throws -> Data {
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
    case galleryBegin
    case metadata
    case pageHeader
    case pageFinished
    case pageResult
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
