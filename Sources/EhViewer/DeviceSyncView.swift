/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI
import EHDeviceSync

struct DeviceSyncView: View {
    @Environment(AppModel.self) private var model
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
                guard case .completed = state else { return }
                Task { await model.refreshDownloadsAfterDeviceSync() }
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
        case let .awaitingSyncConfirmation(preview):
            previewView(preview)
        case let .syncing(progress):
            progressView(progress)
        case .completed:
            ContentUnavailableView("同步完成", systemImage: "checkmark.circle", description: Text("两台设备已完成本地漫画数据并集合并。"))
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
        Form {
            Section("同步预览") {
                LabeledContent("接收漫画", value: "\(preview.receiveGalleryCount) 本")
                LabeledContent("接收页面", value: "\(preview.receivePageCount) 页")
                LabeledContent("接收数据", value: ByteCountFormatter.string(fromByteCount: preview.receiveBytes, countStyle: .file))
                LabeledContent("发送漫画", value: "\(preview.sendGalleryCount) 本")
                LabeledContent("发送页面", value: "\(preview.sendPageCount) 页")
                LabeledContent("发送数据", value: ByteCountFormatter.string(fromByteCount: preview.sendBytes, countStyle: .file))
            }
            Section {
                Button("确认并开始同步", systemImage: "arrow.triangle.2.circlepath") {
                    model.deviceSync.confirmSync()
                }
            }
        }
    }

    private func progressView(_ progress: DeviceSyncProgress) -> some View {
        VStack(spacing: 16) {
            Group {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal)
            Text("已完成 \(progress.completedPages)/\(progress.totalPages) 页")
            Text(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
