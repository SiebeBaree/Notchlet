import Foundation
@testable import Notchlet
import Testing

struct SecretScannerTests {
    private struct Files: SecretScanSource {
        let urls: [URL]
        func input(since: Date?) async throws -> SecretScanInput {
            .files(urls)
        }
    }

    private struct Provider: UsageProvider {
        let id = "test-scanner"
        let name = "Test"
        let logoAssetName = "ClaudeLogo"
        let isInstalled = true
        let authOptions: [AuthOption] = []
        let signInHint = ""
        let secrets: (any SecretScanSource)?
        func fetchUsage() async throws -> UsageSnapshot {
            throw ProviderError.notAvailable(.signedOut)
        }
    }

    private actor Detector {
        var calls = 0
        var records = 0
        let failAt: Int?
        var block = false
        var cancellations = 0
        private var started: CheckedContinuation<Void, Never>?

        init(failAt: Int? = nil) {
            self.failAt = failAt
        }

        func waitUntilStarted() async {
            if calls > 0 {
                return
            }
            await withCheckedContinuation { started = $0 }
        }

        func setBlocking() {
            block = true
        }

        func scan(_ input: SecretScanInput) async throws -> [SecretMatch] {
            calls += 1
            started?.resume()
            started = nil
            if block {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { cancellations += 1; throw error }
            }
            if calls == failAt {
                throw CocoaError(.fileReadUnknown)
            }
            if case let .text(data) = input {
                records += data.filter { $0 == 10 }.count
            }
            return [SecretMatch(
                ruleID: "test",
                description: "Test key",
                secret: "sk_demo_4eC39HqLyjWDarjtT1zdp7dc",
                line: 1
            )]
        }
    }

    @Test func disablingScanningCancelsTheHelperWithoutAcknowledgingTheBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-scan-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "a.jsonl")
        try Data("record\n".utf8).write(to: file)
        let suite = "notchlet-scan-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = Provider(secrets: Files(urls: [file]))
        let store = UsageStore(providers: [provider], defaults: defaults)
        defer { store.suspend() }
        let detector = Detector()
        await detector.setBlocking()
        let scanner = SecretScanner(store: store, stateStore: .init(url: directory.appending(path: "state.json")),
                                    defaults: defaults, available: true, scan: { try await detector.scan($0) },
                                    conditions: { .init(idleSeconds: 600, thermalState: .nominal) })
        let task = Task { await scanner.scanIfDue(now: .distantFuture) }
        await detector.waitUntilStarted()
        scanner.setEnabled(false)
        await task.value
        #expect(await detector.cancellations == 1)
        #expect(scanner.state.checkpoints.isEmpty)
        #expect(scanner.state.lastScanAt.isEmpty)
        #expect(!scanner.isScanning)
    }

    @Test func failedLaterBatchKeepsDurableProgressAndRelaunchResumes() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "notchlet-scan-resume-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = (0 ..< 260).map { directory.appending(path: "\($0).jsonl") }
        for file in files {
            try Data("record\n".utf8).write(to: file)
        }
        let suite = "notchlet-scan-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let provider = Provider(secrets: Files(urls: files))
        let store = UsageStore(providers: [provider], defaults: defaults)
        let disk = SecretStateStore(url: directory.appending(path: "state.json"))
        let failing = Detector(failAt: 2)
        let first = SecretScanner(store: store, stateStore: disk, defaults: defaults, available: true,
                                  scan: { try await failing.scan($0) },
                                  conditions: { .init(idleSeconds: 600, thermalState: .nominal) })
        await first.scanIfDue(now: .distantFuture)
        #expect(first.failedProviderIDs == [provider.id])
        #expect(first.state.lastScanAt[provider.id] == nil)
        #expect(disk.load()?.checkpoints[provider.id]?.count == 256)
        #expect(first.pending.count == 1)
        let saved = try String(contentsOf: disk.url, encoding: .utf8)
        #expect(!saved.contains("sk_demo_4eC39HqLyjWDarjtT1zdp7dc"))
        first.ignore(first.pending[0].id)

        let detector = Detector()
        let resumed = SecretScanner(store: store, stateStore: disk, defaults: defaults, available: true,
                                    scan: { try await detector.scan($0) },
                                    conditions: { .init(idleSeconds: 600, thermalState: .nominal) })
        await resumed.scanIfDue(now: .distantFuture)
        #expect(await detector.records == 4)
        #expect(resumed.failedProviderIDs.isEmpty)
        #expect(resumed.state.lastScanAt[provider.id] != nil)
        #expect(disk.load()?.checkpoints[provider.id]?.count == 260)
        #expect(resumed.pending.isEmpty)
        #expect(resumed.state.findings.first?.status == .ignored)
    }
}
