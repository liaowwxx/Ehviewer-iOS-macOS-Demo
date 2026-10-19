#if os(macOS)
import Foundation

enum TranslationBridgeResources {
    static var directory: URL? {
        // Xcode copies this folder only when PLATFORM_NAME is macosx. Keeping it out
        // of an SPM resource bundle prevents Xcode's automatic bundle copying
        // from shipping Python resources in the iOS application.
        if let url = Bundle.main.url(forResource: "bridge", withExtension: nil) { return url }
        #if DEBUG
        let development = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/bridge")
        if FileManager.default.fileExists(atPath: development.path) { return development }
        #endif
        return nil
    }
}
#endif
