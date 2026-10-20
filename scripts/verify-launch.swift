import AppKit
import CoreGraphics

/// Launches the production app through Launch Services; only reads launch
/// diagnostics and window metadata. Never clicks or consumes a reset.
@main
struct VerifyLaunch {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw Failure.message("Usage: verify-launch APP_PATH OUTPUT_DIRECTORY")
        }
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reportURL = directory.appendingPathComponent("launch-events.json")
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { throw Failure.message("Missing bundle identifier") }
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in existing { guard app.terminate() else { throw Failure.message("Existing app refused termination") } }
        try await wait { existing.allSatisfy(\.isTerminated) }
        if FileManager.default.fileExists(atPath: reportURL.path) { try FileManager.default.removeItem(at: reportURL) }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.allowsRunningApplicationSubstitution = false
        configuration.arguments = ["--launch-report", reportURL.path]
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        try await wait { (try? events(reportURL).count) ?? 0 >= 1 }
        let first = try events(reportURL)[0]
        guard first["event"] as? String == "launched", first["statusItemVisible"] as? Bool == true,
              first["hasStatusButton"] as? Bool == true, first["cardVisible"] as? Bool == false,
              app.isFinishedLaunching, !app.isTerminated else { throw Failure.message("Cold launch failed") }

        // Same launch request Finder makes for an already-running app.
        let reopened = try await NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        try await wait { (try? events(reportURL).count) ?? 0 >= 2 }
        guard reopened.processIdentifier == app.processIdentifier,
              try events(reportURL).last?["cardVisible"] as? Bool == true else {
            throw Failure.message("Finder reopen did not reveal existing card")
        }
        try await wait { visibleCard(pid: app.processIdentifier) }

        // Bypass Launch Services' automatic reuse to exercise our actual guard.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("codex-launch-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.copyItem(at: appURL, to: copy)
        let count = try events(reportURL).count
        let duplicate = Process()
        duplicate.executableURL = copy.appendingPathComponent("Contents/MacOS/CodexMenuBar")
        try duplicate.run()
        try await wait { !duplicate.isRunning }
        guard duplicate.terminationStatus == 0 else { throw Failure.message("Duplicate handoff failed") }
        try await wait { (try? events(reportURL).count) ?? 0 > count }
        guard try events(reportURL).last?["cardVisible"] as? Bool == true,
              visibleCard(pid: app.processIdentifier), !app.isTerminated,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count == 1 else {
            throw Failure.message("Duplicate launch did not preserve one visible owner")
        }
        // The process must survive after the launcher and duplicate have returned.
        try await Task.sleep(for: .seconds(2))
        guard !app.isTerminated else { throw Failure.message("App did not remain running") }
        let output: [String: Any] = ["pid": app.processIdentifier, "bundlePath": appURL.path,
            "coldLaunch": true, "startupCardClosed": true, "finderReopen": true,
            "duplicateCopyReopensOwner": true, "singleInstance": true, "cardOnScreen": true,
            "survivesLauncherReturn": true, "realResetExecuted": false]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("launch-verification.json"), options: .atomic)
        print("启动验证通过：冷启动、Finder 重开、另一副本唤起、单实例和持续运行。PID \(app.processIdentifier)")
    }

    @MainActor
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure.message("Timed out waiting for launch state")
    }
    private static func events(_ url: URL) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return object?["events"] as? [[String: Any]] ?? []
    }
    private static func visibleCard(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? Int32 == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return false }
            return bounds["Width"] as? Int == 360 && bounds["Height"] as? Int == 460
        }
    }
    private enum Failure: Error { case message(String) }
}
