import Foundation

// End-to-end harness for the Pi push. Drives the real PiSyncController (not a
// hand-copied shell script) against the actual Pi, and asserts the outcome.
//
//   ./pisync-test.sh
//
// Exits non-zero on failure. Needs the Pi reachable with key-based SSH auth —
// this is an integration test, not a headless unit test.

@main
struct PiSyncE2E {
    static var failures = 0
    static var checks = 0

    static func check(_ label: String, _ cond: Bool, _ detail: String = "") {
        checks += 1
        if cond { print("  ok   \(label)") }
        else {
            print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            failures += 1
        }
    }

    /// Endpoint for the integration test, from the environment so the harness
    /// never ships a machine-specific address. Run with e.g.
    ///   PI_TEST_HOST=pi.local PI_TEST_PORT=22 PI_TEST_USER=pi ./pisync-test.sh
    static func testHost() -> String {
        ProcessInfo.processInfo.environment["PI_TEST_HOST"] ?? "pi.local"
    }
    static func testPort() -> Int {
        Int(ProcessInfo.processInfo.environment["PI_TEST_PORT"] ?? "22") ?? 22
    }
    static func testUser() -> String {
        ProcessInfo.processInfo.environment["PI_TEST_USER"] ?? "pi"
    }
    /// The test writes into this remote directory — deliberately *not* the real
    /// backup folder, so running it can never touch or mislabel a genuine
    /// snapshot. Override with PI_TEST_REMOTE_DIR if you want it elsewhere.
    static func testRemoteDir() -> String {
        ProcessInfo.processInfo.environment["PI_TEST_REMOTE_DIR"] ?? "~/component-tracker-e2e"
    }

    @MainActor
    static func main() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ct-pi-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        // Start from the app's own seed data so this is hermetic.
        let store = InventoryStore(storeURL: tmp.appendingPathComponent("inventory.json"))
        store.replaceAll(with: InventoryStore.seedComponents())
        print("  seeded \(store.components.count) components")
        // A couple of log entries, so the test proves the payload carries the
        // usage log and not just the component list. Byte-identical is not
        // enough on its own — two payloads could match while both omit the log.
        store.takeOut(store.components[0], count: 3, project: "Line Follower")
        store.putBack(store.components[1], count: 2, project: "Sensor Board")
        print("  seeded \(store.consumed.count) log entries")

        let pi = PiSyncController()
        pi.config = PiConfig(host: testHost(), port: testPort(),
                             user: testUser(), remoteDir: testRemoteDir(),
                             enabled: true, keepSnapshots: 50)

        print("\n== test connection ==")
        pi.testConnection()
        await waitFor(pi)
        print("       \(text(pi.lastResult))")
        check("reaches the Pi", pi.lastResult?.isSuccess == true)

        print("\n== backup ==")
        let t0 = Date()
        pi.sync(components: store.components, consumed: store.consumed)
        await waitFor(pi)
        let elapsed = Date().timeIntervalSince(t0)

        let result = pi.lastResult
        print("       \(text(result))")
        check("push reported success", result?.isSuccess == true)
        check("no checksum corruption", result?.isCorrupt == false)
        check("completed inside the 90s deadline", elapsed < 90)
        check("last sync date recorded", pi.lastSyncDate != nil)
        let verified = pi.lastVerified
        check("last push bytes recorded", (verified?.bytes ?? 0) > 0)
        if let v = verified { print("       verified \(PiSyncController.byteText(v.bytes)) sha \(v.sha)…") }

        print("\n== what landed on the Pi ==")
        let newest = run("ls -1t ~/component-tracker/inventory-[0-9]*.json 2>/dev/null | head -1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if newest.isEmpty {
            check("a snapshot exists on the Pi", false)
        } else {
            print("       newest: \(newest)")
            let count = run("ls -1 ~/component-tracker/inventory-[0-9]*.json 2>/dev/null | wc -l")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("       total snapshots: \(count)")

            // The decisive check: is the Pi's copy byte-identical to what we sent?
            let localPayload = ExportService.json(from: store.components, consumed: store.consumed)
            let localSHA = PiSyncController.sha256Hex(Data(localPayload.utf8))
            let remoteSHA = run("sha256sum '\(newest)' | cut -d' ' -f1")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("       local  sha256: \(localSHA)")
            print("       remote sha256: \(remoteSHA)")
            check("remote copy is byte-identical to local", localSHA == remoteSHA)

            // Matching hashes only prove the transfer was clean. These prove the
            // backup is actually restorable — a payload missing the log would
            // still hash perfectly.
            let remoteKeys = run("grep -o '\"consumed\"' '\(newest)' | head -1")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            check("remote file has the consumed key", remoteKeys.contains("consumed"))
            let remoteEntries = run("grep -c '\"kind\"' '\(newest)'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            check("remote file carries the log entries",
                  remoteEntries == "\(store.consumed.count)",
                  "expected \(store.consumed.count), remote has \(remoteEntries)")
            let remoteProject = run("grep -c 'Line Follower' '\(newest)'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            check("remote file carries the project names", remoteProject != "0")

            let temps = run("ls -a ~/component-tracker/ | grep -cE '^\\.upload'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            check("no temp files left behind", temps == "0")

            let link = run("readlink -f ~/component-tracker/inventory-latest.json")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            check("inventory-latest.json points at the newest", link == newest)
        }

        print("\n== a second push in the same second must not collide ==")
        pi.sync(components: store.components, consumed: store.consumed)
        await waitFor(pi)
        pi.sync(components: store.components, consumed: store.consumed)
        await waitFor(pi)
        print("       \(text(pi.lastResult))")
        check("back-to-back pushes both succeed", pi.lastResult?.isSuccess == true)

        try? FileManager.default.removeItem(at: tmp)
        print("\n\(checks - failures)/\(checks) checks passed")
        if failures > 0 { print("\(failures) FAILURES"); exit(1) }
        print("all good")
    }

    // MARK: - helpers

    /// Polls until the controller reports it is idle.
    @MainActor
    static func waitFor(_ pi: PiSyncController) async {
        let deadline = Date().addingTimeInterval(120)
        while pi.isSyncing && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    nonisolated static func run(_ cmd: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c",
            "ssh -p \(testPort()) -o BatchMode=yes -o ConnectTimeout=8 -T "
            + "\(testUser())@\(testHost()) " + "\"\(cmd)\" 2>&1"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @MainActor
    static func text(_ r: PiSyncResult?) -> String {
        guard let r else { return "no result" }
        switch r {
        case .success(let m): return m
        case .failure(let m): return "FAILED: \(m)"
        case .corrupt(let m): return "CORRUPT: \(m)"
        }
    }
}
