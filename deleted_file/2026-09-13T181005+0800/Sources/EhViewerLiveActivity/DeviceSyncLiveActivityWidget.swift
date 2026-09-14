/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import ActivityKit
import EHDomain
import SwiftUI
import WidgetKit

@main
struct DeviceSyncLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeviceSyncLiveActivityWidget()
    }
}

struct DeviceSyncLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeviceSyncLiveActivityAttributes.self) { context in
            DeviceSyncLockScreenView(
                state: context.state,
                attributes: context.attributes
            )
            .widgetURL(URL(string: "ehviewer://device-sync"))
            .activityBackgroundTint(.blue.opacity(0.16))
            .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("同步", systemImage: icon(for: context.state))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let fraction = context.state.fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.headline.monospacedDigit())
                    } else {
                        ProgressView()
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.remoteDeviceName)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(statusText(for: context.state))
                            .font(.subheadline)
                            .lineLimit(1)
                        if let fraction = context.state.fraction {
                            ProgressView(value: fraction)
                        }
                        HStack {
                            Text(byteSummary(for: context.state))
                            Spacer()
                            Text(gallerySummary(for: context.state))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(for: context.state))
            } compactTrailing: {
                if let fraction = context.state.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                } else {
                    Image(systemName: "ellipsis")
                }
            } minimal: {
                Image(systemName: icon(for: context.state))
            }
            .widgetURL(URL(string: "ehviewer://device-sync"))
        }
        .contentMarginsDisabled()
    }
}

private struct DeviceSyncLockScreenView: View {
    let state: DeviceSyncActivityContentState
    let attributes: DeviceSyncLiveActivityAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("设备同步", systemImage: icon(for: state))
                    .font(.headline)
                Spacer(minLength: 12)
                Text(state.remoteDeviceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(statusText(for: state))
                .font(.subheadline)
                .lineLimit(1)

            if let title = state.currentGalleryTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let fraction = state.fraction {
                ProgressView(value: fraction)
            }

            HStack {
                Text(byteSummary(for: state))
                Spacer(minLength: 12)
                Text(gallerySummary(for: state))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if let transport = state.transportDescription {
                Label(transport, systemImage: "wifi")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("设备同步：\(statusText(for: state))")
        .accessibilityValue("\(byteSummary(for: state))，\(gallerySummary(for: state))，来自 \(attributes.localDeviceName)")
    }
}

private func statusText(for state: DeviceSyncActivityContentState) -> String {
    if let message = state.message, message.isEmpty == false {
        return message
    }
    return switch state.phase {
    case .connecting: "正在建立安全连接…"
    case .waitingForConfirmation: "等待确认…"
    case .generatingManifest: "正在生成同步清单…"
    case .sending: "正在发送…"
    case .receiving: "正在接收…"
    case .verifying: "正在校验…"
    case .committing: "正在提交…"
    case .comparingResults: "正在再次比对…"
    case .completed: "同步完成"
    case .cancelled: "同步已取消"
    case .interrupted: "同步已中断"
    case .failed: "同步失败"
    }
}

private func icon(for state: DeviceSyncActivityContentState) -> String {
    switch state.phase {
    case .connecting: "lock.shield"
    case .waitingForConfirmation: "person.crop.circle.badge.clock"
    case .generatingManifest: "list.bullet.rectangle"
    case .sending: "arrow.up.circle"
    case .receiving: "arrow.down.circle"
    case .verifying: "checkmark.shield"
    case .committing: "internaldrive"
    case .comparingResults: "arrow.triangle.2.circlepath"
    case .completed: "checkmark.circle.fill"
    case .cancelled: "xmark.circle"
    case .interrupted: "wifi.exclamationmark"
    case .failed: "exclamationmark.triangle"
    }
}

private func byteSummary(for state: DeviceSyncActivityContentState) -> String {
    guard state.totalBytes > 0 else { return "准备中" }
    return "\(ByteCountFormatter.string(fromByteCount: state.completedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: state.totalBytes, countStyle: .file))"
}

private func gallerySummary(for state: DeviceSyncActivityContentState) -> String {
    guard state.totalGalleries > 0 else { return "准备中" }
    return "\(state.completedGalleries)/\(state.totalGalleries) 本"
}
