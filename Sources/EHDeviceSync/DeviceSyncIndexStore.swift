/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation
import EHDomain

/// A small, rebuildable sidecar index for device synchronization.
///
/// The snapshot is replaced atomically after a rebuild. Ordinary changes are
/// appended to a journal so downloading one page does not rewrite a file that
/// contains every gallery in the library. The index is a cache: if any write
/// cannot be persisted, synchronization is disabled until the user rebuilds
/// it from the authoritative SwiftData records and media files.
public actor DeviceSyncIndexStore: DeviceSyncIndexSink {
    private enum EventOperation: String, Codable, Sendable {
        case upsertMediaPage
        case removeMediaPage
        case removeMedia
        case upsertMetadata
        case removeMetadata
    }

    private struct Event: Codable, Sendable {
        let operation: EventOperation
        let key: GalleryKey
        let pageIndex: Int?
        let byteCount: Int64?
        let metadata: DeviceSyncMetadataDigest?
    }

    private let directory: URL
    private let snapshotURL: URL
    private let journalURL: URL
    private let markerURL: URL
    private var didLoad = false
    private var indexStatus: DeviceSyncIndexStatus = .needsBuild
    private var entries: [GalleryKey: DeviceSyncIndexEntry] = [:]
    private var journalEventCount = 0
    private var journalByteCount = 0
    private var rebuildInProgress = false
    private var pendingRebuildEvents: [Event] = []

    public init(root: URL? = nil) {
        var resolvedRoot = root ?? Self.defaultRootURL
        directory = resolvedRoot
        snapshotURL = resolvedRoot.appendingPathComponent("index.json")
        journalURL = resolvedRoot.appendingPathComponent("index.log")
        markerURL = resolvedRoot.appendingPathComponent("ready.marker")
        try? FileManager.default.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? resolvedRoot.setResourceValues(values)
    }

    public func status() async -> DeviceSyncIndexStatus {
        ensureLoaded()
        return indexStatus
    }

    public func snapshot() async throws -> DeviceSyncIndexSnapshot {
        ensureLoaded()
        guard indexStatus == .ready else { throw DeviceSyncIndexError.notReady }
        return try makeSnapshot()
    }

    public func beginRebuild() async throws {
        ensureLoaded()
        guard rebuildInProgress == false else { return }
        do {
            try writeMarker("rebuilding")
        } catch {
            indexStatus = .needsBuild
            throw DeviceSyncIndexError.persistenceFailed
        }
        rebuildInProgress = true
        pendingRebuildEvents.removeAll(keepingCapacity: true)
        indexStatus = .rebuilding
    }

    public func finishRebuild(with snapshot: DeviceSyncIndexSnapshot) async throws {
        ensureLoaded()
        guard rebuildInProgress else {
            throw DeviceSyncIndexError.persistenceFailed
        }

        var rebuiltEntries = snapshot.entriesByKey
        do {
            for event in pendingRebuildEvents {
                try apply(event, to: &rebuiltEntries)
            }
            let finalSnapshot = try DeviceSyncIndexSnapshot(entries: Array(rebuiltEntries.values))
            try persistSnapshot(finalSnapshot)
            entries = finalSnapshot.entriesByKey
            pendingRebuildEvents.removeAll(keepingCapacity: false)
            rebuildInProgress = false
            indexStatus = .ready
        } catch {
            rebuildInProgress = false
            pendingRebuildEvents.removeAll(keepingCapacity: false)
            indexStatus = .needsBuild
            throw DeviceSyncIndexError.persistenceFailed
        }
    }

    public func cancelRebuild() async {
        ensureLoaded()
        guard rebuildInProgress else { return }
        rebuildInProgress = false
        pendingRebuildEvents.removeAll(keepingCapacity: false)
        indexStatus = .needsBuild
        try? writeMarker("rebuilding")
    }

    public func upsertMediaPage(key: GalleryKey, pageIndex: Int, byteCount: Int64) async {
        ensureLoaded()
        guard let page = try? DeviceSyncPageEntry(pageIndex: pageIndex, byteCount: byteCount) else {
            indexStatus = .needsBuild
            return
        }
        await record(Event(
            operation: .upsertMediaPage,
            key: key,
            pageIndex: page.pageIndex,
            byteCount: page.byteCount,
            metadata: nil
        ))
    }

    /// Persists a gallery's validated pages in one journal write. Import and
    /// device-sync commits use this to avoid an fsync for every individual
    /// media file while preserving the same crash-rebuild behavior.
    public func upsertMediaPages(key: GalleryKey, pages: [DeviceSyncPageEntry]) async {
        guard pages.isEmpty == false else { return }
        await record(pages.map { page in
            Event(
                operation: .upsertMediaPage,
                key: key,
                pageIndex: page.pageIndex,
                byteCount: page.byteCount,
                metadata: nil
            )
        })
    }

    /// Commits all index state for one validated gallery with one journal
    /// append and one durability boundary.
    public func upsertGallery(
        key: GalleryKey,
        pages: [DeviceSyncPageEntry],
        metadata: DeviceSyncMetadataDigest
    ) async {
        var events = pages.map { page in
            Event(
                operation: .upsertMediaPage,
                key: key,
                pageIndex: page.pageIndex,
                byteCount: page.byteCount,
                metadata: nil
            )
        }
        events.append(Event(
            operation: .upsertMetadata,
            key: key,
            pageIndex: nil,
            byteCount: nil,
            metadata: metadata
        ))
        await record(events)
    }

    public func removeGallery(_ key: GalleryKey) async {
        await record([
            Event(operation: .removeMedia, key: key, pageIndex: nil, byteCount: nil, metadata: nil),
            Event(operation: .removeMetadata, key: key, pageIndex: nil, byteCount: nil, metadata: nil)
        ])
    }

    public func removeMediaPage(key: GalleryKey, pageIndex: Int) async {
        await record(Event(
            operation: .removeMediaPage,
            key: key,
            pageIndex: pageIndex,
            byteCount: nil,
            metadata: nil
        ))
    }

    public func removeMedia(for key: GalleryKey) async {
        await record(Event(
            operation: .removeMedia,
            key: key,
            pageIndex: nil,
            byteCount: nil,
            metadata: nil
        ))
    }

    public func upsertMetadata(_ entry: DeviceSyncIndexMetadataEntry) async {
        await record(Event(
            operation: .upsertMetadata,
            key: entry.key,
            pageIndex: nil,
            byteCount: nil,
            metadata: entry.metadata
        ))
    }

    public func removeMetadata(for key: GalleryKey) async {
        await record(Event(
            operation: .removeMetadata,
            key: key,
            pageIndex: nil,
            byteCount: nil,
            metadata: nil
        ))
    }

    private func record(_ event: Event) async {
        await record([event])
    }

    private func record(_ events: [Event]) async {
        guard events.isEmpty == false else { return }
        ensureLoaded()
        if rebuildInProgress {
            pendingRebuildEvents.append(contentsOf: events)
            return
        }
        // A missing or dirty index is rebuilt from authoritative storage. Do
        // not spend one journal write per download while waiting for that
        // first rebuild.
        guard indexStatus == .ready else { return }
        do {
            var encoded = Data()
            for event in events {
                try apply(event, to: &entries)
                encoded.append(try JSONEncoder().encode(event))
                encoded.append(0x0A)
            }
            try appendToJournal(encoded)
            journalEventCount += events.count
            journalByteCount += encoded.count
            if journalEventCount >= 512 || journalByteCount >= 1_024 * 1_024 {
                try persistSnapshot(makeSnapshot())
            }
        } catch {
            indexStatus = .needsBuild
        }
    }

    private func ensureLoaded() {
        guard didLoad == false else { return }
        didLoad = true
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard String(data: try Data(contentsOf: markerURL), encoding: .utf8) == "ready" else {
                indexStatus = .needsBuild
                return
            }
            let decodedDocument = try JSONDecoder().decode(DeviceSyncIndexSnapshot.self, from: Data(contentsOf: snapshotURL))
            guard decodedDocument.formatVersion == DeviceSyncIndexSnapshot.currentFormatVersion else {
                throw DeviceSyncIndexError.invalidSnapshot
            }
            let document = try DeviceSyncIndexSnapshot(
                entries: decodedDocument.entries,
                formatVersion: decodedDocument.formatVersion
            )
            entries = document.entriesByKey
            if FileManager.default.fileExists(atPath: journalURL.path) {
                let journal = try String(decoding: Data(contentsOf: journalURL), as: UTF8.self)
                for line in journal.split(whereSeparator: \.isNewline) {
                    guard let data = line.data(using: .utf8) else { throw DeviceSyncIndexError.invalidSnapshot }
                    let event = try JSONDecoder().decode(Event.self, from: data)
                    try apply(event, to: &entries)
                    journalEventCount += 1
                    journalByteCount += data.count + 1
                }
            }
            indexStatus = .ready
        } catch {
            entries.removeAll(keepingCapacity: false)
            journalEventCount = 0
            journalByteCount = 0
            indexStatus = .needsBuild
        }
    }

    private func makeSnapshot() throws -> DeviceSyncIndexSnapshot {
        try DeviceSyncIndexSnapshot(entries: Array(entries.values))
    }

    private func apply(
        _ event: Event,
        to entries: inout [GalleryKey: DeviceSyncIndexEntry]
    ) throws {
        let current = entries[event.key]
        let pages = current?.pages ?? []
        let metadata = current?.metadata
        let updated: DeviceSyncIndexEntry
        switch event.operation {
        case .upsertMediaPage:
            guard let pageIndex = event.pageIndex, let byteCount = event.byteCount else {
                throw DeviceSyncIndexError.invalidSnapshot
            }
            let page = try DeviceSyncPageEntry(pageIndex: pageIndex, byteCount: byteCount)
            var pagesByIndex = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageIndex, $0) })
            pagesByIndex[page.pageIndex] = page
            updated = try DeviceSyncIndexEntry(key: event.key, pages: Array(pagesByIndex.values), metadata: metadata)
        case .removeMediaPage:
            guard let pageIndex = event.pageIndex else { throw DeviceSyncIndexError.invalidSnapshot }
            updated = try DeviceSyncIndexEntry(
                key: event.key,
                pages: pages.filter { $0.pageIndex != pageIndex },
                metadata: metadata
            )
        case .removeMedia:
            updated = try DeviceSyncIndexEntry(key: event.key, pages: [], metadata: metadata)
        case .upsertMetadata:
            guard let eventMetadata = event.metadata else { throw DeviceSyncIndexError.invalidSnapshot }
            updated = try DeviceSyncIndexEntry(key: event.key, pages: pages, metadata: eventMetadata)
        case .removeMetadata:
            updated = try DeviceSyncIndexEntry(key: event.key, pages: pages, metadata: nil)
        }
        if updated.pages.isEmpty && updated.metadata == nil {
            entries.removeValue(forKey: event.key)
        } else {
            entries[event.key] = updated
        }
    }

    private func persistSnapshot(_ snapshot: DeviceSyncIndexSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try replaceFile(
            with: encoder.encode(snapshot),
            at: snapshotURL
        )
        try writeMarker("ready")
        try Data().write(to: journalURL, options: .atomic)
        journalEventCount = 0
        journalByteCount = 0
    }

    private func appendToJournal(_ data: Data) throws {
        if FileManager.default.fileExists(atPath: journalURL.path) == false {
            try Data().write(to: journalURL, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    private func writeMarker(_ value: String) throws {
        try Data(value.utf8).write(to: markerURL, options: .atomic)
    }

    private func replaceFile(with data: Data, at url: URL) throws {
        let temporaryURL = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try data.write(to: temporaryURL, options: .atomic)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }
    }

    public static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("EhViewer/DeviceSyncIndex", isDirectory: true)
    }
}
