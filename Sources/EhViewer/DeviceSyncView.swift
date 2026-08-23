/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI
import EHDeviceSync

struct DeviceSyncView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var pairingInput = ""

    var body: some View {
        content
            .navigationTitle("设备间同步")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.deviceSync.cancelSync() }
                }
            }
            .onAppear { model.deviceSync.start() }
            .onDisappear { model.deviceSync.stop() }
            .onChange(of: model.deviceSync.state) { _, state in
                guard case .completed(_) = state else { return }
                Task { await model.refreshDownloadsAfterDeviceSync() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.deviceSync.interruptForBackground()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.deviceSync.state {
        case .idle, .discovering:
            discoveringView
        case .awaitingPairingCode:
            pairingView
        case .connecting:
            if let pairingCode = model.deviceSync.pairingCode {
                VStack(spacing: 16) {
                    Text("请在另一台设备输入此验证码")
                        .font(.headline)
                    Text(pairingCode)
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
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
                Text("确认后才会交换本地漫画清单。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                description: "两台设备已完成本地漫画数据并集合并。",
                result: result
            )
        case let .failed(message):
            ContentUnavailableView("同步失败", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private var discoveringView: some View {
        List {
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
            Section {
                Text("设备发现只在本页面打开期间运行，不会广播漫画、账号或 Cookie 信息。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pairingView: some View {
        Form {
            Section("输入验证码") {
                TextField("6 位数字验证码", text: $pairingInput)
#if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
#endif
                    .onChange(of: pairingInput) { _, value in
                        pairingInput = String(value.filter(\.isNumber).prefix(6))
                    }
                Button("确认设备") {
                    model.deviceSync.acceptPairing(code: pairingInput)
                }
                .disabled(pairingInput.count != 6)
            }
        }
    }

    private func previewView(_ preview: DeviceSyncPreview) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("同步预览")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        previewCard(
                            title: "接收",
                            systemImage: "arrow.down.circle",
                            galleries: preview.receiveGalleryCount,
                            pages: preview.receivePageCount,
                            bytes: preview.receiveBytes
                        )
                        previewCard(
                            title: "发送",
                            systemImage: "arrow.up.circle",
                            galleries: preview.sendGalleryCount,
                            pages: preview.sendPageCount,
                            bytes: preview.sendBytes
                        )
                    }
                    VStack(spacing: 12) {
                        previewCard(
                            title: "接收",
                            systemImage: "arrow.down.circle",
                            galleries: preview.receiveGalleryCount,
                            pages: preview.receivePageCount,
                            bytes: preview.receiveBytes
                        )
                        previewCard(
                            title: "发送",
                            systemImage: "arrow.up.circle",
                            galleries: preview.sendGalleryCount,
                            pages: preview.sendPageCount,
                            bytes: preview.sendBytes
                        )
                    }
                }
                Button("确认并开始同步", systemImage: "arrow.triangle.2.circlepath") {
                    model.deviceSync.confirmSync()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func progressView(_ progress: DeviceSyncProgress) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(phaseTitle(progress.phase), systemImage: phaseSystemImage(progress.phase))
                    .font(.title2.bold())
                if let title = progress.currentGalleryTitle {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .accessibilityLabel("当前画廊：\(title)")
                }
                if let pageIndex = progress.currentPageIndex {
                    Text("当前第 \(pageIndex + 1) 页")
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        directionProgressCard(
                            title: "发送",
                            completedPages: progress.sentPages,
                            totalPages: progress.totalSendPages,
                            completedBytes: progress.sentBytes,
                            totalBytes: progress.totalSendBytes
                        )
                        directionProgressCard(
                            title: "接收",
                            completedPages: progress.receivedPages,
                            totalPages: progress.totalReceivePages,
                            completedBytes: progress.receivedBytes,
                            totalBytes: progress.totalReceiveBytes
                        )
                    }
                    VStack(spacing: 12) {
                        directionProgressCard(
                            title: "发送",
                            completedPages: progress.sentPages,
                            totalPages: progress.totalSendPages,
                            completedBytes: progress.sentBytes,
                            totalBytes: progress.totalSendBytes
                        )
                        directionProgressCard(
                            title: "接收",
                            completedPages: progress.receivedPages,
                            totalPages: progress.totalReceivePages,
                            completedBytes: progress.receivedBytes,
                            totalBytes: progress.totalReceiveBytes
                        )
                    }
                }
                HStack {
                    Label(
                        "已完成 \(progress.completedGalleries)/\(progress.totalGalleries) 本",
                        systemImage: "books.vertical"
                    )
                    Spacer()
                    VStack(alignment: .trailing) {
                        if let speed = progress.bytesPerSecond {
                            Text("\(byteString(Int64(speed)))/秒")
                        } else {
                            Text("正在估算速度")
                        }
                        Text(etaText(progress))
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func previewCard(
        title: String,
        systemImage: String,
        galleries: Int,
        pages: Int,
        bytes: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            LabeledContent("漫画", value: "\(galleries) 本")
            LabeledContent("页面", value: "\(pages) 页")
            LabeledContent("数据", value: byteString(bytes))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func directionProgressCard(
        title: String,
        completedPages: Int,
        totalPages: Int,
        completedBytes: Int64,
        totalBytes: Int64
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ProgressView(value: totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0)
            Text("\(completedPages)/\(totalPages) 页")
            Text("\(byteString(completedBytes)) / \(byteString(totalBytes))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func interruptionView(_ interruption: DeviceSyncInterruption) -> some View {
        ContentUnavailableView {
            Label("同步已中断", systemImage: "wifi.exclamationmark")
        } description: {
            VStack(spacing: 8) {
                Text(interruption.reason)
                Text("已保留 \(interruption.completedGalleryCount) 本；已回滚当前画廊 \(interruption.rolledBackGalleryCount) 本。重新连接后会重新比对，只补传缺失内容。")
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
                Text("发送 \(result.sentGalleryCount) 本 / \(result.sentPageCount) 页，接收 \(result.receivedGalleryCount) 本 / \(result.receivedPageCount) 页。")
            }
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func etaText(_ progress: DeviceSyncProgress) -> String {
        guard progress.phase == .sending || progress.phase == .receiving else {
            return "正在\(phaseTitle(progress.phase))"
        }
        guard let seconds = progress.estimatedRemainingSeconds else { return "剩余时间正在估算" }
        return "预计剩余 \(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))"
    }

    private func phaseTitle(_ phase: DeviceSyncPhase) -> String {
        switch phase {
        case .generatingManifest: "生成清单"
        case .waitingForConfirmation: "等待确认"
        case .sending: "正在发送"
        case .receiving: "正在接收"
        case .verifying: "正在校验"
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
        case .verifying: "checkmark.shield"
        case .committing: "internaldrive"
        case .comparingResults: "arrow.triangle.2.circlepath"
        }
    }
}
