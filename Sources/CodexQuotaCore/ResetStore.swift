import Foundation

public struct ResetRecord: Codable, Sendable, Equatable {
    public let accountID: String
    public let key: String
    public let attemptedAt: Date
    public var finishedAt: Date?
    public var outcome: ResetOutcome

    public init(accountID: String, key: String = UUID().uuidString, attemptedAt: Date = Date(), outcome: ResetOutcome = .pending) {
        self.accountID = accountID
        self.key = key
        self.attemptedAt = attemptedAt
        self.outcome = outcome
    }
}

public struct ResetStore: Sendable {
    public let url: URL
    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexQuota/reset-history.json")
    }
    public func load() throws -> [String: ResetRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do { return try JSONDecoder().decode([String: ResetRecord].self, from: Data(contentsOf: url)) }
        catch { throw QuotaError.persistence }
    }
    public func save(_ records: [String: ResetRecord]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw QuotaError.persistence }
    }
}
