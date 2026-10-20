import AppKit

/// Opt-in launch evidence for local integration checks. No account information
/// or reset history is recorded, and normal launches do not write any report.
@MainActor
final class LaunchReport {
    private var events: [[String: Any]] = []
    private let url: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--launch-report"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()

    func record(_ event: String, statusItemVisible: Bool, hasStatusButton: Bool, cardVisible: Bool) {
        guard let url else { return }
        events.append(["event": event, "statusItemVisible": statusItemVisible,
                       "hasStatusButton": hasStatusButton, "cardVisible": cardVisible])
        do {
            let report: [String: Any] = ["version": AppIdentity.version, "pid": ProcessInfo.processInfo.processIdentifier,
                                        "bundlePath": Bundle.main.bundlePath, "events": events]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("启动验证记录写入失败：\(error.localizedDescription)\n".utf8))
        }
    }
}
