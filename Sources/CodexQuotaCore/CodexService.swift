import Foundation
import Darwin

/// Only account RPCs are sent. Auth stays inside the installed Codex CLI.
public struct CodexService: QuotaService {
    public let executable: URL
    public let timeout: TimeInterval

    public init(executable: URL? = nil, timeout: TimeInterval = 25) throws {
        guard let executable = executable ?? Self.findExecutable() else { throw QuotaError.cliMissing }
        self.executable = executable
        self.timeout = timeout
    }

    public static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["CODEX_CLI_PATH"],
            "\(home)/.local/bin/codex", "\(home)/.codex/packages/standalone/current/bin/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"]
            .compactMap { $0 } + (env["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    public func readUsage() async throws -> UsageSnapshot {
        try await perform { connection in
            try connection.readUsage()
        }
    }

    public func consumeReset(key: String, accountID: String, retry: Bool) async throws -> ResetOutcome {
        try await perform { connection in
            let fresh = try connection.readUsage()
            guard fresh.accountId == accountID else { throw QuotaError.accountChanged }
            // An uncertain attempt must retain its key even when its credit has already been consumed.
            if !retry {
                guard let count = fresh.resetCount else { throw QuotaError.countUnknown }
                guard count > 0 else { throw QuotaError.noCredit }
            }
            struct Response: Decodable { let outcome: ResetOutcome }
            let result: Response = try connection.call("account/rateLimitResetCredit/consume", params: ["idempotencyKey": key])
            guard !result.outcome.isUncertain else { throw QuotaError.invalidResponse }
            return result.outcome
        }
    }

    private func perform<T: Sendable>(_ work: @escaping @Sendable (RPCConnection) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let connection = try RPCConnection(executable: executable, timeout: timeout)
                    defer { connection.close() }
                    try connection.initialize()
                    continuation.resume(returning: try work(connection))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// A short-lived stdio session for each operation. Closing it never stops the desktop daemon.
private final class RPCConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let timeout: TimeInterval
    private var buffer = Data()
    private var nextID = 0
    private var closed = false

    init(executable: URL, timeout: TimeInterval) throws {
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["app-server"] // stdio is the default, including on older CLIs.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // Never write Codex's stderr (which could contain private information) into UI or a log.
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        do { try process.run() } catch { throw QuotaError.connection }
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        _ = Darwin.fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func initialize() throws {
        struct Initialized: Decodable {}
        let _: Initialized = try call("initialize", params: [
            "clientInfo": ["name": "codex_quota_menubar", "title": "Codex Quota", "version": "1.2.8"],
            "capabilities": ["experimentalApi": true]
        ])
        try send(["method": "initialized"])
    }

    func readUsage() throws -> UsageSnapshot {
        do {
            // Older servers define this as a parameterless request. Even an empty object
            // or a newer optional field can be rejected with -32600 before authentication.
            return try call("account/rateLimits/read")
        } catch {
            let original = error
            if case QuotaError.rpcFailure(-32600, _, _) = error {
                struct AccountInfo: Decodable {
                    struct Account: Decodable { let type: String }
                    let account: Account?
                }
                // Decode only authentication type. Never expose email, credentials or raw messages.
                if let info: AccountInfo = try? call("account/read", params: ["refreshToken": false]) {
                    if info.account == nil { throw QuotaError.loginRequired }
                    if info.account?.type == "apiKey" || info.account?.type == "amazonBedrock" {
                        throw QuotaError.subscriptionLoginRequired
                    }
                }
            }
            throw original
        }
    }

    func call<T: Decodable>(_ method: String, params: [String: Any]? = nil) throws -> T {
        nextID += 1
        let id = nextID
        var request: [String: Any] = ["id": id, "method": method]
        if let params { request["params"] = params }
        try send(request)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            let line = try readLine(deadline: deadline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            // Decline server requests: this integration never approves commands or shares tokens.
            if object["method"] != nil, let serverID = object["id"] {
                try send(["id": serverID, "error": ["code": -32601, "message": "Unsupported client request"]])
                continue
            }
            guard object["id"] as? Int == id else { continue }
            if let error = object["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? -1
                let message = (error["message"] as? String ?? "").lowercased()
                let reason: String
                if message.contains("not logged in") || message.contains("not authenticated") {
                    reason = "notLoggedIn"
                } else if message.contains("invalid params") || message.contains("unknown field") || message.contains("invalid type") {
                    reason = "parameters"
                } else if message.contains("chatgpt") && (message.contains("required") || message.contains("only available")) {
                    reason = "chatgptRequired"
                } else { reason = "unknown" }
                throw QuotaError.rpcFailure(code, method, reason)
            }
            guard let result = object["result"], JSONSerialization.isValidJSONObject(result) else { throw QuotaError.invalidResponse }
            do { return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: result)) }
            catch { throw QuotaError.invalidResponse }
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard process.isRunning else { throw QuotaError.connection }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw QuotaError.connection }
    }

    private func readLine(deadline: TimeInterval) throws -> Data {
        while true {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw QuotaError.timeout }
            if let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                return line
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let millis = Int32(min(250, max(1, (deadline - ProcessInfo.processInfo.systemUptime) * 1_000)))
            let result = Darwin.poll(&descriptor, 1, millis)
            if result < 0 {
                if errno == EINTR { continue }
                throw QuotaError.connection
            }
            if result == 0 { continue }
            var chunk = [UInt8](repeating: 0, count: 8_192)
            let count = Darwin.read(descriptor.fd, &chunk, chunk.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw QuotaError.connection }
            buffer.append(contentsOf: chunk.prefix(count))
            guard buffer.count <= 4_194_304 else { throw QuotaError.invalidResponse }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
    }
    deinit { close() }
}
