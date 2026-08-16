/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#if os(iOS)
import Foundation
import Photos
import EHDownloads

enum PhotoLibrarySaver {
    static func save(_ mediaData: Data, kind: DownloadMediaKind) async throws {
        let authorization = await authorizationStatus()
        guard authorization == .authorized || authorization == .limited else {
            throw NSError(
                domain: "EhViewer.PhotoLibrarySaver",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "没有照片添加权限，请在系统设置中允许 EhViewer 写入照片。"]
            )
        }

        try await performChanges(with: mediaData, kind: kind)
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard currentStatus == .notDetermined else { return currentStatus }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func performChanges(with mediaData: Data, kind: DownloadMediaKind) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: kind == .video ? .video : .photo, data: mediaData, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? NSError(
                        domain: "EhViewer.PhotoLibrarySaver",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "系统照片未完成保存图片。"]
                    ))
                }
            }
        }
    }
}
#endif
