/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import EHDownloads
import EHNetworking
import EHPersistence

enum AppDataResetter {
    private struct Target {
        let url: URL
        let name: String
    }

    private static var targets: [Target] {
        [
            Target(url: GalleryCoverLoader.defaultRootURL, name: "缩略图缓存"),
            Target(url: GalleryCacheStore.defaultRootURL, name: "画廊缓存"),
            Target(url: DownloadFileStore.defaultRootURL, name: "已下载画廊文件"),
            Target(url: ModelContainerFactory.persistentStoreURL, name: "SwiftData 本地数据库")
        ]
    }

    static func removeAll() async throws {
        await GalleryCoverLoader.shared.removeAll()

        let fileManager = FileManager.default
        for target in targets {
            guard fileManager.fileExists(atPath: target.url.path) else { continue }
            do {
                try fileManager.removeItem(at: target.url)
            } catch {
                throw AppDataResetError.failed(target.name, error)
            }
        }
    }
}

private enum AppDataResetError: LocalizedError {
    case failed(String, Error)

    var errorDescription: String? {
        switch self {
        case let .failed(name, error):
            return "清除\(name)失败：\(error.localizedDescription)"
        }
    }
}
