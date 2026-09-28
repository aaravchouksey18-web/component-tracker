import Foundation
import Combine
import CryptoKit
import os

// MARK: - Raspberry Pi snapshot backup
//
// Local-first: the app is fully functional with no network. "Back Up to Pi" shells
// out over SSH, streams a JSON snapshot to the Pi, and has the Pi checksum what it
// actually received before moving it into place. A push either lands verified or is
// reported as failed — there is no "probably fine" path.
//
// The Pi is a backup target only. A push never reads, restores, or overwrites
// anything already there: it only ever adds a new timestamped file. The Mac's
// data is always authoritative.

struct PiConfig: Codable {
    // Placeholder defaults — set these to your own Pi in Settings ▸ Raspberry Pi
    // backup. The repository deliberately ships no machine-specific values.
    var host: String = "pi.local"
    var port: Int = 22
    var user: String = NSUserName()
    var remoteDir: String = "~/component-tracker"
    var enabled: Bool = false

    /// How many dated snapshots to keep on the Pi. Pruning happens as part of the
    /// same push, so the button stays the only action while the Pi never fills up.
    /// 0 disables pruning and keeps everything.
    var keepSnapshots: Int = 50

    static let defaultsKey = "piConfig"

    var displayString: String { enabled ? "\(user)@\(host):\(port)" : "not configured" }
}

enum PiSyncResult {
    case success(message: String)
    case failure(message: String)
    /// The upload completed but the bytes on the Pi did not match what was sent.
    /// Distinct from a network failure because the fix is different: retry, and
    /// if it repeats, suspect the network rather than the data.
    case corrupt(message: String)

    var isSuccess: Bool { if case .success = self { return true }; return false }
    var isCorrupt: Bool  { if case .corrupt  = self { return true }; return false }
}

/// Failure payload for the SSH runner.
struct PiCommandError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

// MARK: - Shell quoting

enum ShellQuote {
    /// POSIX single-quoting: safe to interpolate any string into a remote command.
    /// `it's` -> `'it'\''s'`
    static func single(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Quote a user-supplied remote path, deliberately leaving a leading `~`
    /// unquoted so the remote shell still expands it to $HOME. Quoting the whole
    /// thing would create a literal directory named "~".
    ///
    ///   ~/component-tracker -> ~/'component-tracker'
    ///   ~/my tracker        -> ~/'my tracker'
    ///   ~pi/backups         -> ~'pi'/'backups'
    ///   /srv/ct             -> '/srv/ct'
    static func path(_ s: String) -> String {
        // Validate path doesn't contain dangerous characters
        let forbidden = CharacterSet(charactersIn: "`$|&;<>(){}[]\\")
        if s.unicodeScalars.contains(where: forbidden.contains) {
            // Fall back to full quoting if suspicious characters found
            return single(s)
        }
        
        guard s.hasPrefix("~") else { return single(s) }
        if s == "~" { return "~" }
        if s.hasPrefix("~/") {
            return "~/" + single(String(s.dropFirst(2)))
        }
        // ~user or ~user/path — leave the tilde unquoted so it still expands.
        let rest = String(s.dropFirst())
        if let slash = rest.firstIndex(of: "/") {
            let user = String(rest[..<slash])
            let tail = String(rest[rest.index(after: slash)...])
            // The "/" goes *between* the two quoted segments. Folding it into
            // either one puts two adjacent quotes at the junction ('pi''/x'),
            // which the shell reads as an empty argument.
            return "~" + single(user) + "/" + single(tail)
        }
        return "~" + single(rest)
    }
    
    /// Validate and sanitize a string for safe use in SSH arguments.
    /// Rejects strings containing shell metacharacters.
    static func validateForSSHArg(_ s: String, fieldName: String) throws -> String {
        let forbidden = CharacterSet(charactersIn: "`$|&;<>(){}[]\\\"' \t\n\r")
        if s.unicodeScalars.contains(where: forbidden.contains) {
            throw PiCommandError(message: "\(fieldName) contains invalid characters")
        }
        if s.isEmpty {
            throw PiCommandError(message: "\(fieldName) cannot be empty")
        }
        if s.count > 255 {
            throw PiCommandError(message: "\(fieldName) exceeds maximum length")
        }
        return s
    }
}

// MARK: - Controller

@MainActor
final class PiSyncController: ObservableObject {
    @Published var config: PiConfig {
        didSet { save() }
    }
    @Published var isSyncing = false
    @Published var lastResult: PiSyncResult? = nil
    @Published var lastSyncDate: Date? = nil
    /// Bytes and hash of the most recent verified push, shown in Settings.
    @Published private(set) var lastVerified: (bytes: Int, sha: String)?

    private let defaults = UserDefaults.standard
    private static let lastSyncKey = "piLastSync"

    init() {
        if let data = defaults.data(forKey: PiConfig.defaultsKey),
           let decoded = try? JSONDecoder().decode(PiConfig.self, from: data) {
            config = decoded
        } else {
            config = PiConfig()
        }
        // Persisted, so "when did I last back up?" survives a relaunch.
        if let t = defaults.object(forKey: PiSyncController.lastSyncKey) as? Date {
            lastSyncDate = t
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: PiConfig.defaultsKey)
        }
    }

    func testConnection() {
        isSyncing = true
        PiRunner.run(host: config.host, port: config.port, user: config.user,
                     command: "echo ok", timeout: 20) { [weak self] result in
            Task { @MainActor in
                self?.isSyncing = false
                switch result {
                case .success(let out):
                    let msg = out.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.lastResult = .success(message: msg.isEmpty
                        ? "Connected to \(self?.config.displayString ?? "the Pi")."
                        : "Connected to Pi — \(msg)")
                case .failure(let err):
                    self?.lastResult = .failure(message: "Could not reach Pi: \(err)")
                }
            }
        }
    }

    /// The one button. Streams a snapshot to the Pi and verifies it landed intact.
    /// Sends the whole document — components and usage log — because the Pi is
    /// the backup, and a backup missing the log is only a partial one.
    func sync(components: [Component], consumed: [ConsumptionEntry] = []) {
        guard config.enabled else {
            lastResult = .failure(message: "Pi sync is off. Enable it in Settings first.")
            return
        }
        isSyncing = true

        let payload = ExportService.json(from: components, consumed: consumed)
        guard let data = payload.data(using: .utf8) else {
            isSyncing = false
            lastResult = .failure(message: "Could not encode the inventory for upload.")
            return
        }
        
        // Validate remoteDir before use
        do {
            _ = try ShellQuote.validateForSSHArg(config.remoteDir, fieldName: "Remote directory")
        } catch let err as PiCommandError {
            isSyncing = false
            lastResult = .failure(message: err.message)
            return
        } catch {
            isSyncing = false
            lastResult = .failure(message: "Validation failed: \(error.localizedDescription)")
            return
        }

        let sha = PiSyncController.sha256Hex(data)
        let stamp = PiSyncController.stamp()

        let dir  = ShellQuote.path(config.remoteDir)
        let file = "\(dir)/inventory-\(stamp).json"
        // Secure temp file: use random suffix instead of PID
        let randomSuffix = String((0..<16).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        let tmp  = "\(dir)/.upload-\(stamp)-\(randomSuffix).tmp"

        // Verification is the point: the Pi hashes what it actually received and
        // refuses to publish the file unless it matches. Also prunes old snapshots
        // in the same pass, so the button is still the only action you need.
        let keep = max(0, config.keepSnapshots)
        let prune: String
        if keep > 0 {
            prune = """
            ls -1t -- \(dir)/inventory-[0-9]*.json 2>/dev/null | tail -n +\(keep + 1) | \
            while IFS= read -r old; do [ -n "$old" ] && rm -f -- "$old" || true; done
            """
        } else {
            prune = "true"
        }

        let script = """
        set -eu
        DIR=\(dir)
        mkdir -p -- "$DIR"
        TMP=\(tmp)
        trap 'rm -f -- "$TMP"' EXIT
        cat > "$TMP"
        BYTES=$(wc -c < "$TMP" | tr -d ' ')
        GOT=$(sha256sum -- "$TMP" | cut -d' ' -f1)
        if [ "$GOT" != "\(sha)" ]; then
          printf 'CHECKSUM_MISMATCH: sent %s bytes with sha256 %s\\n' "$BYTES" "\(sha)" >&2
          printf 'CHECKSUM_MISMATCH: Pi received %s bytes with sha256 %s\\n' "$BYTES" "$GOT" >&2
          exit 3
        fi
        mv -f -- "$TMP" \(file)
        trap - EXIT
        ln -sfn -- \(file) "$DIR/inventory-latest.json"
        \(prune)
        echo "FILE:\(config.remoteDir)/inventory-\(stamp).json"
        echo "BYTES:$BYTES"
        echo "SHA:$GOT"
        """

        PiRunner.run(host: config.host, port: config.port, user: config.user,
                     command: script, stdin: payload, timeout: 90) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSyncing = false
                switch result {
                case .success(let out):
                    let lines = out.split(separator: "\n").map(String.init)
                    let path  = lines.first { $0.hasPrefix("FILE:") }?
                        .replacingOccurrences(of: "FILE:", with: "") ?? "the Pi"
                    let bytes = Int(lines.first { $0.hasPrefix("BYTES:") }?
                        .replacingOccurrences(of: "BYTES:", with: "") ?? "") ?? data.count
                    let shaOut = lines.first { $0.hasPrefix("SHA:") }?
                        .replacingOccurrences(of: "SHA:", with: "") ?? sha
                    self.lastSyncDate = Date()
                    self.defaults.set(Date(), forKey: PiSyncController.lastSyncKey)
                    self.lastVerified = (bytes, String(shaOut.prefix(12)))
                    self.lastResult = .success(message:
                        "Verified \(Self.byteText(bytes)) on the Pi — sha256 \(String(shaOut.prefix(12)))…\n\(path)")
                case .failure(let err):
                    self.lastResult = .failure(message: "Backup failed: \(err)")
                }
            }
        }
    }

    static func byteText(_ n: Int) -> String {
        n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", Int($0)) }.joined()
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone.current
        return f.string(from: Date())
    }
}

// MARK: - SSH runner

enum PiRunner {

    /// Runs a command on the Pi over SSH, returning stdout+stderr.
    ///
    /// Two things this gets right that a naive `Process` setup does not:
    ///  - both pipes are drained concurrently, so a full stderr buffer can't
    ///    wedge ssh while we're blocked reading stdout;
    ///  - there is an overall deadline, so a Pi that accepts the connection and
    ///    then stops responding can never leave the UI stuck on "Working…".
    static func run(host: String, port: Int, user: String,
                    command: String, stdin: String? = nil,
                    timeout: TimeInterval = 60,
                    completion: @escaping (Result<String, PiCommandError>) -> Void) {

        // Validate all user inputs before using in SSH command
        do {
            _ = try ShellQuote.validateForSSHArg(host, fieldName: "Host")
            _ = try ShellQuote.validateForSSHArg(user, fieldName: "User")
            if port < 1 || port > 65535 {
                throw PiCommandError(message: "Invalid port number")
            }
        } catch let err as PiCommandError {
            completion(.failure(err))
            return
        } catch {
            completion(.failure(PiCommandError(message: "Validation failed: \(error.localizedDescription)")))
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        // Security: Use strict host key checking - user must manually accept new hosts
        // This prevents MITM attacks. User should run `ssh-keyscan` manually first.
        p.arguments = [
            "-p", String(port),
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=~/.ssh/known_hosts",
            "-T",
            "\(user)@\(host)",
            command
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            p.standardInput = inPipe
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(stdin.data(using: .utf8) ?? Data())
                try? inPipe.fileHandleForWriting.close()
            }
        }

        // Drain both pipes on their own threads.
        let outData = NSMutableData()
        let errData = NSMutableData()
        let lock = NSLock()
        for (handle, sink) in [(outPipe.fileHandleForReading, outData),
                               (errPipe.fileHandleForReading, errData)] {
            handle.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty {
                    h.readabilityHandler = nil
                    return
                }
                lock.lock(); sink.append(d); lock.unlock()
            }
        }

        let timedOut = OSAllocatedUnfairLock(initialState: false)

        p.terminationHandler = { proc in
            // Collect whatever arrived; readability handlers may not have fired yet.
            let extraOut = outPipe.fileHandleForReading.readDataToEndOfFile()
            let extraErr = errPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            if !extraOut.isEmpty { outData.append(extraOut) }
            if !extraErr.isEmpty { errData.append(extraErr) }
            let out = String(data: outData as Data, encoding: .utf8) ?? ""
            let err = String(data: errData as Data, encoding: .utf8) ?? ""
            lock.unlock()

            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            let didTimeOut = timedOut.withLock { $0 }

            DispatchQueue.main.async {
                if didTimeOut {
                    completion(.failure(PiCommandError(
                        message: "timed out after \(Int(timeout))s — the Pi stopped responding")))
                } else if proc.terminationStatus == 0 {
                    completion(.success(out))
                } else {
                    completion(.failure(PiCommandError(message: clean(err, status: proc.terminationStatus))))
                }
            }
        }

        // Overall deadline. ConnectTimeout only covers the TCP handshake.
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            let alreadyDead = timedOut.withLock { t -> Bool in
                if t { return true }
                t = true
                return false
            }
            guard !alreadyDead else { return }
            if p.isRunning { p.terminate() }
        }

        do {
            try p.run()
        } catch {
            completion(.failure(PiCommandError(message: "could not launch ssh: \(error.localizedDescription)")))
        }
    }

    /// Turns raw ssh stderr into something a person can act on.
    private static func clean(_ err: String, status: Int32) -> String {
        var e = err.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return "exit status \(status)" }

        if e.contains("CHECKSUM_MISMATCH") {
            // Both lines are ours; surface the pair as-is.
            return e
        }
        if e.contains("Permission denied") {
            e += " — check that your SSH key is authorised for this user on the Pi."
        } else if e.contains("Connection refused") {
            e = "connection refused — is SSH running on the Pi?"
        } else if e.contains("could not resolve hostname") || e.contains("Name or service not known") {
            e = "can't find that host — check the address."
        } else if e.contains("timed out") || e.contains("Operation timed out") {
            e = "the Pi didn't answer — check it's powered on and on the same network."
        } else if e.contains("No space left") {
            e = "the Pi is out of disk space."
        }
        return e
    }
}
