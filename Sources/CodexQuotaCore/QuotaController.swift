import Foundation
import Combine

public struct ResetConfirmation: Identifiable, Sendable {
    public let id: String
    public let record: ResetRecord
    public let isRetry: Bool
    public let availableCount: Int?
    public var title: String { isRetry ? "确认上次 reset 的结果？" : "使用 1 次 reset？" }
    public var message: String {
        if isRetry { return "将使用上次操作的同一个标识重试。如果此前已成功，不会再次消耗 reset；如果尚未执行，此次可能使用 1 次。" }
        return "当前有 \(availableCount ?? 0) 次可用 reset。本次将申请重置 Codex 用量，并消耗 1 次 reset；能否重置由账户服务判断。"
    }
}

@MainActor
public final class QuotaController: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var updatedAt: Date?
    @Published public private(set) var busy = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var historyError: String?
    @Published public private(set) var records: [String: ResetRecord] = [:]
    @Published public private(set) var confirmation: ResetConfirmation?
    private let service: any QuotaService
    private let store: ResetStore

    public init(service: any QuotaService, store: ResetStore = ResetStore()) {
        self.service = service
        self.store = store
        do { records = try store.load() }
        catch { historyError = QuotaError.persistence.localizedDescription }
    }
    public var latest: ResetRecord? { snapshot?.accountId.flatMap { records[$0] } }
    public var recordURL: URL { store.url }
    public var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 180 } ?? true }
    public var canReset: Bool {
        !busy && confirmation == nil && historyError == nil && snapshot?.accountId != nil &&
        (latest?.outcome.isUncertain == true || (snapshot?.resetCount ?? 0) > 0)
    }
    public var statusTitle: String {
        guard let snapshot else { return busy ? "Codex …" : "Codex —" }
        return snapshot.menuBarTitle + ((errorMessage != nil || isStale) ? " ·" : "")
    }

    public func refresh() async {
        guard !busy, confirmation == nil else { return }
        busy = true
        defer { busy = false }
        await loadUsage()
    }
    private func loadUsage() async {
        do {
            snapshot = try await service.readUsage()
            updatedAt = Date()
            errorMessage = nil
        } catch { errorMessage = safeMessage(error) }
    }

    /// Called by the button. A fresh read precedes the user's confirmation.
    public func prepareReset() async {
        guard !busy, confirmation == nil, historyError == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let fresh = try await service.readUsage()
            snapshot = fresh
            updatedAt = Date()
            errorMessage = nil
            guard let account = fresh.accountId, !account.isEmpty else { throw QuotaError.accountMissing }
            let previous = records[account]
            let retry = previous?.outcome.isUncertain == true
            if !retry {
                guard let count = fresh.resetCount else { throw QuotaError.countUnknown }
                guard count > 0 else { throw QuotaError.noCredit }
            }
            let record = retry ? previous! : ResetRecord(accountID: account)
            confirmation = ResetConfirmation(id: record.key, record: record, isRetry: retry, availableCount: fresh.resetCount)
        } catch { errorMessage = safeMessage(error) }
    }
    public func cancelReset() { confirmation = nil }

    /// The UI calls this only after the user explicitly confirms this attempt.
    public func confirmReset(_ id: String) async {
        guard !busy, let approved = confirmation, approved.id == id, historyError == nil else { return }
        confirmation = nil
        busy = true
        defer { busy = false }
        var record = approved.record
        record.outcome = .pending
        var saved = records
        saved[record.accountID] = record
        do {
            // Write the idempotency key BEFORE sending anything that can consume a credit.
            try store.save(saved)
            records = saved
        } catch {
            historyError = QuotaError.persistence.localizedDescription
            return
        }
        do {
            record.outcome = try await service.consumeReset(key: record.key, accountID: record.accountID, retry: approved.isRetry)
            record.finishedAt = Date()
            errorMessage = nil
        } catch {
            // Never generate a new key after a transport failure or unknown server response.
            record.outcome = .uncertain
            errorMessage = safeMessage(error)
        }
        saved[record.accountID] = record
        records = saved
        do { try store.save(saved) }
        catch { historyError = "reset 结果未能保存。已保留操作标识，请重启后确认此次结果。" }

        // A successful reset remains successful even if this read fails.
        let resetError = errorMessage
        await loadUsage()
        if let resetError { errorMessage = resetError }
    }
    private func safeMessage(_ error: Error) -> String {
        (error as? QuotaError)?.localizedDescription ?? "操作未完成，请检查 Codex 登录状态与网络。"
    }
}
