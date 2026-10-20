import AppKit
import SwiftUI
import CodexQuotaCore

/// Explicit, offline UI fixtures. Never contacts Codex or opens the real reset journal.
@MainActor
enum PreviewSupport {
    private static var window: NSWindow?

    static func handleCommandLine() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(where: { $0 == "--render-previews" || $0 == "--preview" || $0 == "--verify-cancel" || $0 == "--verify-toggle" }),
              arguments.indices.contains(index + 1) else { return false }
        let mode = arguments[index]
        let value = arguments[index + 1]
        let app = NSApplication.shared
        app.setActivationPolicy(mode == "--preview" ? .regular : .accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        Task { @MainActor in
            do {
                if mode == "--verify-toggle" {
                    try await verifyToggle(at: URL(fileURLWithPath: value, isDirectory: true))
                    app.terminate(nil)
                } else if mode == "--verify-cancel" {
                    try await verifyCancellation(at: URL(fileURLWithPath: value, isDirectory: true))
                    app.terminate(nil)
                } else if mode == "--render-previews" {
                    let directory = URL(fileURLWithPath: value, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for name in ["0", "3", "10", "20", "30", "40", "50", "62", "70", "80", "90", "97", "100",
                                 "unknown", "error", "stale", "multiple", "no-credits", "no-account", "uncertain"] {
                        let model = try await makeModel(name)
                        let view = show(model, title: "离线预览 · \(name)")
                        // Let AppKit lay out native controls before taking a bitmap.
                        try await Task.sleep(for: .milliseconds(80))
                        view.layoutSubtreeIfNeeded()
                        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                            throw PreviewError.render
                        }
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        guard let png = bitmap.representation(using: .png, properties: [:]) else {
                            throw PreviewError.render
                        }
                        try png.write(to: directory.appendingPathComponent("\(name).png"))
                    }
                    print("离线预览已保存：\(directory.path)")
                    app.terminate(nil)
                } else {
                    _ = show(try await makeModel(value), title: "\(AppIdentity.name) · 离线预览")
                    app.activate(ignoringOtherApps: true)
                }
            } catch {
                FileHandle.standardError.write(Data("离线预览失败：\(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
        return true
    }

    private static func show(_ model: QuotaController, title: String) -> CoffeeCardView {
        window?.close()
        let hosting = CoffeeCardView(model: model)
        let preview = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable],
                               backing: .buffered, defer: false)
        preview.title = title
        preview.isReleasedWhenClosed = false
        preview.appearance = NSAppearance(named: .darkAqua)
        preview.contentView = hosting
        preview.center()
        preview.makeKeyAndOrderFront(nil)
        window = preview
        return hosting
    }

    /// Exercises the production NSAlert and its response gate against a local
    /// service that cannot contact Codex. Every scenario must submit zero resets.
    private static func verifyCancellation(at directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var results: [[String: Any]] = []
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "Codpresso 测试"
        defer { NSStatusBar.system.removeStatusItem(status) }
        for scenario in ["cancel-button", "return-default", "abort", "retry-cancel"] {
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data("""
            {"accountId":"offline-cancel-check","rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":10080}},
            "rateLimitResetCredits":{"availableCount":3,"credits":[]}}
            """.utf8))
            let service = PreviewService(snapshot: snapshot)
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("codex-cancel-\(UUID().uuidString)")
            let store = ResetStore(url: scratch.appendingPathComponent("history.json"))
            var prior = ResetRecord(accountID: "offline-cancel-check")
            prior.outcome = scenario == "retry-cancel" ? .uncertain : .reset
            try store.save(["offline-cancel-check": prior])
            let before = try Data(contentsOf: store.url)
            let model = QuotaController(service: service, store: store)
            await model.refresh()
            let popover = CoffeePopover()
            guard let button = status.button else { throw PreviewError.assertion("Missing status button") }
            popover.show(model: model, relativeTo: button)
            try await Task.sleep(for: .milliseconds(80))
            if let content = NSApp.keyWindow?.contentView,
               let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("\(scenario)-card.png"))
            }
            var approvalID: String?
            var defaultIsCancel = false
            var snapshotSaved = false
            var keyHandled = true
            await RefillDialog.present(for: model) { alert in
                approvalID = model.confirmation?.id
                let cancellationTimer = Timer(timeInterval: 0.15, repeats: false) { _ in
                    MainActor.assumeIsolated {
                    defaultIsCancel = alert.buttons[0].title == "取消"
                        && alert.buttons[0].keyEquivalent == "\r"
                        && alert.buttons[1].keyEquivalent.isEmpty
                    if let content = alert.window.contentView,
                       let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                        content.cacheDisplay(in: content.bounds, to: bitmap)
                        if let png = bitmap.representation(using: .png, properties: [:]) {
                            do {
                                try png.write(to: directory.appendingPathComponent("\(scenario).png"))
                                snapshotSaved = true
                            } catch {}
                        }
                    }
                    switch scenario {
                    case "return-default":
                        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                                       windowNumber: alert.window.windowNumber, context: nil,
                                                       characters: "\r", charactersIgnoringModifiers: "\r",
                                                       isARepeat: false, keyCode: 36) {
                            keyHandled = alert.window.performKeyEquivalent(with: event)
                            if !keyHandled { NSApp.abortModal() }
                        } else { keyHandled = false; NSApp.abortModal() }
                    case "abort": NSApp.abortModal()
                    default: alert.buttons[0].performClick(nil)
                    }
                    }
                }
                RunLoop.main.add(cancellationTimer, forMode: .modalPanel)
            }
            guard popover.isShown, model.confirmation == nil, let approvalID,
                  defaultIsCancel, snapshotSaved, keyHandled else {
                throw PreviewError.assertion("Native cancellation failed: \(scenario)")
            }
            // Even a late callback carrying the cancelled approval must do nothing.
            await model.confirmReset(approvalID)
            let count = await service.consumptionCount()
            let after = try Data(contentsOf: store.url)
            guard count == 0, model.snapshot?.resetCount == 3, before == after,
                  model.latest?.key == prior.key else {
                throw PreviewError.assertion("Cancellation mutated reset state: \(scenario)")
            }
            results.append(["scenario": scenario, "consumeRequests": count,
                            "remainingResetCount": 3, "historyUnchanged": true,
                            "defaultAction": "cancel", "cardStillVisible": popover.isShown, "passed": true])
            popover.close()
            try FileManager.default.removeItem(at: scratch)
        }
        let output: [String: Any] = ["version": AppIdentity.version, "service": "offline-only",
                                    "realResetExecuted": false, "results": results]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("cancel-verification.json"))
        print("原生取消验证通过：4 个场景，消费请求 0 次，重置次数仍为 3，历史文件逐字节不变。")
    }

    private static func verifyToggle(at directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = try await makeModel("62")
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = status.button else { throw PreviewError.assertion("Missing status button") }
        button.title = "Codpresso 切换测试"
        button.sendAction(on: .leftMouseDown)
        let target = ToggleTarget(model: model, button: button)
        button.target = target
        button.action = #selector(ToggleTarget.click)
        defer {
            target.popover.close()
            NSStatusBar.system.removeStatusItem(status)
        }
        var results: [[String: Any]] = []
        func expect(_ shown: Bool, _ scenario: String) throws {
            guard target.popover.isShown == shown else { throw PreviewError.assertion(scenario) }
            results.append(["scenario": scenario, "shown": shown, "passed": true])
        }

        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(true, "first-click-opens")
        guard let buttonWindow = button.window else { throw PreviewError.assertion("Missing anchor window") }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // Reproduce the original ordering: outside monitor and focus loss arrive
        // before the status-button action, while the card is already visible.
        target.popover.handleGlobalMouseDown(at: NSPoint(x: anchor.midX, y: anchor.midY), primary: true)
        NSApp.keyWindow?.resignKey()
        try await Task.sleep(for: .milliseconds(40))
        try expect(true, "anchor-mousedown-does-not-close-early")
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(false, "second-click-closes")
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(true, "third-click-reopens")

        if let oldPanel = NSApp.keyWindow {
            target.popover.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: oldPanel))
        }
        button.performClick(nil)
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(true, "old-focus-callback-cannot-close-reopened-card")
        button.performClick(nil)
        try expect(false, "next-click-closes")
        button.performClick(nil)
        target.popover.handleGlobalMouseDown(at: NSPoint(x: anchor.midX, y: anchor.minY - 600), primary: true)
        try expect(false, "outside-click-closes")
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(80))
        try expect(true, "click-after-outside-dismissal-reopens")

        let output: [String: Any] = ["version": AppIdentity.version, "service": "offline-only",
                                    "realResetExecuted": false, "results": results]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("toggle-verification.json"))
        print("菜单栏切换验证通过：首次展开、再次收起、重开、外部点击和迟到焦点回调均符合预期。")
    }

    @MainActor
    private final class ToggleTarget: NSObject {
        let popover = CoffeePopover()
        let model: QuotaController
        let button: NSStatusBarButton
        init(model: QuotaController, button: NSStatusBarButton) {
            self.model = model
            self.button = button
        }
        @objc func click() { popover.toggle(model: model, relativeTo: button) }
    }

    private static func makeModel(_ name: String) async throws -> QuotaController {
        let percent = min(100, max(0, Double(name) ?? 62))
        let remaining = name == "unknown" ? "\"usedPercent\":null" : "\"usedPercent\":\(100 - percent)"
        let secondary = name == "multiple" ? ",\"secondary\":{\"usedPercent\":18,\"windowDurationMins\":300,\"resetsAt\":1792393200}" : ""
        let account = name == "no-account" ? "" : "\"accountId\":\"offline-preview\","
        let count = name == "no-credits" ? 0 : 3
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data("""
        {\(account)"ordinaryUsageAllowed":true,"rateLimitsByLimitId":{
        "codex":{"primary":{\(remaining),"windowDurationMins":10080,"resetsAt":1792458000}\(secondary)},
        "reserve":{"limitName":"gpt-reserve","primary":{"usedPercent":0}}},
        "rateLimitResetCredits":{"availableCount":\(count),"credits":[]}}
        """.utf8))
        let service = PreviewService(snapshot: snapshot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-coffee-preview-\(UUID().uuidString)")
        let store = ResetStore(url: directory.appendingPathComponent("history.json"))
        defer { try? FileManager.default.removeItem(at: directory) }
        if name != "no-account" {
            var record = ResetRecord(accountID: "offline-preview", attemptedAt: Date(timeIntervalSince1970: 1792305120),
                                     outcome: name == "uncertain" ? .uncertain : .reset)
            record.finishedAt = name == "uncertain" ? nil : record.attemptedAt
            try store.save(["offline-preview": record])
        }
        if name == "error" { await service.setFailure() }
        let model = QuotaController(service: service, store: store)
        await model.refresh()
        if name == "stale" {
            await service.setFailure()
            await model.refresh()
        }
        return model
    }
}

private enum PreviewError: Error { case render, assertion(String) }

private actor PreviewService: QuotaService {
    let snapshot: UsageSnapshot
    var fails = false
    var consumeCalls = 0
    init(snapshot: UsageSnapshot) { self.snapshot = snapshot }
    func setFailure() { fails = true }
    func consumptionCount() -> Int { consumeCalls }
    func readUsage() async throws -> UsageSnapshot {
        if fails { throw QuotaError.timeout }
        return snapshot
    }
    func consumeReset(key: String, accountID: String, retry: Bool) async throws -> ResetOutcome {
        consumeCalls += 1
        // UI inspection remains offline even when the confirmation is accepted.
        return retry ? .alreadyRedeemed : .nothingToReset
    }
}
