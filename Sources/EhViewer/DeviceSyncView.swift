/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI
import EHDeviceSync
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
import WiFiAware
import DeviceDiscoveryUI
#endif

struct DeviceSyncView: View {
    @Environment(AppModel.self) private var model
    @State private var pairingInput = ""

    var body: some View {
        content
            .navigationTitle("设备间同步")
            .toolbar {
                if canCancelSync {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", role: .cancel, action: model.deviceSync.cancelSync)
                    }
                }
            }
            .task(id: "\(model.isLoadingDownloads)-\(model.localDownloadLoadError == nil)") {
                if !model.isLoadingDownloads, model.localDownloadLoadError == nil,
                   model.deviceSync.hasActiveSession == false {
                    model.deviceSync.start()
                }
            }
            .onDisappear {
                if model.deviceSync.hasActiveSession == false {
                    model.deviceSync.stop()
                }
            }
            .onChange(of: shouldRefreshDownloads) { _, shouldRefresh in
                if shouldRefresh {
                    Task { await model.refreshDownloadsAfterDeviceSync() }
                }
            }
    }

    private var shouldRefreshDownloads: Bool {
        switch model.deviceSync.state {
        case .completed(_), .cancelled(_), .interrupted(_): true
        default: false
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingDownloads {
            ProgressView("正在加载下载内容…")
        } else if let error = model.localDownloadLoadError {
            ContentUnavailableView {
                Label("无法加载本地内容", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("重试") { model.retryLocalDownloadLoad() }
            }
        } else {
            readyContent
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        switch model.deviceSync.state {
        case .indexRequired:
            VStack(spacing: 16) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.largeTitle)
                Text("需要先建立同步索引")
                    .font(.headline)
                Button("建立索引", systemImage: "arrow.triangle.2.circlepath") {
                    model.runFileOperation {
                        await model.buildDeviceSyncIndex()
                        if model.isDeviceSyncIndexSetupRequired == false {
                            model.deviceSync.start()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .idle, .discovering:
            discoveringView
        case .awaitingPairingCode:
            DeviceSyncPairingView(code: $pairingInput) {
                model.deviceSync.acceptPairing(code: pairingInput)
            }
        case .connecting:
            if let pairingCode = model.deviceSync.pairingCode {
                VStack(spacing: 16) {
                    Text("请在另一台设备输入此验证码")
                        .font(.headline)
                    Text(pairingCode)
                        .font(.largeTitle.monospaced().bold())
                        .tracking(6)
                        .accessibilityLabel("验证码 \(pairingCode)")
                    ProgressView("正在等待安全连接…")
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("正在建立安全连接…")
            }
        case .awaitingRemoteConfirmation:
            VStack(spacing: 12) {
                ProgressView()
                Text("等待 \(model.deviceSync.remoteDeviceName) 确认")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .awaitingConnectionConfirmation:
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.largeTitle)
                Text("已建立加密连接")
                Button("确认此设备", systemImage: "checkmark.shield") {
                    model.deviceSync.confirmConnection()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .preparing(phase):
            VStack(spacing: 12) {
                ProgressView()
                Label(phaseTitle(phase), systemImage: phaseSystemImage(phase))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .awaitingSyncConfirmation(preview):
            previewView(preview)
        case let .syncing(progress):
            progressView(progress)
        case let .interrupted(interruption):
            interruptionView(interruption)
        case let .cancelled(result):
            resultView(
                title: "同步已取消",
                systemImage: "xmark.circle",
                description: "已完整提交的画廊和页面均已保留。",
                result: result
            )
        case let .completed(result):
            resultView(
                title: "同步完成",
                systemImage: "checkmark.circle",
                description: "两台设备已完成本地漫画数据合并。",
                result: result
            )
        case let .failed(message):
            ContentUnavailableView("同步失败", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var discoveringView: some View {
        List {
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware) && canImport(DeviceDiscoveryUI)
            if #available(iOS 26.0, *),
               DeviceSyncWiFiAwareSupport.isAvailable,
               let publishable = WAPublishableService.allServices[DeviceSyncCoordinator.serviceType],
               let subscribable = WASubscribableService.allServices[DeviceSyncCoordinator.serviceType] {
                Section("Wi-Fi Aware（优先）") {
                    DevicePicker(
                        .wifiAware(.connecting(to: .userSpecifiedDevices, from: subscribable)),
                        onSelect: { endpoint in
                            model.deviceSync.connectWiFiAware(to: endpoint)
                        },
                        label: {
                            Label("选择并连接设备", systemImage: "wifi")
                        },
                        fallback: {
                            Label("系统设备选择器不可用", systemImage: "wifi.slash")
                                .foregroundStyle(.secondary)
                        }
                    )
                    DevicePairingView(
                        .wifiAware(.connecting(to: publishable, from: .userSpecifiedDevices)),
                        label: {
                            Label("允许另一台设备配对", systemImage: "person.badge.plus")
                        },
                        fallback: {
                            Label("系统配对界面不可用", systemImage: "person.crop.circle.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    )
                }
            }
#endif
            Section("附近的 EhViewer 设备") {
                if model.deviceSync.peers.isEmpty {
                    HStack {
                        ProgressView()
                        Text("正在搜索本地网络…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.deviceSync.peers) { peer in
                        Button {
                            model.deviceSync.connect(to: peer)
                        } label: {
                            Label(peer.displayName, systemImage: "ipad.and.iphone")
                        }
                    }
                }
            }
        }
    }

    private func previewView(_ preview: DeviceSyncPreview) -> some View {
        List {
            Section {
                previewSummary(
                    galleries: preview.receiveGalleryCount,
                    pages: preview.receivePageCount,
                    bytes: preview.receiveBytes
                )
            } header: {
                Label("接收", systemImage: "arrow.down.circle")
            }
            Section {
                previewSummary(
                    galleries: preview.sendGalleryCount,
                    pages: preview.sendPageCount,
                    bytes: preview.sendBytes
                )
            } header: {
                Label("发送", systemImage: "arrow.up.circle")
            }
            Section {
                Button(
                    "确认并开始同步",
                    systemImage: "arrow.triangle.2.circlepath",
                    action: model.confirmDeviceSync
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func previewSummary(galleries: Int, pages: Int, bytes: Int64) -> some View {
        VStack {
            LabeledContent("漫画", value: "\(galleries) 本")
            LabeledContent("页面", value: "\(pages) 页")
            LabeledContent("数据", value: byteString(bytes))
        }
        .accessibilityElement(children: .combine)
    }

    private func progressView(_ progress: DeviceSyncProgress) -> some View {
        List {
            Section {
                if let transport = progress.transportInfo {
                    LabeledContent("实际连接", value: transport.label)
                }
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("设备同步总进度")
                        .accessibilityValue(
                            "\(byteString(progress.completedBytes)) / \(byteString(progress.totalBytes))"
                        )
                } else {
                    ProgressView()
                        .accessibilityLabel(phaseTitle(progress.phase))
                }
                LabeledContent("总进度") {
                    Text("\(byteString(progress.completedBytes)) / \(byteString(progress.totalBytes))")
                        .monospacedDigit()
                }
                LabeledContent("预计剩余", value: etaText(progress))
                if let speed = progress.bytesPerSecond {
                    LabeledContent("传输速度", value: "\(byteString(Int64(speed)))/秒")
                }
                LabeledContent("已处理漫画") {
                    Text("\(progress.completedGalleries)/\(progress.totalGalleries) 本")
                        .monospacedDigit()
                }
                if progress.totalLocalGalleries > 0,
                   progress.phase == .committing {
                    LabeledContent("本地提交") {
                        Text("\(progress.locallyProcessedGalleries)/\(progress.totalLocalGalleries) 本")
                            .monospacedDigit()
                    }
                }
            } header: {
                Label(phaseTitle(progress.phase), systemImage: phaseSystemImage(progress.phase))
            }
            if let title = progress.currentGalleryTitle {
                Section("当前项目") {
                    LabeledContent("漫画", value: title)
                    if let pageIndex = progress.currentPageIndex {
                        LabeledContent("页面", value: "第 \(pageIndex + 1) 页")
                    }
                }
            }
            if progress.totalSendPages > 0 {
                Section("发送") {
                    directionProgress(
                        completedPages: progress.sentPages,
                        totalPages: progress.totalSendPages,
                        completedBytes: progress.sentBytes,
                        totalBytes: progress.totalSendBytes
                    )
                }
            }
            if progress.totalReceivePages > 0 {
                Section("接收") {
                    directionProgress(
                        completedPages: progress.receivedPages,
                        totalPages: progress.totalReceivePages,
                        completedBytes: progress.receivedBytes,
                        totalBytes: progress.totalReceiveBytes
                    )
                }
            }
        }
    }

    private func directionProgress(
        completedPages: Int,
        totalPages: Int,
        completedBytes: Int64,
        totalBytes: Int64
    ) -> some View {
        VStack {
            ProgressView(value: totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0)
            LabeledContent("页面") {
                Text("\(completedPages)/\(totalPages) 页")
                    .monospacedDigit()
            }
            LabeledContent("数据") {
                Text("\(byteString(completedBytes)) / \(byteString(totalBytes))")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func interruptionView(_ interruption: DeviceSyncInterruption) -> some View {
        ContentUnavailableView {
            Label("同步已中断", systemImage: "wifi.exclamationmark")
        } description: {
            VStack(spacing: 8) {
                Text(interruption.reason)
                Text("已发送 \(interruption.result.sentGalleryCount) 本，接收 \(interruption.result.receivedGalleryCount) 本。")
            }
        } actions: {
            Button("重新搜索设备") { model.deviceSync.start() }
        }
    }

    private func resultView(
        title: String,
        systemImage: String,
        description: String,
        result: DeviceSyncResult
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            VStack(spacing: 8) {
                Text(description)
                Text("发送 \(result.sentGalleryCount) 本，接收 \(result.receivedGalleryCount) 本。")
            }
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func etaText(_ progress: DeviceSyncProgress) -> String {
        guard progress.phase == .sending || progress.phase == .receiving else {
            return phaseTitle(progress.phase)
        }
        guard let seconds = progress.estimatedRemainingSeconds else { return "正在估算" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    private func phaseTitle(_ phase: DeviceSyncPhase) -> String {
        switch phase {
        case .generatingManifest: "生成清单"
        case .waitingForConfirmation: "等待确认"
        case .sending: "正在发送"
        case .receiving: "正在接收"
        case .committing: "正在提交"
        case .comparingResults: "正在再次比对"
        }
    }

    private func phaseSystemImage(_ phase: DeviceSyncPhase) -> String {
        switch phase {
        case .generatingManifest: "list.bullet.rectangle"
        case .waitingForConfirmation: "person.crop.circle.badge.clock"
        case .sending: "arrow.up.circle"
        case .receiving: "arrow.down.circle"
        case .committing: "internaldrive"
        case .comparingResults: "arrow.triangle.2.circlepath"
        }
    }

    private var canCancelSync: Bool {
        switch model.deviceSync.state {
        case .awaitingPairingCode,
             .connecting,
             .awaitingRemoteConfirmation,
             .awaitingConnectionConfirmation,
             .preparing,
             .awaitingSyncConfirmation,
             .syncing:
            true
        default:
            false
        }
    }
}
