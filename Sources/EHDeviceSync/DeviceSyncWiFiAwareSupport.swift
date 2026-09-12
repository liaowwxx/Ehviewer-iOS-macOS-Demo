/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
import WiFiAware
#endif

public enum DeviceSyncWiFiAwareSupport {
    public static var isAvailable: Bool {
#if EH_ENABLE_WIFI_AWARE && os(iOS) && canImport(WiFiAware)
        if #available(iOS 26.0, *) {
            return WACapabilities.supportedFeatures.contains(.wifiAware)
                && WAPublishableService.allServices[DeviceSyncCoordinator.serviceType] != nil
                && WASubscribableService.allServices[DeviceSyncCoordinator.serviceType] != nil
        }
#endif
        return false
    }

    public static var fallbackReason: String? {
        guard isAvailable == false else { return nil }
#if os(macOS)
        return String(localized: "macOS 不提供 Wi-Fi Aware，已使用 Apple 点对点 Wi-Fi或局域网。")
#else
        return String(localized: "当前构建未启用 Wi-Fi Aware，已使用兼容连接。")
#endif
    }
}
