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
