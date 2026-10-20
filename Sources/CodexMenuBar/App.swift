import AppKit
import SwiftUI
import Combine
import CodexQuotaCore
import Darwin

@main
struct CodexMenuBarApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--check") {
            Task {
                do {
                    let service = try CodexService()
                    print("使用的 Codex CLI：\(service.executable.path)")
                    let snapshot = try await service.readUsage()
                    print("连接成功 · \(snapshot.menuBarTitle) · \(snapshot.resetSummary)")
                    for window in snapshot.core?.windows ?? [] {
                        print("\(window.label)：剩余 \(window.remaining.map { String(format: "%.0f%%", $0) } ?? "未知")")
                    }
                    print("只读检查完成，未使用 reset。")
                    exit(0)
                } catch {
                    try? FileHandle.standardError.write(contentsOf: Data("\((error as? QuotaError)?.localizedDescription ?? "连接失败")\n".utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }
        if PreviewSupport.handleCommandLine() { return }
        let app = NSApplication.shared
        // Reopen the owner instead of silently disappearing when another copy is
        // launched. Launch Services delivers the reopen event to that instance.
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != getpid() && !$0.isTerminated }),
           let url = existing.bundleURL {
            Task { @MainActor in
                do {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = true
                    configuration.appleEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                        eventID: AEEventID(kAEReopenApplication), targetDescriptor: nil,
                        returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                    _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("无法唤起已运行的 Codexccino：\(error.localizedDescription)\n".utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

private struct MissingService: QuotaService {
    func readUsage() async throws -> UsageSnapshot { throw QuotaError.cliMissing }
    func consumeReset(key: String, accountID: String, retry: Bool) async throws -> ResetOutcome { throw QuotaError.cliMissing }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = CoffeePopover()
    private var controller: QuotaController!
    private var timer: Timer?
    private var subscription: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?
    private let launchReport = LaunchReport()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let service: any QuotaService = (try? CodexService()) ?? MissingService()
        controller = QuotaController(service: service)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Codex …"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: .leftMouseDown)
            button.setAccessibilityLabel("Codex 剩余用量")
        }
        subscription = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus(); self?.popover.updateSize() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.controller.refresh(); self?.updateStatus() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.controller.refresh() }
        }
        // Keep AppKit's event loop outside an async main task so its delegate and UI tasks run normally.
        Task { await controller.refresh(); updateStatus() }
        recordLaunch("launched")
    }
    private func updateStatus() {
        statusItem.button?.title = controller.statusTitle
        statusItem.button?.toolTip = "Codex 剩余用量 · 点击查看周期、reset 与操作记录"
    }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.toggle(model: controller, relativeTo: button) {
            Task { await controller.refresh() }
        }
    }
    private func showPopover() {
        guard let button = statusItem?.button, controller != nil, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(model: controller, relativeTo: button)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard controller != nil else { return false }
        showPopover()
        Task { await controller.refresh() }
        recordLaunch("reopened")
        return true
    }
    private func recordLaunch(_ event: String) {
        launchReport.record(event, statusItemVisible: statusItem?.isVisible == true,
                            hasStatusButton: statusItem?.button?.window != nil, cardVisible: popover.isShown)
    }
    func applicationWillTerminate(_ notification: Notification) {
        popover.close()
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }
}
