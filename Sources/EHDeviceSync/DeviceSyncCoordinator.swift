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
#if EH_ENABLE_WIFI_AWARE && canImport(WiFiAware)
import WiFiAware
#endif
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
            String(localized: "设备同步长时间没有传输数据，连接已中断。")
        case .peerCancelled:
            String(localized: "对方取消了设备同步。")
        case .appEnteredBackground:
            String(localized: "应用进入后台，设备同步已安全中断。")
        case let .protocolVersionMismatch(local, remote):
            String(localized: "设备同步协议版本不匹配（本机 \(local)，对方 \(remote)）。请先将另一台设备升级到支持同步 v4 的版本。")
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
    public let receiveTranslationCount: Int
    public let sendTranslationCount: Int

    fileprivate init(plan: DeviceSyncPlan) {
        self.plan = plan
        receiveGalleryCount = plan.receiveGalleries.count
        sendGalleryCount = plan.sendGalleries.count
        receivePageCount = plan.receivePages.count + plan.receiveTranslations.reduce(0) { $0 + $1.availablePages.count }
        sendPageCount = plan.sendPages.count + plan.sendTranslations.reduce(0) { $0 + $1.availablePages.count }
        receiveBytes = plan.receiveBytes
        sendBytes = plan.sendBytes
        receiveTranslationCount = plan.receiveTranslations.count
        sendTranslationCount = plan.sendTranslations.count
    }
}

public enum DeviceSyncPhase: String, Hashable, Sendable {
    case generatingManifest
    case waitingForConfirmation
    case sending
    case receiving
    case committing
    case comparingResults
}

public enum DeviceSyncDirection: String, Hashable, Sendable {
    case sending
    case receiving
}

public enum DeviceSyncTransportKind: String, Codable, Hashable, Sendable {
    case wifiAware
    case applePeerToPeerWiFi
    case infrastructureWiFi
    case wiredEthernet
    case localNetwork
}

public struct DeviceSyncTransportInfo: Codable, Hashable, Sendable {
    public let kind: DeviceSyncTransportKind
    public let displayName: String
    public let applicationProtocol: String
    public let interfaceName: String?
    public let isFallback: Bool

    public init(
        kind: DeviceSyncTransportKind,
        displayName: String,
        applicationProtocol: String = "TCP",
        interfaceName: String? = nil,
        isFallback: Bool = false
    ) {
        self.kind = kind
        self.displayName = displayName
        self.applicationProtocol = applicationProtocol
        self.interfaceName = interfaceName
        self.isFallback = isFallback
    }

    public var label: String { "\(displayName) / \(applicationProtocol)" }
}

public struct DeviceSyncTransferMetrics: Codable, Hashable, Sendable {
    public let networkDuration: TimeInterval
    public let applicationBytes: Int64
    public let averageBytesPerSecond: Double
    public let retransmittedBytes: Int64?
    public let smoothedRTTMilliseconds: Double?

    public init(
        networkDuration: TimeInterval,
        applicationBytes: Int64,
        retransmittedBytes: Int64? = nil,
        smoothedRTTMilliseconds: Double? = nil
    ) {
        self.networkDuration = max(0, networkDuration)
        self.applicationBytes = max(0, applicationBytes)
        averageBytesPerSecond = networkDuration > 0 ? Double(applicationBytes) / networkDuration : 0
        self.retransmittedBytes = retransmittedBytes
        self.smoothedRTTMilliseconds = smoothedRTTMilliseconds
    }
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
    public let transportInfo: DeviceSyncTransportInfo?
    public let locallyProcessedGalleries: Int
    public let totalLocalGalleries: Int

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
    public let result: DeviceSyncResult
    public let completedGalleryCount: Int
    public let rolledBackGalleryCount: Int
}

public struct DeviceSyncResult: Hashable, Sendable {
    public let plannedSentGalleryCount: Int
    public let plannedReceivedGalleryCount: Int
    public let sentGalleryCount: Int
    public let receivedGalleryCount: Int
    public let sentPageCount: Int
    public let receivedPageCount: Int
    public let sentTranslationCount: Int
    public let receivedTranslationCount: Int
    public let sentBytes: Int64
    public let receivedBytes: Int64
    public let committedGalleryCount: Int
    public let deletedGalleryCount: Int
    public let skippedGalleryCount: Int
    public let transferMetrics: DeviceSyncTransferMetrics?
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
    case indexRequired
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
    private enum TransferTermination: Sendable {
        case cancelled
        case interrupted
    }

    nonisolated public static let serviceType = "_ehviewer-sync._tcp"
    nonisolated public static let protocolVersion = 5
    nonisolated public static let maximumControlFrameBytes = 4 * 1024 * 1024
    nonisolated public static let pageChunkBytes = 1 * 1024 * 1024
    nonisolated public static let maximumPageChunkBytes = 1 * 1024 * 1024
    nonisolated public static let sendWindowBytes = 16 * 1024 * 1024
    nonisolated public static let receiveQueueBytes = 16 * 1024 * 1024
    nonisolated public static let progressUpdateBytes = 4 * 1024 * 1024
    private static let serviceInstanceTXTKey = "ehviewer-instance"

    public let persistence: PersistenceStore
    public let files: DownloadFileStore
    public let index: DeviceSyncIndexStore
    public let translations: TranslationFileStore

    public private(set) var state: DeviceSyncState = .idle
    public private(set) var peers: [DeviceSyncPeer] = []
    public private(set) var pairingCode: String?
    public private(set) var localDeviceName: String
    public private(set) var remoteDeviceName = "EhViewer"
    public private(set) var transportDescription: String?
    public private(set) var transportInfo: DeviceSyncTransportInfo?
    public private(set) var transferMetrics: DeviceSyncTransferMetrics?

    /// Keeps the synchronization session alive when the settings screen is
    /// no longer visible. The iOS runtime uses this to distinguish an active
    /// transfer from discovery, which is intentionally view-scoped.
    public var hasActiveSession: Bool {
        switch state {
        case .connecting,
             .awaitingRemoteConfirmation,
             .awaitingConnectionConfirmation,
             .preparing,
             .awaitingSyncConfirmation,
             .syncing:
            true
        case .interrupted:
            interruptionFinalizationTask != nil
        case .idle,
             .indexRequired,
             .discovering,
             .awaitingPairingCode,
             .completed,
             .cancelled,
             .failed:
            false
        }
    }

    /// Opaque per-coordinator identifier used only to filter this process's
    /// own Bonjour advertisement from browser results. It is not user data.
    private let serviceInstanceID = UUID().uuidString
    private let transactionRoot: URL
    private let staging: DeviceSyncStagingStore
    private var browser: NWBrowser?
    private var listener: NWListener?
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
    @ObservationIgnored private var wifiAwareListenerStorage: AnyObject?
    private var wifiAwareListenerTask: Task<Void, Never>?
#endif
    private var endpoints: [String: NWEndpoint] = [:]
    private var pendingIncoming: NWConnection?
    private var wire: (any DeviceSyncStreamConnection)?
    private var sessionTask: Task<Void, Never>?
    private var indexStatusTask: Task<Void, Never>?
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
    private var progressSentGalleries = 0
    private var progressReceivedGalleries = 0
    private var progressSentPages = 0
    private var progressReceivedPages = 0
    private var progressSentTranslations = 0
    private var progressReceivedTranslations = 0
    private var progressSentBytes: Int64 = 0
    private var progressReceivedBytes: Int64 = 0
    private var progressCommittedGalleries = 0
    private var progressDeletedGalleries = 0
    private var progressSkippedGalleries = 0
    private var progressLocalTotalGalleries = 0
    private var stagingSessionID: UUID?
    private var networkStartedAt: ContinuousClock.Instant?
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

    public init(
        persistence: PersistenceStore,
        files: DownloadFileStore,
        translations: TranslationFileStore = TranslationFileStore(),
        index: DeviceSyncIndexStore = DeviceSyncIndexStore(),
        transactionRoot: URL? = nil
    ) {
        self.persistence = persistence
        self.files = files
        self.translations = translations
        self.index = index
        self.transactionRoot = transactionRoot ?? Self.defaultTransactionRootURL
        self.staging = DeviceSyncStagingStore(root: transactionRoot ?? Self.defaultTransactionRootURL)
        self.localDeviceName = Self.makeDeviceName()
    }

    nonisolated public static func preferredPageChunkBytes(forPageByteCount byteCount: Int64) -> Int {
        maximumPageChunkBytes
    }

    /// Resolves the small transaction journals left by a force-quit. A
    /// gallery that reached the committing phase is completed idempotently;
    /// an earlier gallery is rolled back using the hashes of this round's
    /// newly-created pages.
    public func recoverInterruptedTransfers() async -> DeviceSyncRecoveryResult {
        var completed = 0
        var rolledBack = 0
        for sessionID in await staging.pendingSessionIDs() {
            guard !Task.isCancelled else { break }
            let beforeCompleted = progressCommittedGalleries
            let beforeDeleted = progressDeletedGalleries
            do {
                try await finalizeStagedSession(sessionID, plan: nil, interrupted: true)
            } catch {
                // Leave the session in place. Startup recovery is idempotent
                // and will retry after the next launch.
                continue
            }
            completed += progressCommittedGalleries - beforeCompleted
            rolledBack += progressDeletedGalleries - beforeDeleted
        }

        let fileManager = FileManager.default
        let journals = await Self.loadRecoveryJournals(root: transactionRoot)
        for (url, decodedJournal) in journals {
            guard !Task.isCancelled else { break }
            guard let journal = decodedJournal else {
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
                    for page in journal.pages {
                        await index.upsertMediaPage(
                            key: journal.key,
                            pageIndex: page.pageIndex,
                            byteCount: page.byteCount
                        )
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

    /// Builds the sidecar index from the authoritative metadata records and
    /// validated local media. During the scan, file and metadata mutations are
    /// queued by the index actor and applied to the rebuilt snapshot before it
    /// becomes visible to synchronization.
    public func rebuildIndex(
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws {
        try await index.beginRebuild()
        do {
            let records = try await persistence.downloadedGalleryTransferRecords()
            let galleryCount = records.count
            let total = max(1, galleryCount * 2)
            progress(0, total)
            let pagesByGallery = try await files.scanLocalPageEntries(
                for: records.map { $0.stable.key },
                progress: { completed, _ in
                    progress(completed, total)
                }
            )

            var entries: [DeviceSyncIndexEntry] = []
            entries.reserveCapacity(galleryCount)
            for (offset, record) in records.enumerated() {
                try Task.checkCancellation()
                let metadata = try DeviceSyncMetadataDigest.make(
                    stable: record.stable,
                    dynamic: record.dynamic
                )
                entries.append(try DeviceSyncIndexEntry(
                    key: record.stable.key,
                    pages: pagesByGallery[record.stable.key] ?? [],
                    metadata: metadata
                ))
                progress(galleryCount + offset + 1, total)
            }

            try await index.finishRebuild(with: DeviceSyncIndexSnapshot(entries: entries))
            progress(total, total)
            state = .idle
        } catch {
            await index.cancelRebuild()
            throw error
        }
    }

    /// Starts Bonjour browser/listener only while the sync screen is active.
    public func start() {
        stop()
        guard interruptionFinalizationTask == nil else { return }
        indexStatusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.index.status() == .ready else {
                self.state = .indexRequired
                return
            }
            self.startDiscovery()
        }
    }

    private func startDiscovery() {
        guard interruptionFinalizationTask == nil else { return }
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
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
            if #available(iOS 26.0, *), DeviceSyncWiFiAwareSupport.isAvailable {
                startWiFiAwarePublisher()
            }
#endif
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func stop() {
        if interruptionFinalizationTask != nil {
            cancelTransport()
            return
        }
        if progressPlan != nil {
            let taskToDrain = cancelTransport()
            finalizeInterruption(
                reason: String(localized: "设备同步已取消。"),
                termination: .cancelled,
                draining: taskToDrain
            )
            return
        }
        _ = cancelTransport()
        resetSessionState()
    }

    @discardableResult
    private func cancelTransport() -> Task<Void, Never>? {
        let task = sessionTask
        task?.cancel()
        sessionTask = nil
        indexStatusTask?.cancel()
        indexStatusTask = nil
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        browser?.cancel()
        listener?.cancel()
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
        if #available(iOS 26.0, *) {
            wifiAwareListenerStorage = nil
        }
        wifiAwareListenerTask?.cancel()
        wifiAwareListenerTask = nil
#endif
        pendingIncoming?.cancel()
        wire?.cancel()
        browser = nil
        listener = nil
        pendingIncoming = nil
        wire = nil
        resumeLocalSyncConfirmationWaiter()
        return task
    }

    private func resetSessionState() {
#if os(iOS)
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
#endif
        endpoints.removeAll()
        peers.removeAll()
        secureListenerActive = false
        pairingCode = nil
        remoteDeviceName = "EhViewer"
        transportDescription = nil
        transportInfo = nil
        transferMetrics = nil
        localApproved = false
        peerApproved = false
        localSyncRequested = false
        localSyncStartSent = false
        peerSyncRequested = false
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
        progressSentGalleries = 0
        progressReceivedGalleries = 0
        progressSentPages = 0
        progressReceivedPages = 0
        progressSentTranslations = 0
        progressReceivedTranslations = 0
        progressSentBytes = 0
        progressReceivedBytes = 0
        progressCommittedGalleries = 0
        progressDeletedGalleries = 0
        progressSkippedGalleries = 0
        progressLocalTotalGalleries = 0
        stagingSessionID = nil
        networkStartedAt = nil
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
                self?.fail(CancellationError())
            } catch {
                self?.fail(error)
            }
        }
    }

#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
    @available(iOS 26.0, *)
    public func connectWiFiAware(to endpoint: WAEndpoint) {
        guard DeviceSyncWiFiAwareSupport.isAvailable, wire == nil else {
            state = .failed(DeviceSyncError.notReady.localizedDescription)
            return
        }
        isInitiator = true
        localApproved = true
        pairingCode = nil
        state = .connecting
        let connection = NetworkConnection(
            to: endpoint,
            using: .parameters {
                TCP().noDelay(true)
            }
            .wifiAware { $0.performanceMode = .bulk }
            .serviceClass(.bestEffort)
        )
        let candidateWire = WiFiAwareWireConnection(connection: connection)
        wire = candidateWire
        sessionTask = Task { @MainActor [weak self, candidateWire] in
            do {
                try await self?.runWiFiAwareInitiator(wire: candidateWire)
            } catch is CancellationError {
                self?.fail(CancellationError())
            } catch {
                self?.fail(error)
            }
        }
    }

    @available(iOS 26.0, *)
    private func startWiFiAwarePublisher() {
        guard let service = WAPublishableService.allServices[Self.serviceType] else { return }
        do {
            let listener = try NetworkListener(
                for: .wifiAware(.connecting(to: service, from: .allPairedDevices, datapath: .defaults)),
                using: .parameters {
                    TCP().noDelay(true)
                }
                .wifiAware { $0.performanceMode = .bulk }
                .serviceClass(.bestEffort)
            )
            self.wifiAwareListenerStorage = listener
            wifiAwareListenerTask = Task { @MainActor [weak self, listener] in
                do {
                    try await listener.run { connection in
                        await MainActor.run {
                            self?.handleWiFiAwareIncoming(connection)
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard self?.wire == nil else { return }
                    deviceSyncLogger.error("Wi-Fi Aware publisher failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            deviceSyncLogger.error("Wi-Fi Aware publisher unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(iOS 26.0, *)
    private func handleWiFiAwareIncoming(_ connection: NetworkConnection<TCP>) {
        guard wire == nil else {
            connection.sendIdempotent(Data(), endOfStream: true)
            return
        }
        isInitiator = false
        localApproved = false
        let candidateWire = WiFiAwareWireConnection(connection: connection)
        wire = candidateWire
        sessionTask = Task { @MainActor [weak self, candidateWire] in
            do {
                try await candidateWire.start(timeout: .seconds(10))
                guard let self else { return }
                self.recordTransportInfo(await candidateWire.currentTransportInfo())
                let hello: DeviceSyncHello = try self.decodeControl(
                    try await candidateWire.receivePayload(expected: .hello)
                )
                guard hello.protocolVersion == Self.protocolVersion else {
                    throw DeviceSyncError.protocolVersionMismatch(local: Self.protocolVersion, remote: hello.protocolVersion)
                }
                self.remoteDeviceName = hello.deviceName
                self.state = .awaitingConnectionConfirmation
            } catch is CancellationError {
                self?.fail(CancellationError())
            } catch {
                self?.fail(error)
            }
        }
    }

    @available(iOS 26.0, *)
    private func runWiFiAwareInitiator(wire: WiFiAwareWireConnection) async throws {
        try await wire.start(timeout: .seconds(10))
        recordTransportInfo(await wire.currentTransportInfo())
        _ = try await wire.send(.hello, payload: try encodeControl(DeviceSyncHello(
            protocolVersion: Self.protocolVersion,
            deviceName: localDeviceName
        )))
        state = .awaitingRemoteConfirmation
        try await waitForApproval(wire: wire)
        try await runInitiatorSession(wire: wire)
    }
#endif

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
                _ = try await wire.send(.approval, payload: Data())
                try await self?.runReceiverSession(wire: wire)
            } catch is CancellationError {
                self?.fail(CancellationError())
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
                _ = try await wire.send(.syncStart, payload: Data())
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
        if progressPlan != nil {
            let taskToDrain = cancelTransport()
            finalizeInterruption(
                reason: String(localized: "本机取消了设备同步。"),
                termination: .cancelled,
                draining: taskToDrain
            )
        } else {
            let cancellationResult = currentPlan.map(result(for:)) ?? emptyResult
            stop()
            state = .cancelled(cancellationResult)
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
        let taskToDrain = cancelTransport()
        finalizeInterruption(
            reason: DeviceSyncError.appEnteredBackground.localizedDescription,
            draining: taskToDrain
        )
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
                    self.recordTransportInfo(await wire.currentTransportInfo())
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
                    self?.fail(CancellationError())
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
                recordTransportInfo(await candidateWire.currentTransportInfo())
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

    private func waitForApproval(wire: any DeviceSyncStreamConnection) async throws {
        let message = try await wire.receive()
        guard message.type == .approval else {
            throw DeviceSyncError.peerRejected
        }
        peerApproved = true
    }

    private func runInitiatorSession(wire: any DeviceSyncStreamConnection) async throws {
        guard peerApproved else { throw DeviceSyncError.peerRejected }
        state = .preparing(.generatingManifest)
        let manifest = try await makeLocalManifest()
        localManifest = manifest
        localRecords.removeAll(keepingCapacity: true)
        _ = try await wire.send(.manifest, payload: try encodeControl(manifest))
        let remote: DeviceSyncManifest = try decodeControl(try await wire.receivePayload(expected: .manifest))
        try await preparePreview(local: manifest, remote: remote)
        try await waitForPeerSyncStart(wire: wire)
        try await runTransfer(wire: wire)
    }

    private func runReceiverSession(wire: any DeviceSyncStreamConnection) async throws {
        guard localApproved else { throw DeviceSyncError.peerRejected }
        state = .preparing(.generatingManifest)
        let remote: DeviceSyncManifest = try decodeControl(try await wire.receivePayload(expected: .manifest))
        let manifest = try await makeLocalManifest()
        localManifest = manifest
        localRecords.removeAll(keepingCapacity: true)
        _ = try await wire.send(.manifest, payload: try encodeControl(manifest))
        try await preparePreview(local: manifest, remote: remote)
        try await waitForPeerSyncStart(wire: wire)
        try await runTransfer(wire: wire)
    }

    private func preparePreview(local: DeviceSyncManifest, remote: DeviceSyncManifest) async throws {
        try local.validate()
        try remote.validate()
        guard local.formatVersion == DeviceSyncManifest.currentFormatVersion,
              remote.formatVersion == DeviceSyncManifest.currentFormatVersion else { throw DeviceSyncError.unexpectedMessage }
        try DeviceSyncTranslationReconciler.validate(local: local.translations ?? [], remote: remote.translations ?? [])
        let plan = DeviceSyncReconciler.plan(local: local, remote: remote)
        currentPlan = plan
        remoteManifest = remote
        let preview = DeviceSyncPreview(plan: plan)
        currentPreview = preview
        state = .awaitingSyncConfirmation(preview)
    }

    private func waitForPeerSyncStart(wire: any DeviceSyncStreamConnection) async throws {
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

    private func runTransfer(wire: any DeviceSyncStreamConnection) async throws {
        guard let plan = currentPlan else { throw DeviceSyncError.notReady }
        beginProgress(plan: plan)
        let receivePagesByKey = Dictionary(grouping: plan.receivePages, by: \.key)
        let receiveKeys = Set(plan.receiveMetadata).union(receivePagesByKey.keys)
        let stagingPlans = receiveKeys.sorted(by: Self.galleryKeyLessThan).map { key in
            DeviceSyncStagingGalleryPlan(
                key: key,
                pages: (receivePagesByKey[key] ?? []).map {
                    DeviceSyncStagingPage(pageIndex: $0.pageIndex, byteCount: $0.byteCount)
                },
                requiresMetadata: plan.receiveMetadata.contains(key)
            )
        }
        let sessionID = try await staging.create(plan: stagingPlans)
        stagingSessionID = sessionID
        progressLocalTotalGalleries = stagingPlans.count
        networkStartedAt = progressClock.now
        if isInitiator {
            try await sendPlannedData(plan: plan, wire: wire)
            try await receivePlannedData(plan: plan, sessionID: sessionID, wire: wire)
        } else {
            try await receivePlannedData(plan: plan, sessionID: sessionID, wire: wire)
            try await sendPlannedData(plan: plan, wire: wire)
        }

        if let report = await wire.collectTransferReport() {
            recordTransportInfo(report.transportInfo)
            transferMetrics = DeviceSyncTransferMetrics(
                networkDuration: report.duration,
                applicationBytes: report.applicationBytes,
                retransmittedBytes: report.retransmittedBytes,
                smoothedRTTMilliseconds: report.smoothedRTTMilliseconds
            )
        } else if let startedAt = networkStartedAt {
            let duration = Self.seconds(from: startedAt.duration(to: progressClock.now))
            transferMetrics = DeviceSyncTransferMetrics(
                networkDuration: duration,
                applicationBytes: progressSentBytes + progressReceivedBytes
            )
        }
        publishProgress(phase: .committing, force: true)
        try await finalizeStagedSession(sessionID, plan: plan, interrupted: false)
        state = .completed(result(for: plan))
        progressPlan = nil
        stagingSessionID = nil
    }

    private func sendPlannedData(plan: DeviceSyncPlan, wire: any DeviceSyncStreamConnection) async throws {
        let galleryKeys = Set(plan.sendMetadata).union(plan.sendPages.map(\.key))
        var records = try await persistence.galleryTransferRecords(for: galleryKeys)
        let found = Set(records.map { $0.stable.key })
        for key in galleryKeys.subtracting(found) {
            if let record = try await translations.galleryMetadata(for: key) { records.append(record) }
        }
        let recordsByKey = Dictionary(uniqueKeysWithValues: records.map { ($0.stable.key, $0) })
        let pagesByKey = Dictionary(grouping: plan.sendPages, by: \.key)
        let orderedKeys = galleryKeys.sorted(by: Self.galleryKeyLessThan)
        for key in orderedKeys {
            let pages = (pagesByKey[key] ?? []).sorted { $0.pageIndex < $1.pageIndex }
            let includesMetadata = plan.sendMetadata.contains(key)
            let title = recordsByKey[key]?.stable.title
            publishProgress(
                phase: .sending,
                direction: .sending,
                galleryTitle: title
            )
            _ = try await wire.enqueue(.galleryBegin, payload: try encodeControl(DeviceSyncGalleryBegin(
                key: key,
                pageIndexes: pages.map(\.pageIndex),
                includesMetadata: includesMetadata
            )))
            if includesMetadata {
                guard let record = recordsByKey[key] else { throw DeviceSyncError.transferNotPlanned }
                _ = try await wire.enqueue(.metadata, payload: try encodeControl(record))
            }
            for page in pages {
                try await sendPage(page, title: title, wire: wire)
            }
            _ = try await wire.enqueue(
                .galleryFinished,
                payload: try encodeControl(DeviceSyncGalleryFinished(key: key))
            )
            addCompletedPages(pages.count, direction: .sending)
            progressCompletedGalleries += 1
            progressSentGalleries += 1
        }
        try await sendTranslations(plan.sendTranslations, wire: wire)
        _ = try await wire.send(.transferFinished, payload: Data())
        try await wire.expect(.directionReceived)
    }

    private func receivePlannedData(
        plan: DeviceSyncPlan,
        sessionID: UUID,
        wire: any DeviceSyncStreamConnection
    ) async throws {
        let expectedGalleryKeys = Set(plan.receiveMetadata).union(plan.receivePages.map(\.key))
        let expectedPagesByKey = Dictionary(grouping: plan.receivePages, by: \.key)
        var receivedGalleryKeys = Set<GalleryKey>()
        var receivedVersions = Set<UUID>()
        while true {
            let message = try await wire.receive()
            switch message.type {
            case .translationBegin:
                let entry: DeviceSyncTranslationEntry = try decodeControl(message.payload)
                guard let expected = plan.receiveTranslations.first(where: { $0.id == entry.id }),
                      entry == expected, receivedVersions.insert(entry.id).inserted else { throw DeviceSyncError.transferNotPlanned }
                try await receiveTranslation(entry, wire: wire)
            case .galleryBegin:
                let begin: DeviceSyncGalleryBegin = try decodeControl(message.payload)
                guard expectedGalleryKeys.contains(begin.key),
                      receivedGalleryKeys.insert(begin.key).inserted,
                      begin.includesMetadata == plan.receiveMetadata.contains(begin.key) else {
                    throw DeviceSyncError.transferNotPlanned
                }
                do {
                    try await receiveGallery(
                        begin,
                        expectedPageTransfers: expectedPagesByKey[begin.key] ?? [],
                        sessionID: sessionID,
                        wire: wire
                    )
                } catch { throw error }
            case .transferFinished:
                guard receivedGalleryKeys == expectedGalleryKeys,
                      receivedVersions == Set(plan.receiveTranslations.map(\.id)) else {
                    throw DeviceSyncError.transferNotPlanned
                }
                _ = try await wire.send(.directionReceived, payload: Data())
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
        expectedPageTransfers: [DeviceSyncPageTransfer],
        sessionID: UUID,
        wire: any DeviceSyncStreamConnection
    ) async throws {
        let expectedPages = Dictionary(uniqueKeysWithValues: expectedPageTransfers.map { ($0.pageIndex, $0) })
        guard Set(begin.pageIndexes) == Set(expectedPages.keys),
              begin.pageIndexes.count == expectedPages.count else {
            throw DeviceSyncError.transferNotPlanned
        }
        var receivedMetadata = false
        var receivedIndexes = Set<Int>()
        let title = localRecords[begin.key]?.stable.title
        publishProgress(
            phase: .receiving,
            direction: .receiving,
            galleryTitle: title
        )

        while true {
            let message = try await wire.receive()
            switch message.type {
            case .metadata:
                let record: GalleryTransferRecord = try decodeControl(message.payload)
                guard begin.includesMetadata,
                      receivedMetadata == false,
                      record.stable.key == begin.key,
                      record.dynamic.map({ $0.key == begin.key }) ?? true else {
                    throw DeviceSyncError.transferNotPlanned
                }
                receivedMetadata = true
                try await staging.storeMetadata(message.payload, for: begin.key, sessionID: sessionID)
            case .pageHeader:
                let header: DeviceSyncPageHeader = try decodeControl(message.payload)
                guard let expected = expectedPages[header.pageIndex],
                      receivedIndexes.insert(header.pageIndex).inserted,
                      header.key == begin.key,
                      header.byteCount == expected.byteCount else {
                    throw DeviceSyncError.transferNotPlanned
                }
                publishProgress(
                    phase: .receiving,
                    direction: .receiving,
                    galleryTitle: title,
                    pageIndex: header.pageIndex
                )
                try await receivePageToStaging(header, sessionID: sessionID, wire: wire)
            case .galleryFinished:
                let finished: DeviceSyncGalleryFinished = try decodeControl(message.payload)
                guard finished.key == begin.key,
                      receivedIndexes == Set(expectedPages.keys),
                      begin.includesMetadata == receivedMetadata else {
                    throw DeviceSyncError.transferNotPlanned
                }
                try await staging.finishGallery(begin.key, sessionID: sessionID)
                addCompletedPages(receivedIndexes.count, direction: .receiving)
                publishProgress(
                    phase: .receiving,
                    direction: .receiving,
                    galleryTitle: title
                )
                return
            case .cancel:
                throw DeviceSyncError.peerCancelled
            default:
                throw DeviceSyncError.unexpectedMessage
            }
        }
    }

    func sendTranslations(_ entries: [DeviceSyncTranslationEntry], wire: any DeviceSyncStreamConnection) async throws {
        for entry in entries {
            _ = try await wire.enqueue(.translationBegin, payload: try encodeControl(entry))
            for index in entry.availablePages {
                let page = entry.manifest.pages[index]
                _ = try await wire.enqueue(.translationPage, payload: try encodeControl(page))
                publishProgress(phase: .sending, direction: .sending, galleryTitle: entry.manifest.gallery.title, pageIndex: index)
                let buffer = DeviceSyncProgressBuffer(threshold: Int64(Self.progressUpdateBytes))
                try await translations.streamPage(entry.manifest, index: index) { chunk in
                    _ = try await wire.enqueueRaw(chunk)
                    let count = await buffer.add(chunk.count)
                    if count > 0 { await MainActor.run { self.addProgressBytes(count, direction: .sending) } }
                }
                addProgressBytes(await buffer.drain(), direction: .sending)
                addCompletedPages(1, direction: .sending)
            }
            _ = try await wire.enqueue(.translationFinished, payload: try encodeControl(entry.id))
            progressSentTranslations += 1
        }
    }

    func receiveTranslation(_ entry: DeviceSyncTranslationEntry, wire: any DeviceSyncStreamConnection) async throws {
        try await translations.beginIncoming(entry.manifest)
        for index in entry.availablePages {
            let page: GalleryTranslationManifest.Page = try decodeControl(try await wire.receivePayload(expected: .translationPage))
            guard page == entry.manifest.pages[index] else { throw DeviceSyncError.transferNotPlanned }
            let receiver = try await translations.beginIncomingPage(entry.manifest, index: index)
            publishProgress(phase: .receiving, direction: .receiving, galleryTitle: entry.manifest.gallery.title, pageIndex: index)
            let buffer = DeviceSyncProgressBuffer(threshold: Int64(Self.progressUpdateBytes))
            try await wire.receiveExactly(page.byteCount) { chunk in
                try await receiver.append(chunk)
                let count = await buffer.add(chunk.count)
                if count > 0 { await MainActor.run { self.addProgressBytes(count, direction: .receiving) } }
            }
            try await receiver.finish()
            try await translations.finishIncomingPage(entry.manifest, index: index)
            addProgressBytes(await buffer.drain(), direction: .receiving)
            addCompletedPages(1, direction: .receiving)
        }
        let finished: UUID = try decodeControl(try await wire.receivePayload(expected: .translationFinished))
        guard finished == entry.id else { throw DeviceSyncError.transferNotPlanned }
        if try await translations.manifests(for: entry.manifest.gallery.key).contains(where: { $0.id == entry.id }) {
            progressReceivedTranslations += 1
        }
    }

    private func receivePageToStaging(
        _ header: DeviceSyncPageHeader,
        sessionID: UUID,
        wire: any DeviceSyncStreamConnection
    ) async throws {
        let pageID = try await staging.beginPage(
            for: header.key,
            pageIndex: header.pageIndex,
            byteCount: header.byteCount,
            sessionID: sessionID
        )
        let progressBuffer = DeviceSyncProgressBuffer(threshold: Int64(Self.progressUpdateBytes))
        let startedAt = Date()
        do {
            try await wire.receiveExactly(header.byteCount) { chunk in
                try await self.staging.append(chunk, to: pageID)
                let completedBytes = await progressBuffer.add(chunk.count)
                if completedBytes > 0 {
                    await MainActor.run {
                        self.addProgressBytes(completedBytes, direction: .receiving)
                    }
                }
            }
            try await staging.finishPage(pageID)
            addProgressBytes(await progressBuffer.drain(), direction: .receiving)
            let duration = max(0.001, Date().timeIntervalSince(startedAt))
            deviceSyncLogger.debug(
                "Device sync receive and staging write: \(header.byteCount, privacy: .public) bytes, \(Double(header.byteCount) / duration, privacy: .public) B/s"
            )
        } catch {
            let receivedBytes = await progressBuffer.totalByteCount
            deviceSyncLogger.error(
                "Device sync page receive failed: page \(header.pageIndex, privacy: .public), \(receivedBytes, privacy: .public)/\(header.byteCount, privacy: .public) bytes, \(error.localizedDescription, privacy: .public)"
            )
            wire.cancel()
            await staging.abandonPage(pageID)
            throw error
        }
    }

    private func sendPage(
        _ page: DeviceSyncPageTransfer,
        title: String?,
        wire: any DeviceSyncStreamConnection
    ) async throws {
        let header = DeviceSyncPageHeader(
            key: page.key,
            pageIndex: page.pageIndex,
            byteCount: page.byteCount
        )
        _ = try await wire.enqueue(.pageHeader, payload: try encodeControl(header))
        publishProgress(
            phase: .sending,
            direction: .sending,
            galleryTitle: title,
            pageIndex: page.pageIndex
        )
        let progressBuffer = DeviceSyncProgressBuffer(threshold: Int64(Self.progressUpdateBytes))
        try await files.readPageChunks(
            for: page.key,
            pageIndex: page.pageIndex,
            chunkSize: Self.maximumPageChunkBytes
        ) { chunk in
            _ = try await wire.enqueueRaw(chunk)
            let completedBytes = await progressBuffer.add(chunk.count)
            if completedBytes > 0 {
                await MainActor.run {
                    self.addProgressBytes(completedBytes, direction: .sending)
                }
            }
        }
        addProgressBytes(await progressBuffer.drain(), direction: .sending)
    }

    private func finalizeStagedSession(
        _ sessionID: UUID,
        plan: DeviceSyncPlan?,
        interrupted: Bool
    ) async throws {
        let complete = try await staging.completedGalleries(sessionID: sessionID)
        let incomplete = try await staging.incompleteKeys(sessionID: sessionID)
        let unstarted = try await staging.unstartedKeys(sessionID: sessionID)
        progressSkippedGalleries += unstarted.count

        var failedKeys = incomplete
        let commitStartedAt = Date()
        for gallery in complete {
            try Task.checkCancellation()
            do {
                publishProgress(
                    phase: .committing,
                    galleryTitle: gallery.record?.stable.title ?? localRecords[gallery.key]?.stable.title,
                    force: true
                )
                let record: GalleryTransferRecord
                if let incoming = gallery.record {
                    record = incoming
                } else {
                    record = try await transferRecord(for: gallery.key)
                }
                for page in gallery.pages.sorted(by: { $0.pageIndex < $1.pageIndex }) {
                    let url = await staging.pageURL(
                        for: gallery.key,
                        pageIndex: page.pageIndex,
                        sessionID: sessionID
                    )
                    _ = try await files.commitDeviceSyncStagedFile(
                        at: url,
                        for: gallery.key,
                        pageIndex: page.pageIndex
                    )
                }
                let completedPages = Dictionary(
                    uniqueKeysWithValues: gallery.pages.map { ($0.pageIndex, $0.byteCount) }
                )
                try await persistence.commitDeviceSyncGallery(
                    record,
                    completedPages: completedPages,
                    flushIndex: false
                )
                let entries = try gallery.pages.map {
                    try DeviceSyncPageEntry(pageIndex: $0.pageIndex, byteCount: $0.byteCount)
                }
                let metadata = try DeviceSyncMetadataDigest.make(stable: record.stable, dynamic: record.dynamic)
                if (try await translations.manifests(for: gallery.key)).isEmpty == false {
                    try await translations.storeGalleryMetadata(record)
                }
                await index.upsertGallery(key: gallery.key, pages: entries, metadata: metadata)
                localRecords[gallery.key] = record
                try await staging.markResolved(gallery.key, sessionID: sessionID)
                progressCommittedGalleries += 1
                progressReceivedGalleries += 1
                progressCompletedGalleries += 1
                publishProgress(phase: .committing, galleryTitle: record.stable.title, force: true)
            } catch {
                failedKeys.insert(gallery.key)
                progressDeletedGalleries += 1
            }
        }

        if incomplete.isEmpty == false {
            progressDeletedGalleries += incomplete.count
        }
        var cleanupSucceeded = true
        for key in failedKeys {
            if await purgeAbnormalGallery(key) {
                try await staging.markResolved(key, sessionID: sessionID)
            } else {
                cleanupSucceeded = false
            }
        }
        guard cleanupSucceeded else {
            throw DeviceSyncError.network("异常漫画清理尚未完成，将在下次启动时继续。")
        }
        let commitDuration = max(0.001, Date().timeIntervalSince(commitStartedAt))
        deviceSyncLogger.debug(
            "Device sync local commit: \(self.progressCommittedGalleries, privacy: .public) galleries, \(commitDuration, privacy: .public) seconds"
        )
        await staging.removeSession(sessionID)

        if interrupted {
            progressRolledBackGalleries += failedKeys.count
        }
        _ = plan
    }

    private func purgeAbnormalGallery(_ key: GalleryKey) async -> Bool {
        if (try? await translations.manifests(for: key).isEmpty) == false,
           let record = try? await persistence.downloadedTransferRecord(for: key) {
            try? await translations.storeGalleryMetadata(record)
        }
        // Download storage and downloaded metadata are intentionally removed
        // as one logical item. Persistence keeps browse cache, history and
        // favorites in independent models.
        do {
            try await files.remove(key)
            try await persistence.deleteDownload(for: key)
        } catch {
            deviceSyncLogger.error("Failed to purge abnormal synced gallery: \(error.localizedDescription, privacy: .public)")
            return false
        }
        await index.removeGallery(key)
        localRecords[key] = nil
        return true
    }

    private func transferRecord(for key: GalleryKey) async throws -> GalleryTransferRecord {
        if let record = localRecords[key] { return record }
        guard let record = try await persistence.galleryTransferRecords(for: [key]).first else {
            throw DeviceSyncError.transferNotPlanned
        }
        localRecords[key] = record
        return record
    }

    private func makeLocalManifest() async throws -> DeviceSyncManifest {
        let original = try await index.snapshot().manifest()
        let entries = try await translations.syncEntries()
        // The existing original-media index keeps its format and journal.
        // Immutable translation manifests are the companion index namespace.
        var galleries = original.galleries
        let existingKeys = Set(galleries.map(\.key))
        let missingKeys = Set(entries.map { $0.manifest.gallery.key }).subtracting(existingKeys)
        var records = try await persistence.galleryTransferRecords(for: missingKeys)
        let found = Set(records.map { $0.stable.key })
        for key in missingKeys.subtracting(found) {
            if let record = try await translations.galleryMetadata(for: key) { records.append(record) }
        }
        for record in records {
            galleries.append(try DeviceSyncGalleryEntry(key: record.stable.key, pages: [], metadata: DeviceSyncMetadataDigest.make(for: record)))
        }
        let keys = Set(galleries.map(\.key))
        return try DeviceSyncManifest(galleries: galleries, translations: entries.filter { keys.contains($0.manifest.gallery.key) })
    }

    /// Refreshes only the records touched by this synchronization round. Page
    /// bytes were hashed while streaming and every received gallery was
    /// already committed transactionally, so repeating a library-wide
    /// SwiftData commit here would add latency without strengthening checks.
    private func refreshLocalTransferState(
        keys: Set<GalleryKey>
    ) async throws -> (DeviceSyncManifest, [GalleryTransferRecord]) {
        let manifest = try await makeLocalManifest()
        let records = try await persistence.galleryTransferRecords(for: keys)
        localManifest = manifest
        for record in records {
            localRecords[record.stable.key] = record
        }
        return (manifest, records)
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
        progressSentGalleries = 0
        progressReceivedGalleries = 0
        progressSentPages = 0
        progressReceivedPages = 0
        progressSentTranslations = 0
        progressReceivedTranslations = 0
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
        publishProgress(phase: direction == .sending ? .sending : .receiving, direction: direction)
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
        let phaseChanged = phase != progressPhase
        let directionChanged = direction.map { $0 != progressDirection } ?? false
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
           phaseChanged == false,
           directionChanged == false,
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
            totalSendPages: plan.sendPages.count + plan.sendTranslations.reduce(0) { $0 + $1.availablePages.count },
            receivedPages: progressReceivedPages,
            totalReceivePages: plan.receivePages.count + plan.receiveTranslations.reduce(0) { $0 + $1.availablePages.count },
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
            estimatedRemainingSeconds: eta,
            transportInfo: transportInfo,
            locallyProcessedGalleries: progressCommittedGalleries + progressDeletedGalleries,
            totalLocalGalleries: progressLocalTotalGalleries
        ))
    }

    private func result(for plan: DeviceSyncPlan) -> DeviceSyncResult {
        DeviceSyncResult(
            plannedSentGalleryCount: Set(plan.sendMetadata).union(plan.sendPages.map(\.key)).count,
            plannedReceivedGalleryCount: Set(plan.receiveMetadata).union(plan.receivePages.map(\.key)).count,
            sentGalleryCount: progressSentGalleries,
            receivedGalleryCount: progressReceivedGalleries,
            sentPageCount: progressSentPages,
            receivedPageCount: progressReceivedPages,
            sentTranslationCount: progressSentTranslations,
            receivedTranslationCount: progressReceivedTranslations,
            sentBytes: progressSentBytes,
            receivedBytes: progressReceivedBytes,
            committedGalleryCount: progressCommittedGalleries,
            deletedGalleryCount: progressDeletedGalleries,
            skippedGalleryCount: progressSkippedGalleries,
            transferMetrics: transferMetrics
        )
    }

    private var emptyResult: DeviceSyncResult {
        DeviceSyncResult(
            plannedSentGalleryCount: 0,
            plannedReceivedGalleryCount: 0,
            sentGalleryCount: 0,
            receivedGalleryCount: 0,
            sentPageCount: 0,
            receivedPageCount: 0,
            sentTranslationCount: 0,
            receivedTranslationCount: 0,
            sentBytes: 0,
            receivedBytes: 0,
            committedGalleryCount: 0,
            deletedGalleryCount: 0,
            skippedGalleryCount: 0,
            transferMetrics: nil
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
        var root = transactionRoot
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

    @concurrent
    private static func loadRecoveryJournals(root: URL) async -> [(URL, DeviceSyncTransactionJournal?)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        var journals: [(URL, DeviceSyncTransactionJournal?)] = []
        for url in urls where url.pathExtension == "json" {
            guard !Task.isCancelled else { break }
            let journal = (try? Data(contentsOf: url)).flatMap(decodeTransactionJournal)
            journals.append((url, journal))
        }
        return journals
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

    nonisolated private static var defaultTransactionRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/DeviceSync/Transactions", isDirectory: true)
    }

    private func fail(_ error: Error) {
        if error is CancellationError {
            guard progressPlan != nil else { return }
            finalizeInterruption(reason: String(localized: "设备同步已取消。"), draining: sessionTask)
            return
        }
        resumeLocalSyncConfirmationWaiter()
        let taskToDrain = sessionTask
        sessionTask?.cancel()
        sessionTask = nil
        let message: String
        if progressPlan != nil,
           let syncError = error as? DeviceSyncError,
           case .network = syncError {
            // A peer that is manually stopped can close the stream before
            // the cancel frame reaches the other side. The completed staging
            // journals are still safe to commit, so do not expose the raw
            // Network.framework stream error as if the local commit failed.
            message = String(localized: "设备同步连接已中断，已收到的内容将继续提交。")
        } else {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        wire?.cancel()
        if progressPlan != nil {
            finalizeInterruption(reason: message, draining: taskToDrain)
        } else if error as? DeviceSyncError == .peerCancelled {
            state = .interrupted(DeviceSyncInterruption(
                reason: message,
                result: emptyResult,
                completedGalleryCount: progressCompletedGalleries,
                rolledBackGalleryCount: progressRolledBackGalleries
            ))
        } else {
            state = .failed(message)
        }
    }

    private func finalizeInterruption(
        reason: String,
        termination: TransferTermination = .interrupted,
        draining sessionTaskToDrain: Task<Void, Never>? = nil
    ) {
        guard interruptionFinalizationTask == nil else { return }
        publishProgress(phase: .committing, force: true)
        interruptionFinalizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let sessionTaskToDrain {
                await sessionTaskToDrain.value
            }
            if let report = await self.wire?.collectTransferReport() {
                self.recordTransportInfo(report.transportInfo)
                self.transferMetrics = DeviceSyncTransferMetrics(
                    networkDuration: report.duration,
                    applicationBytes: report.applicationBytes,
                    retransmittedBytes: report.retransmittedBytes,
                    smoothedRTTMilliseconds: report.smoothedRTTMilliseconds
                )
            }
            if let sessionID = self.stagingSessionID {
                do {
                    try await self.finalizeStagedSession(
                        sessionID,
                        plan: self.currentPlan,
                        interrupted: true
                    )
                    self.stagingSessionID = nil
                } catch {
                    // The persisted session remains recoverable on next launch.
                }
            } else if await self.rollbackActiveTransaction() {
                self.progressRolledBackGalleries += 1
            }

            var finalReason = reason
            do {
                let affectedKeys = self.currentPlan.map {
                    Set($0.receiveMetadata).union($0.receivePages.map(\.key))
                } ?? []
                _ = try await self.refreshLocalTransferState(keys: affectedKeys)
            } catch is CancellationError {
                return
            } catch {
                finalReason += String(localized: " 中断后的本地提交未能完成：\(error.localizedDescription)")
            }
            guard Task.isCancelled == false else { return }
            switch termination {
            case .cancelled:
                self.state = .cancelled(self.currentPlan.map(self.result(for:)) ?? self.emptyResult)
            case .interrupted:
                let result = self.currentPlan.map(self.result(for:)) ?? self.emptyResult
                self.state = .interrupted(DeviceSyncInterruption(
                    reason: finalReason,
                    result: result,
                    completedGalleryCount: self.progressCompletedGalleries,
                    rolledBackGalleryCount: self.progressRolledBackGalleries
                ))
            }
            self.progressPlan = nil
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

    private func recordTransportInfo(_ info: DeviceSyncTransportInfo) {
        transportInfo = info
        transportDescription = info.label
        deviceSyncLogger.info("Device sync transport ready: \(info.label, privacy: .public)")
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

struct DeviceSyncWireTransferReport: Sendable {
    let transportInfo: DeviceSyncTransportInfo
    let duration: TimeInterval
    let applicationBytes: Int64
    let retransmittedBytes: Int64
    let smoothedRTTMilliseconds: Double
}

protocol DeviceSyncStreamConnection: AnyObject, Sendable {
    func start() async throws
    func start(timeout: Duration) async throws
    func send(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64
    func enqueue(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64
    func enqueueRaw(_ data: Data) async throws -> Int64
    func flush() async throws -> Int64
    func receive() async throws -> DeviceSyncWireFrame
    func receivePayload(expected: DeviceSyncMessageType) async throws -> Data
    func expect(_ expected: DeviceSyncMessageType) async throws
    func receiveExactly(_ count: Int64, consume: @Sendable (Data) async throws -> Void) async throws
    nonisolated func sendSynchronously(_ type: DeviceSyncMessageType, payload: Data) throws
    nonisolated func cancel()
    func currentTransportInfo() async -> DeviceSyncTransportInfo
    func collectTransferReport() async -> DeviceSyncWireTransferReport?
}

actor DeviceSyncWireConnection: DeviceSyncStreamConnection {

    private struct PendingSend: Sendable {
        let data: Data
        let mediaByteCount: Int64
    }

    private static let maximumRawChunk = DeviceSyncCoordinator.maximumPageChunkBytes
    /// TCP and Network.framework normally report a real disconnect directly.
    /// This is a last-resort watchdog for one bounded segment that stops
    /// making progress without producing an error.
    private static let stalledTransferTimeout: Duration = .seconds(60)
    private static let slowTransferWarningDelay: Duration = .seconds(30)
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
        let gate = DeviceSyncContinuationGate<Void>()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.succeed(())
                    case let .failed(error):
                        gate.fail(DeviceSyncError.network(error.localizedDescription))
                    case .cancelled:
                        gate.fail(CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            gate.fail(CancellationError())
            connection.cancel()
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
        let byteCount = sends.reduce(0) { $0 + $1.data.count }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.sendBatchUnbounded(sends) }
            group.addTask {
                try await Task.sleep(for: Self.slowTransferWarningDelay)
                deviceSyncLogger.warning(
                    "Device sync send window is still pending after 30 seconds: \(byteCount, privacy: .public) bytes"
                )
                try await Task.sleep(for: Self.stalledTransferTimeout - Self.slowTransferWarningDelay)
                deviceSyncLogger.error(
                    "Device sync send window stalled: \(byteCount, privacy: .public) bytes"
                )
                self.cancel()
                throw DeviceSyncError.idleTimeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { return }
            return result
        }
    }

    private func sendBatchUnbounded(_ sends: [PendingSend]) async throws {
        let gate = DeviceSyncContinuationGate<Void>()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                gate.install(continuation)
                connection.batch {
                    for send in sends.dropLast() {
                        connection.send(content: send.data, completion: .idempotent)
                    }
                    guard let last = sends.last else {
                        gate.succeed(())
                        return
                    }
                    connection.send(content: last.data, completion: .contentProcessed { error in
                        if let error {
                            gate.fail(DeviceSyncError.network(error.localizedDescription))
                        } else {
                            gate.succeed(())
                        }
                    })
                }
            }
        } onCancel: {
            gate.fail(CancellationError())
            connection.cancel()
        }
    }

    func receive() async throws -> DeviceSyncWireFrame {
        let header = try await receiveExactlyData(count: DeviceSyncWireFrame.headerByteCount)
        guard let type = DeviceSyncMessageType(rawValue: header[header.startIndex]) else {
            throw DeviceSyncError.unexpectedMessage
        }
        let length = header.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        return DeviceSyncWireFrame(type: type, payload: try await receiveExactlyData(count: Int(length)))
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

    func currentTransportInfo() -> DeviceSyncTransportInfo {
        guard let path = connection.currentPath else { return Self.makeTransportInfo(interface: nil) }
        if path.usesInterfaceType(.wiredEthernet) {
            return DeviceSyncTransportInfo(
                kind: .wiredEthernet,
                displayName: String(localized: "有线以太网"),
                isFallback: true
            )
        }
        if path.usesInterfaceType(.wifi) {
            return DeviceSyncTransportInfo(
                kind: .localNetwork,
                displayName: String(localized: "本地 Wi-Fi（正在确认路径）"),
                isFallback: true
            )
        }
        return Self.makeTransportInfo(interface: nil)
    }

    func collectTransferReport() async -> DeviceSyncWireTransferReport? {
        nil
    }

    nonisolated private static func makeTransportInfo(interface: NWInterface?) -> DeviceSyncTransportInfo {
        guard let interface else {
            return DeviceSyncTransportInfo(
                kind: .localNetwork,
                displayName: String(localized: "本地网络"),
                isFallback: true
            )
        }
        if interface.name.lowercased().hasPrefix("awdl") {
            return DeviceSyncTransportInfo(
                kind: .applePeerToPeerWiFi,
                displayName: String(localized: "Apple 点对点 Wi-Fi（AWDL）"),
                interfaceName: interface.name,
                isFallback: true
            )
        }
        switch interface.type {
        case .wifi:
            return DeviceSyncTransportInfo(
                kind: .infrastructureWiFi,
                displayName: String(localized: "局域网 Wi-Fi"),
                interfaceName: interface.name,
                isFallback: true
            )
        case .wiredEthernet:
            return DeviceSyncTransportInfo(
                kind: .wiredEthernet,
                displayName: String(localized: "有线以太网"),
                interfaceName: interface.name,
                isFallback: true
            )
        default:
            return DeviceSyncTransportInfo(
                kind: .localNetwork,
                displayName: String(localized: "本地网络"),
                interfaceName: interface.name,
                isFallback: true
            )
        }
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
                try await Task.sleep(for: Self.slowTransferWarningDelay)
                deviceSyncLogger.warning(
                    "Device sync receive is still pending after 30 seconds for up to \(maximumLength, privacy: .public) bytes"
                )
                try await Task.sleep(for: Self.stalledTransferTimeout - Self.slowTransferWarningDelay)
                deviceSyncLogger.error(
                    "Device sync receive stalled while waiting for up to \(maximumLength, privacy: .public) bytes"
                )
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
        let gate = DeviceSyncContinuationGate<Data>()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                connection.receive(
                    minimumIncompleteLength: max(1, min(minimumLength, maximumLength)),
                    maximumLength: max(1, maximumLength)
                ) { data, _, isComplete, error in
                    if let error {
                        gate.fail(DeviceSyncError.network(error.localizedDescription))
                    } else if let data, data.isEmpty == false {
                        gate.succeed(data)
                    } else if isComplete {
                        gate.fail(DeviceSyncError.network("连接已关闭"))
                    } else {
                        gate.succeed(Data())
                    }
                }
            }
        } onCancel: {
            gate.fail(CancellationError())
            connection.cancel()
        }
    }
}

#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
@available(iOS 26.0, *)
private actor WiFiAwareWireConnection: DeviceSyncStreamConnection {
    private struct PendingSend: Sendable {
        let data: Data
        let mediaByteCount: Int64
    }

    private let connection: NetworkConnection<TCP>
    private var started = false
    private var pendingSends: [PendingSend] = []
    private var pendingByteCount = 0
    private var pendingMediaByteCount: Int64 = 0

    init(connection: NetworkConnection<TCP>) {
        self.connection = connection
    }

    func start() async throws {
        guard started == false else { return }
        // A one-to-one NetworkConnection starts lazily. Awaiting the first
        // empty stream send establishes the datapath without adding a frame.
        try await connection.send(Data())
        started = true
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
            _ = try await group.next()
        }
    }

    @discardableResult
    func send(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64 {
        let flushed = try await flush()
        try await sendBatch([PendingSend(data: try DeviceSyncWireFrame(type: type, payload: payload).encoded(), mediaByteCount: 0)])
        return flushed
    }

    @discardableResult
    func enqueue(_ type: DeviceSyncMessageType, payload: Data) async throws -> Int64 {
        try await enqueue(PendingSend(
            data: try DeviceSyncWireFrame(type: type, payload: payload).encoded(),
            mediaByteCount: 0
        ))
    }

    @discardableResult
    func enqueueRaw(_ data: Data) async throws -> Int64 {
        guard data.isEmpty == false, data.count <= DeviceSyncCoordinator.maximumPageChunkBytes else {
            throw DeviceSyncError.transferNotPlanned
        }
        return try await enqueue(PendingSend(data: data, mediaByteCount: Int64(data.count)))
    }

    @discardableResult
    func flush() async throws -> Int64 {
        guard pendingSends.isEmpty == false else { return 0 }
        let sends = pendingSends
        let mediaBytes = pendingMediaByteCount
        pendingSends.removeAll(keepingCapacity: true)
        pendingByteCount = 0
        pendingMediaByteCount = 0
        try await sendBatch(sends)
        return mediaBytes
    }

    private func enqueue(_ send: PendingSend) async throws -> Int64 {
        pendingSends.append(send)
        pendingByteCount += send.data.count
        pendingMediaByteCount += send.mediaByteCount
        return pendingByteCount >= DeviceSyncCoordinator.sendWindowBytes ? try await flush() : 0
    }

    private func sendBatch(_ sends: [PendingSend]) async throws {
        guard let last = sends.last else { return }
        for send in sends.dropLast() {
            connection.sendIdempotent(send.data)
        }
        try await connection.send(last.data)
    }

    func receive() async throws -> DeviceSyncWireFrame {
        let header = try await receiveExactlyData(DeviceSyncWireFrame.headerByteCount)
        guard let type = DeviceSyncMessageType(rawValue: header[header.startIndex]) else {
            throw DeviceSyncError.unexpectedMessage
        }
        let length = header.dropFirst().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        return DeviceSyncWireFrame(type: type, payload: try await receiveExactlyData(Int(length)))
    }

    func receivePayload(expected: DeviceSyncMessageType) async throws -> Data {
        let frame = try await receive()
        guard frame.type == expected else { throw DeviceSyncError.unexpectedMessage }
        return frame.payload
    }

    func expect(_ expected: DeviceSyncMessageType) async throws {
        guard try await receive().type == expected else { throw DeviceSyncError.unexpectedMessage }
    }

    func receiveExactly(
        _ count: Int64,
        consume: @Sendable (Data) async throws -> Void
    ) async throws {
        var remaining = count
        while remaining > 0 {
            let maximum = min(DeviceSyncCoordinator.maximumPageChunkBytes, Int(remaining))
            let message = try await connection.receive(atLeast: 1, atMost: maximum)
            guard message.content.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            remaining -= Int64(message.content.count)
            try await consume(message.content)
        }
    }

    private func receiveExactlyData(_ count: Int) async throws -> Data {
        guard count >= 0, count <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            let message = try await connection.receive(atLeast: 1, atMost: count - data.count)
            guard message.content.isEmpty == false else { throw DeviceSyncError.network("连接提前关闭") }
            data.append(message.content)
        }
        return data
    }

    nonisolated func sendSynchronously(_ type: DeviceSyncMessageType, payload: Data) throws {
        connection.sendIdempotent(try DeviceSyncWireFrame(type: type, payload: payload).encoded())
    }

    nonisolated func cancel() {
        connection.sendIdempotent(Data(), endOfStream: true)
    }

    func currentTransportInfo() -> DeviceSyncTransportInfo {
        DeviceSyncTransportInfo(
            kind: .wifiAware,
            displayName: String(localized: "Wi-Fi Aware"),
            isFallback: false
        )
    }

    func collectTransferReport() async -> DeviceSyncWireTransferReport? {
        guard let report = try? await connection.dataTransferReport() else { return nil }
        let path = report.aggregatePathReport
        return DeviceSyncWireTransferReport(
            transportInfo: currentTransportInfo(),
            duration: report.duration,
            applicationBytes: Int64(clamping: path.receivedApplicationByteCount + path.sentApplicationByteCount),
            retransmittedBytes: Int64(clamping: path.retransmittedTransportByteCount),
            smoothedRTTMilliseconds: path.transportSmoothedRTT * 1_000
        )
    }
}
#endif

enum DeviceSyncMessageType: UInt8, Sendable {
    case hello = 1
    case approval = 2
    case manifest = 3
    case galleryBegin = 4
    case metadata = 5
    case pageHeader = 6
    case galleryFinished = 7
    case transferFinished = 8
    case directionReceived = 9
    case syncStart = 10
    case cancel = 11
    case error = 12
    case translationBegin = 13
    case translationPage = 14
    case translationFinished = 15
}

struct DeviceSyncWireFrame: Sendable {
    static let headerByteCount = 5
    let type: DeviceSyncMessageType
    let payload: Data

    init(type: DeviceSyncMessageType, payload: Data) {
        self.type = type
        self.payload = payload
    }

    func encoded() throws -> Data {
        guard payload.count <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        var result = Data(capacity: Self.headerByteCount + payload.count)
        result.append(type.rawValue)
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(payload)
        return result
    }

    static func decodeEncoded(_ data: Data) throws -> Self {
        guard data.count >= headerByteCount,
              let type = DeviceSyncMessageType(rawValue: data[data.startIndex]) else {
            throw DeviceSyncError.unexpectedMessage
        }
        let length = data.dropFirst().prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= DeviceSyncCoordinator.maximumControlFrameBytes else {
            throw DeviceSyncError.controlFrameTooLarge
        }
        guard data.count == headerByteCount + Int(length) else {
            throw DeviceSyncError.unexpectedMessage
        }
        return DeviceSyncWireFrame(type: type, payload: Data(data.dropFirst(headerByteCount)))
    }
}
