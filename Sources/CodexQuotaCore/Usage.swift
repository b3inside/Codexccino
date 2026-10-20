import Foundation

public struct UsageWindow: Codable, Sendable, Equatable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
    public var label: String {
        switch windowDurationMins {
        case 300: return "5 小时"
        case 10_080: return "每周"
        case let minutes? where minutes >= 1_440 && minutes % 1_440 == 0: return "\(minutes / 1_440) 天"
        case let minutes? where minutes >= 60 && minutes % 60 == 0: return "\(minutes / 60) 小时"
        case let minutes? where minutes > 0: return "\(minutes) 分钟"
        default: return "额度周期"
        }
    }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

public struct UsageBucket: Codable, Sendable, Equatable {
    public let limitId: String?
    public let limitName: String?
    public let normalModelSlug: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let planType: String?
    public let spendControlReached: Bool?
    public var windows: [UsageWindow] { [primary, secondary].compactMap { $0 } }
    public var remaining: Double? { windows.compactMap(\.remaining).min() }
}

public struct ResetCredit: Codable, Sendable, Equatable {
    public let id: String
    public let status: String
    public let expiresAt: Double?
}

public struct ResetCredits: Codable, Sendable, Equatable {
    public let availableCount: Int?
    public let credits: [ResetCredit]?
    public var count: Int? { availableCount.flatMap { $0 >= 0 ? $0 : nil } }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let accountId: String?
    public let ordinaryUsageAllowed: Bool?
    public let rateLimits: UsageBucket?
    public let rateLimitsByLimitId: [String: UsageBucket]?
    public let rateLimitResetCredits: ResetCredits?

    public var core: UsageBucket? {
        if let bucket = rateLimitsByLimitId?["codex"] { return bucket }
        guard let rateLimits, rateLimits.limitId == nil || rateLimits.limitId == "codex" else { return nil }
        return rateLimits
    }
    public var otherBuckets: [(String, UsageBucket)] {
        (rateLimitsByLimitId ?? [:]).filter { $0.key != "codex" }.sorted { $0.key < $1.key }
    }
    public var resetCount: Int? { rateLimitResetCredits?.count }
    public var resetSummary: String {
        guard let resetCount else { return "暂时无法获取 reset 数量" }
        return resetCount == 0 ? "当前没有可用 reset" : "\(resetCount) 次可用 reset"
    }
    public var menuBarTitle: String {
        guard let remaining = core?.remaining else { return "Codex —" }
        let marker = ordinaryUsageAllowed == false || core?.spendControlReached == true ? " !" : ""
        return "Codex \(CoffeeLevel.displayedPercent(remaining)!)%\(marker)"
    }
}

public enum QuotaError: Error, LocalizedError, Sendable, Equatable {
    case cliMissing, connection, timeout, invalidResponse, rpc(Int), accountMissing, accountChanged, noCredit, countUnknown, persistence
    case loginRequired, subscriptionLoginRequired, rpcFailure(Int, String, String)
    public var errorDescription: String? {
        switch self {
        case .cliMissing: return "未找到 Codex CLI。请先安装并登录 Codex。"
        case .connection: return "无法连接 Codex。请确认 Codex 已登录，再点刷新。"
        case .timeout: return "Codex 请求超时，请检查网络后重试。"
        case .invalidResponse: return "Codex 返回了无法识别的数据，请检查 CLI 版本。"
        case .rpc(let code): return "Codex 请求失败（\(code)）。请检查登录状态与网络。"
        case .loginRequired: return "Codex CLI 尚未登录。请在终端运行 codex login，用 ChatGPT 账户登录后刷新。"
        case .subscriptionLoginRequired: return "当前 CLI 使用 API key 或其他认证，无法读取 ChatGPT 订阅额度。请用 ChatGPT 账户登录 Codex CLI 后刷新。"
        case .rpcFailure(let code, let method, let reason):
            if reason == "notLoggedIn" { return QuotaError.loginRequired.localizedDescription }
            if reason == "chatgptRequired" { return "此用量接口需要 ChatGPT 账户认证，请检查 Codex CLI 的登录方式。" }
            let stage = method == "initialize" ? "初始化" : (method == "account/rateLimitResetCredit/consume" ? "reset" : "用量查询")
            if code == -32601 || reason == "parameters" { return "当前 Codex CLI 不兼容\(stage)接口（\(code)），请更新 CLI 后重试。" }
            return "Codex 拒绝了\(stage)请求（\(code)）。请核对 CLI 版本与账户登录方式。"
        case .accountMissing: return "无法确认当前账户，暂不能使用 reset。请刷新或重新登录 Codex。"
        case .accountChanged: return "Codex 账户已切换，请刷新后重新确认。"
        case .noCredit: return "当前没有可用 reset"
        case .countUnknown: return "暂时无法获取 reset 数量，请稍后刷新。"
        case .persistence: return "无法保存 reset 记录。请检查本机磁盘空间及文件权限。"
        }
    }
}

public enum ResetOutcome: String, Codable, Sendable {
    case pending, uncertain, reset, alreadyRedeemed, nothingToReset, noCredit
    public var isUncertain: Bool { self == .pending || self == .uncertain }
    public var label: String {
        switch self {
        case .pending, .uncertain: return "结果待确认（可能已生效）"
        case .reset: return "成功，已使用 1 次 reset"
        case .alreadyRedeemed: return "成功，此次 reset 此前已生效"
        case .nothingToReset: return "未使用：当前没有符合重置条件的用量周期"
        case .noCredit: return "未使用：当前没有可用 reset"
        }
    }
}

public protocol QuotaService: Sendable {
    func readUsage() async throws -> UsageSnapshot
    func consumeReset(key: String, accountID: String, retry: Bool) async throws -> ResetOutcome
}
