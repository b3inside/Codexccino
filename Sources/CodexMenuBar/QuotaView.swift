import AppKit
import SwiftUI
import CodexQuotaCore

enum CoffeeTheme {
    static var nsBackground: NSColor { NSColor(srgbRed: 36 / 255, green: 29 / 255, blue: 24 / 255, alpha: 1) }
    static let background = Color(nsColor: nsBackground)
    static let primary = Color(red: 1, green: 0.92, blue: 0.81)
    static let secondary = Color(red: 0.76, green: 0.72, blue: 0.68)
    static let labelFont = Font.system(size: 15, weight: .medium)
}

struct QuotaView: View {
    @ObservedObject var model: QuotaController

    private var window: UsageWindow? { model.snapshot?.core?.displayWindow }
    private var percent: Int? { CoffeeLevel.displayedPercent(window?.remaining) }
    private var retry: Bool { model.latest?.outcome.isUncertain == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppIdentity.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(CoffeeTheme.primary)
                Spacer()
                Text("v\(AppIdentity.version)")
                    .font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(CoffeeTheme.secondary)
                    .accessibilityLabel("版本 \(AppIdentity.version)")
            }.padding(.bottom, 6)

            VStack(spacing: 0) {
                CoffeeCupView(remaining: window?.remaining)
                    .frame(width: 230, height: 160)
                    .accessibilityHidden(true)
                    .padding(.bottom, -18)
                Text(percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CoffeeTheme.primary)
                    .frame(height: 62)
                    .accessibilityLabel(percent.map { "剩余用量 \($0)%" } ?? "剩余用量暂不可用")
                Text(window.map { $0.windowDurationMins == 10_080 ? "本周剩余" : "\($0.label)剩余" }
                     ?? (model.busy ? "正在读取用量…" : "用量暂不可用"))
                    .font(CoffeeTheme.labelFont)
                    .padding(.top, 2)
                Text(supportingLine)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 8)
                    .accessibilityLabel(supportingLine)
                    .help(supportingLine)
                if let extra = additionalWindows {
                    Text(extra)
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .padding(.top, 5)
                }
            }
            .foregroundStyle(CoffeeTheme.secondary)
            .frame(maxWidth: .infinity)

            Rectangle().fill(CoffeeTheme.secondary.opacity(0.25)).frame(height: 1)
                .padding(.top, 34).padding(.bottom, 16)

            HStack {
                Text(model.snapshot?.resetCount.map { "还有\($0)次重置续杯" } ?? "重置续杯次数暂不可用")
                    .font(CoffeeTheme.labelFont)
                    .lineLimit(1)
                    .help(resetDetails)
                Spacer(minLength: 8)
                Button(action: requestRefill) {
                    Text(retry ? "确认结果…" : "续一杯")
                        .font(.system(size: 12))
                        .frame(minWidth: retry ? 76 : 64, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RefillButtonStyle())
                .disabled(!model.canReset)
                .help(retry ? "确认上次重置结果，仍需再次确认" : "使用一次 reset 重置额度，点击后需确认")
                .accessibilityLabel(retry ? "确认上次重置结果" : "续一杯，使用一次 reset，需确认")
            }
            .foregroundStyle(CoffeeTheme.primary)

            Text(historyLine)
                .font(.system(size: 10))
                .foregroundStyle(retry ? Color.orange : CoffeeTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let snapshot = model.snapshot,
               (snapshot.resetCount ?? 0) > 0 && snapshot.accountId == nil {
                notice("当前 CLI 未提供账户标识；更新 CLI 后可续杯。")
            }
            if model.snapshot?.ordinaryUsageAllowed == false || model.snapshot?.core?.spendControlReached == true {
                notice("账户当前限制使用，恢复状态以 Codex 为准。")
            }
            if let error = model.historyError ?? model.errorMessage { notice(error) }
            if model.snapshot != nil && (model.errorMessage != nil || model.isStale) {
                Text("当前显示上次成功读取的数据")
                    .font(.system(size: 10)).foregroundStyle(CoffeeTheme.secondary).padding(.top, 5)
            }

            HStack(spacing: 12) {
                Text("每分钟自动刷新")
                    .font(.system(size: 10))
                    .help(model.updatedAt.map { "更新于 \(timeText($0))" } ?? "尚未更新")
                Spacer()
                if model.busy { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 16))
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(model.busy)
                .help("刷新用量").accessibilityLabel("刷新用量")
                Menu {
                    Button("打开 Codex") { openCodex() }
                    Menu("全部用量与恢复时间") {
                        if let snapshot = model.snapshot {
                            ForEach(Array((snapshot.core?.windows ?? []).enumerated()), id: \.offset) { _, item in
                                Text("\(item.label)：\(CoffeeLevel.displayedPercent(item.remaining).map { "\($0)%" } ?? "未知") · \(item.resetDate.map { dateText($0) } ?? "恢复时间未知")")
                            }
                            ForEach(snapshot.otherBuckets, id: \.0) { key, bucket in
                                Text("\(bucket.limitName == "gpt-reserve" ? "备用额度" : (bucket.limitName ?? key))：\(CoffeeLevel.displayedPercent(bucket.remaining).map { "\($0)%" } ?? "未知")")
                            }
                        } else { Text("暂无用量数据") }
                    }
                    Text(resetDetails)
                    Text(model.updatedAt.map { "更新于 \(timeText($0))" } ?? "尚未更新")
                    Button("查看本地 reset 记录") {
                        let url = model.recordURL
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    Divider()
                    Button("退出 Codex 用量") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17)).frame(width: 24, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("更多").accessibilityLabel("更多选项")
            }
            .foregroundStyle(CoffeeTheme.secondary)
            .padding(.top, 12)
        }
        .padding(16)
        .frame(width: 360)
        .background(CoffeeTheme.background)
        .preferredColorScheme(.dark)
    }

    private var supportingLine: String {
        let recovery = window?.resetDate.map { "\(dateText($0)) 恢复" } ?? "恢复时间暂不可用"
        guard let snapshot = model.snapshot else { return recovery }
        let reserve = snapshot.otherBuckets.first { $0.1.limitName == "gpt-reserve" }
            ?? snapshot.otherBuckets.first
        guard let reserve else { return recovery }
        let name = reserve.1.limitName == "gpt-reserve" ? "备用额度" : (reserve.1.limitName ?? reserve.0)
        let value = CoffeeLevel.displayedPercent(reserve.1.remaining).map { "\($0)%" } ?? "未知"
        return "\(recovery) · \(name) \(value)"
    }

    private var additionalWindows: String? {
        guard let core = model.snapshot?.core, core.windows.count > 1 else { return nil }
        // Keep every window visible; the hero uses the most constrained window.
        let others = core.windows.filter { $0 != window }
        let text = others.map { item in
            "\(item.label)剩余 \(CoffeeLevel.displayedPercent(item.remaining).map { "\($0)%" } ?? "未知")"
        }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private var resetDetails: String {
        var text = model.snapshot?.resetSummary ?? "暂时无法获取 reset 数量"
        if let expiry = model.snapshot?.rateLimitResetCredits?.credits?
            .filter({ $0.status == "available" }).compactMap(\.expiresAt).min() {
            text += " · 最早到期：\(dateText(Date(timeIntervalSince1970: expiry)))"
        }
        return text
    }

    private var historyLine: String {
        guard let record = model.latest else { return "最近重置 · 尚无操作记录" }
        let date = dateText(record.finishedAt ?? record.attemptedAt, compact: true)
        let outcome: String
        switch record.outcome {
        case .reset, .alreadyRedeemed: outcome = "成功"
        case .pending, .uncertain: outcome = "结果待确认（可能已生效）"
        case .nothingToReset: outcome = "未使用：暂无符合条件的周期"
        case .noCredit: outcome = "未使用：没有可用次数"
        }
        return "最近重置 \(date) · \(outcome)"
    }

    private func notice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.system(size: 11)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
    }

    private func requestRefill() {
        Task { await RefillDialog.present(for: model) }
    }

    private func openCodex() {
        let paths = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
        if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}

private struct RefillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(CoffeeTheme.primary.opacity(enabled ? 0.88 : 0.35))
            .background(CoffeeTheme.primary.opacity(configuration.isPressed ? 0.1 : 0.015))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(CoffeeTheme.secondary.opacity(enabled ? 0.5 : 0.2), lineWidth: 1))
    }
}

func dateText(_ date: Date, compact: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = .current
    formatter.dateFormat = compact ? "M/d HH:mm" : "M月d日 HH:mm"
    return formatter.string(from: date)
}

func timeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}
