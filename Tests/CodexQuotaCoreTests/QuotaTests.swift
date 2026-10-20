import Foundation
import Testing
@testable import CodexQuotaCore

private func usage(_ json: String) throws -> UsageSnapshot {
    try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
}
private func fixture(account: String = "test-account", count: Int = 3) throws -> UsageSnapshot {
    try usage("""
    {"accountId":"\(account)","ordinaryUsageAllowed":true,
     "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1789995568}}},
     "rateLimitResetCredits":{"availableCount":\(count),"credits":[]}}
    """)
}
private func temporaryStore() -> ResetStore {
    ResetStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("codex-quota-test-\(UUID().uuidString)/history.json"))
}
private func cleanup(_ store: ResetStore) { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }

private actor MockService: QuotaService {
    var snapshot: UsageSnapshot
    var readFails = false
    var failAfterConsume = false
    var consumeFails = false
    var outcome: ResetOutcome = .reset
    var keys: [String] = []
    init(_ snapshot: UsageSnapshot) { self.snapshot = snapshot }
    func readUsage() async throws -> UsageSnapshot {
        if readFails { throw QuotaError.timeout }
        return snapshot
    }
    func consumeReset(key: String, accountID: String, retry: Bool) async throws -> ResetOutcome {
        keys.append(key)
        if failAfterConsume { readFails = true }
        if consumeFails { throw QuotaError.timeout }
        return outcome
    }
    func configure(failure: Bool = false, afterConsume: Bool = false, outcome: ResetOutcome = .reset) {
        consumeFails = failure
        failAfterConsume = afterConsume
        self.outcome = outcome
    }
    func setSnapshot(_ value: UsageSnapshot) { snapshot = value }
    func keyList() -> [String] { keys }
}

@Test func weeklyPrimaryAndAuthoritativeCount() throws {
    let value = try fixture()
    #expect(value.core?.primary?.label == "每周")
    #expect(value.menuBarTitle == "Codex 96%")
    #expect(value.resetCount == 3) // Empty detail list does not mean zero credits.
}

@Test func missingIsUnknownAndZeroIsExplicit() throws {
    let unknown = try usage("{\"rateLimitResetCredits\":null}")
    #expect(unknown.resetCount == nil)
    #expect(unknown.menuBarTitle == "Codex —")
    #expect(unknown.resetSummary == "暂时无法获取 reset 数量")
    #expect(try fixture(count: 0).resetSummary == "当前没有可用 reset")
}

@Test func mapWinsAndReserveCannotBecomeCore() throws {
    let value = try usage("""
    {"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{
      "codex":{"primary":{"usedPercent":80},"secondary":{"usedPercent":91}},
      "base_model_inference":{"primary":{"usedPercent":0}}}}
    """)
    #expect(value.core?.remaining == 9)
    #expect(value.menuBarTitle == "Codex 9%")
    let reserveOnly = try usage("""
    {"rateLimits":{"limitId":"base_model_inference","primary":{"usedPercent":0}}}
    """)
    #expect(reserveOnly.core == nil)
}

@Test func clampAndUnknownWindow() throws {
    #expect(try usage("{\"rateLimits\":{\"primary\":{\"usedPercent\":120}}}").core?.remaining == 0)
    #expect(try usage("{\"rateLimits\":{\"primary\":{\"usedPercent\":-10}}}").core?.remaining == 100)
    #expect(try usage("{\"rateLimits\":{\"primary\":{\"usedPercent\":null}}}").core?.remaining == nil)
}

@Test @MainActor func noMutationBeforeConfirmationAndCancel() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture())
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    #expect(model.confirmation != nil)
    #expect(await service.keyList().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
    let cancelledID = try #require(model.confirmation?.id)
    model.cancelReset()
    await model.confirmReset(cancelledID)
    #expect(await service.keyList().isEmpty)
    #expect(model.confirmation == nil)
    #expect(model.snapshot?.resetCount == 3)
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
    await model.prepareReset()
    #expect(model.confirmation?.id != cancelledID)
    model.cancelReset()
    #expect(await service.keyList().isEmpty)
}

@Test(arguments: [ResetOutcome.reset, .uncertain]) @MainActor
func cancelLeavesExistingJournalByteIdentical(outcome: ResetOutcome) async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture())
    var record = ResetRecord(accountID: "test-account")
    record.outcome = outcome
    try store.save([record.accountID: record])
    let before = try Data(contentsOf: store.url)
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    let id = try #require(model.confirmation?.id)
    model.cancelReset()
    await model.confirmReset(id)
    await model.refresh()
    #expect(await service.keyList().isEmpty)
    #expect(model.snapshot?.resetCount == 3)
    #expect(model.latest?.key == record.key)
    #expect(try Data(contentsOf: store.url) == before)
}

@Test @MainActor func successPersistsAndRefreshFailureDoesNotUndoSuccess() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture())
    await service.configure(afterConsume: true)
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    let id = try #require(model.confirmation?.id)
    await model.confirmReset(id)
    #expect(model.latest?.outcome == .reset)
    #expect(model.latest?.finishedAt != nil)
    #expect(model.errorMessage != nil)
    #expect(try store.load()["test-account"]?.outcome == .reset)
    await model.confirmReset(id) // Double click cannot redeem again.
    #expect(await service.keyList().count == 1)
}

@Test @MainActor func timeoutThenRestartReusesKeyEvenWithZeroCredits() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture())
    await service.configure(failure: true)
    let original = QuotaController(service: service, store: store)
    await original.prepareReset()
    let id = try #require(original.confirmation?.id)
    await original.confirmReset(id)
    #expect(original.latest?.outcome == .uncertain)

    await service.configure(outcome: .alreadyRedeemed)
    await service.setSnapshot(try fixture(count: 0))
    let restarted = QuotaController(service: service, store: store)
    await restarted.prepareReset()
    #expect(restarted.confirmation?.isRetry == true)
    #expect(restarted.confirmation?.id == id)
    await restarted.confirmReset(id)
    #expect(restarted.latest?.outcome == .alreadyRedeemed)
    #expect(await service.keyList() == [id, id])
}

@Test @MainActor func noCreditsNeverOffersNewReset() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture(count: 0))
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    #expect(model.confirmation == nil)
    #expect(model.errorMessage == "当前没有可用 reset")
    #expect(await service.keyList().isEmpty)
}

@Test @MainActor func recordsAreSeparatedByAccount() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    try store.save(["other-account": ResetRecord(accountID: "other-account", outcome: .uncertain)])
    let service = MockService(try fixture())
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    #expect(model.latest == nil)
    #expect(model.confirmation?.isRetry == false)
}

@Test @MainActor func corruptJournalDisablesConsumption() async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("broken".utf8).write(to: store.url)
    let service = MockService(try fixture())
    let model = QuotaController(service: service, store: store)
    await model.refresh()
    await model.prepareReset()
    #expect(model.historyError != nil)
    #expect(!model.canReset)
    #expect(await service.keyList().isEmpty)
}

@Test @MainActor func cannotSaveMeansCannotSend() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-quota-unwritable-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("file, not a directory".utf8).write(to: directory)
    let store = ResetStore(url: directory.appendingPathComponent("history.json"))
    let service = MockService(try fixture())
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    let id = try #require(model.confirmation?.id)
    await model.confirmReset(id)
    #expect(model.historyError != nil)
    #expect(await service.keyList().isEmpty)
}

@Test(arguments: [ResetOutcome.nothingToReset, .noCredit]) @MainActor
func definitiveNonRedemptionIsRecorded(outcome: ResetOutcome) async throws {
    let store = temporaryStore(); defer { cleanup(store) }
    let service = MockService(try fixture())
    await service.configure(outcome: outcome)
    let model = QuotaController(service: service, store: store)
    await model.prepareReset()
    let id = try #require(model.confirmation?.id)
    await model.confirmReset(id)
    #expect(model.latest?.outcome == outcome)
    #expect(model.latest?.outcome.isUncertain == false)
}

// End-to-end protocol tests run against a local fake process, never the real account.
private func fakeCLI(body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-quota-fake-\(UUID().uuidString)")
    let script = """
    #!/usr/bin/python3
    import sys,json,time
    for line in sys.stdin:
        m=json.loads(line)
        if 'id' not in m: continue
        if m['method']=='initialize':
            print(json.dumps({'id':m['id'],'result':{}}),flush=True)
            continue
    \(body.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n"))
    """
    try Data(script.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    return url
}

@Test func legacyParameterlessUsageRequest() async throws {
    let url = try fakeCLI(body: """
    if m['method']=='account/rateLimits/read' and 'params' not in m:
        print(json.dumps({'id':m['id'],'result':{'rateLimits':{'primary':{'usedPercent':20}}}}),flush=True)
    else:
        print(json.dumps({'id':m['id'],'error':{'code':-32600,'message':'invalid type: map, expected unit'}}),flush=True)
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    #expect(try await service.readUsage().menuBarTitle == "Codex 80%")
}

@Test func apiKeyAuthenticationGetsActionableError() async throws {
    let url = try fakeCLI(body: """
    if m['method']=='account/read':
        print(json.dumps({'id':m['id'],'result':{'account':{'type':'apiKey'}}}),flush=True)
    else:
        print(json.dumps({'id':m['id'],'error':{'code':-32600,'message':'usage unavailable'}}),flush=True)
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    await #expect(throws: QuotaError.subscriptionLoginRequired) { try await service.readUsage() }
}

@Test func signedOutAuthenticationGetsActionableError() async throws {
    let url = try fakeCLI(body: """
    if m['method']=='account/read':
        print(json.dumps({'id':m['id'],'result':{'account':None}}),flush=True)
    else:
        print(json.dumps({'id':m['id'],'error':{'code':-32600,'message':'usage unavailable'}}),flush=True)
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    await #expect(throws: QuotaError.loginRequired) { try await service.readUsage() }
}

@Test func unknownServerMessageIsNotExposed() async throws {
    let url = try fakeCLI(body: """
    print(json.dumps({'id':m['id'],'error':{'code':-32000,'message':'private-test-string'}}),flush=True)
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    await #expect(throws: QuotaError.rpcFailure(-32000, "account/rateLimits/read", "unknown")) { try await service.readUsage() }
}

@Test func protocolHandlesNotificationsAndFragmentedLines() async throws {
    let url = try fakeCLI(body: """
    print(json.dumps({'method':'account/rateLimits/updated','params':{}}),flush=True)
    output=json.dumps({'id':m['id'],'result':{'accountId':'test','rateLimits':{'primary':{'usedPercent':25}}}})+'\\n'
    sys.stdout.write(output[:12]);sys.stdout.flush();time.sleep(0.03)
    sys.stdout.write(output[12:]);sys.stdout.flush()
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    let snapshot = try await service.readUsage()
    #expect(snapshot.menuBarTitle == "Codex 75%")
}

@Test func protocolHasBoundedTimeout() async throws {
    let url = try fakeCLI(body: "time.sleep(5)")
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 0.3)
    await #expect(throws: QuotaError.timeout) { try await service.readUsage() }
}

@Test @MainActor func cancellationSendsNoConsumeRPC() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-rpc-\(UUID().uuidString)")
    let path = String(data: try JSONEncoder().encode(marker.path), encoding: .utf8)!
    let url = try fakeCLI(body: """
    if m['method']=='account/rateLimits/read':
        print(json.dumps({'id':m['id'],'result':{'accountId':'test-account','rateLimitResetCredits':{'availableCount':3}}}),flush=True)
    elif m['method']=='account/rateLimitResetCredit/consume':
        open(\(path),'w').write('consume was sent')
        print(json.dumps({'id':m['id'],'result':{'outcome':'reset'}}),flush=True)
    """)
    let store = temporaryStore()
    defer {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: marker)
        cleanup(store)
    }
    let model = QuotaController(service: try CodexService(executable: url, timeout: 2), store: store)
    await model.refresh()
    await model.prepareReset()
    let id = try #require(model.confirmation?.id)
    model.cancelReset()
    await model.confirmReset(id)
    await model.refresh()
    #expect(model.snapshot?.resetCount == 3)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
}

@Test func protocolRejectsAccountSwitchBeforeConsume() async throws {
    let url = try fakeCLI(body: """
    print(json.dumps({'id':m['id'],'result':{'accountId':'different-account','rateLimitResetCredits':{'availableCount':3}}}),flush=True)
    """)
    defer { try? FileManager.default.removeItem(at: url) }
    let service = try CodexService(executable: url, timeout: 2)
    await #expect(throws: QuotaError.accountChanged) {
        try await service.consumeReset(key: "test-only", accountID: "test-account", retry: false)
    }
}
