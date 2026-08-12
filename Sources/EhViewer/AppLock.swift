import Foundation
import LocalAuthentication

@MainActor
enum AppLockService {
    static func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解锁 EhViewer 以查看本地阅读记录和下载内容"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
