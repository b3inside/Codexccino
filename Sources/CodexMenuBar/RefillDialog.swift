import AppKit
import CodexQuotaCore

@MainActor
enum RefillDialog {
    /// The optional hook is used only by the offline UI verifier. Production
    /// always uses the same native alert and this single response gate.
    static func present(for model: QuotaController, onPresent: ((NSAlert) -> Void)? = nil) async {
        await model.prepareReset()
        guard let approval = model.confirmation else { return }
        let parent = NSApp.keyWindow
        let parentLevel = parent?.level
        if parent is NSPanel { parent?.level = .normal }
        let alert = NSAlert()
        alert.messageText = approval.title
        alert.informativeText = approval.message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: approval.isRetry ? "确认此次结果" : "使用 1 次 reset")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.window.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        onPresent?(alert)
        let response = alert.runModal()
        alert.window.orderOut(nil)
        // No other modal response, closure, Escape or abort may consume a reset.
        if response == .alertSecondButtonReturn {
            await model.confirmReset(approval.id)
        } else {
            model.cancelReset()
        }
        if parent?.isVisible == true {
            if let parentLevel { parent?.level = parentLevel }
            parent?.makeKeyAndOrderFront(nil)
        }
    }
}
