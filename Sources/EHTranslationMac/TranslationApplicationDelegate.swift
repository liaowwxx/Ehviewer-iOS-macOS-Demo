#if os(macOS)
import AppKit

/// NSApplication's deferred termination keeps the run loop alive while draining.
@MainActor
public final class TranslationApplicationDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let coordinator = TranslationCoordinator.shared
        guard coordinator.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "翻译任务仍在运行"
        alert.informativeText = "可以等待已开始的队列完成，或停止任务并退出。中断任务会保留，之后可手动重试。"
        alert.addButton(withTitle: "取消退出")
        alert.addButton(withTitle: "完成当前队列后退出")
        alert.addButton(withTitle: "停止任务并退出")
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            coordinator.drainAndQuit { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        case .alertThirdButtonReturn:
            coordinator.stopAndQuit { sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        default: return .terminateCancel
        }
    }
}
#endif
