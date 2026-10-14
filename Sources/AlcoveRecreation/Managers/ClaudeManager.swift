import AppKit
import Observation

/// Follows Claude Code sessions (terminal CLI and the Claude desktop app's Code tab) so the
/// notch can show whether Claude is working, finished, or waiting on the user.
///
/// Everything is read from files Claude Code already writes, so the feature needs no setup:
/// - `~/.claude/projects/<project>/<session>.jsonl` — session transcripts, for status and tokens
/// - `~/.claude.json` — the cached plan usage (5-hour and 7-day limits)
///
/// One thing transcripts cannot show is a pending permission prompt, because nothing is written
/// until it is answered. `ClaudeHooks` can optionally register a Notification hook for that.
@Observable
final class ClaudeManager {
    static let shared = ClaudeManager()

    enum Status: String { case idle, working, needsResponse, finished }

    struct Session: Equatable {
        var id: String
        var projectName: String
        var status: Status
        /// Tool Claude is waiting on, or the text of a permission notification.
        var detail: String?
        var contextTokens: Int
        var contextWindow: Int
        var isDesktop: Bool
        var lastActivity: Date

        var contextFraction: Double {
            contextWindow > 0 ? min(Double(contextTokens) / Double(contextWindow), 1) : 0
        }
    }

    struct PlanUsage: Equatable {
        var fiveHourPercent: Int?
        var sevenDayPercent: Int?
        var fiveHourResetsAt: Date?
        var fetchedAt: Date?
    }

    /// The session the notch should show right now, if any.
    private(set) var current: Session?
    private(set) var planUsage = PlanUsage()

    /// Called on the main queue with the previous status whenever `current` changes meaningfully.
    @ObservationIgnored var onChange: ((_ previous: Status) -> Void)?

    @ObservationIgnored private let queue = DispatchQueue(label: "claude.sessions", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var tick = 0
    @ObservationIgnored private var candidates: [URL] = []
    @ObservationIgnored private var parsed: [URL: (size: UInt64, modified: Date, snapshot: Snapshot)] = [:]
    @ObservationIgnored private var hookOverrides: [String: (date: Date, message: String)] = [:]
    @ObservationIgnored private var defaultContextWindow = 200_000

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let projectsDirectory = home.appendingPathComponent(".claude/projects")
    private static let stateFile = home.appendingPathComponent(".claude.json")
    /// Tools that exist to put a question in front of the user.
    private static let askingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    /// A session that has written nothing for this long is treated as abandoned, not working.
    private static let staleInterval: TimeInterval = 15 * 60
    private static let tailBytes: UInt64 = 256 * 1024

    private struct Snapshot {
        var status: Status = .idle
        var detail: String?
        var contextTokens = 0
        var projectName = ""
        var isDesktop = false
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        guard Prefs.bool(Key.enableClaudeStatus) else {
            if current != nil { publish(nil, usage: planUsage) }
            return
        }
        tick += 1
        let rescan = tick % 5 == 1
        let readUsage = tick % 20 == 1
        let finishedDuration = max(Prefs.double(Key.claudeFinishedDuration), 1)
        queue.async { [weak self] in
            guard let self else { return }
            if rescan { self.candidates = Self.recentTranscripts() }
            self.drainHookEvents()
            let usage = readUsage ? Self.readPlanUsage() : nil
            if readUsage { self.defaultContextWindow = Self.readDefaultContextWindow() }
            let session = self.resolveCurrentSession(finishedDuration: finishedDuration)
            DispatchQueue.main.async { self.publish(session, usage: usage ?? self.planUsage) }
        }
    }

    private func publish(_ session: Session?, usage: PlanUsage) {
        if usage != planUsage { planUsage = usage }
        guard session != current else { return }
        let previous = current
        current = session
        // Token counts tick up constantly; only status or session switches are worth announcing.
        if previous?.status != session?.status || previous?.id != session?.id {
            onChange?(previous?.status ?? .idle)
        }
    }

    // MARK: Sessions

    /// Transcripts touched recently enough to matter, newest first.
    private static func recentTranscripts() -> [URL] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil) else { return [] }
        let cutoff = Date().addingTimeInterval(-staleInterval)
        var result: [(URL, Date)] = []
        for project in projects {
            guard let files = try? manager.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      modified > cutoff else { continue }
                result.append((file, modified))
            }
        }
        return result.sorted { $0.1 > $1.1 }.prefix(8).map(\.0)
    }

    private func resolveCurrentSession(finishedDuration: TimeInterval) -> Session? {
        let now = Date()
        var sessions: [Session] = []
        for url in candidates {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? UInt64, let modified = attributes[.modificationDate] as? Date else { continue }
            let snapshot: Snapshot
            if let cached = parsed[url], cached.size == size, cached.modified == modified {
                snapshot = cached.snapshot
            } else {
                snapshot = Self.parseTail(of: url, size: size)
                parsed[url] = (size, modified, snapshot)
            }
            let id = url.deletingPathExtension().lastPathComponent
            var status = snapshot.status
            var detail = snapshot.detail
            let age = now.timeIntervalSince(modified)

            // A permission prompt reported by the hook holds until the transcript moves on.
            if let hook = hookOverrides[id] {
                if modified > hook.date.addingTimeInterval(1) || now.timeIntervalSince(hook.date) > Self.staleInterval {
                    hookOverrides[id] = nil
                } else if status == .working {
                    status = .needsResponse
                    detail = hook.message
                }
            }
            switch status {
            case .working, .needsResponse:
                if age > Self.staleInterval { status = .idle }
            case .finished:
                if age > finishedDuration { status = .idle }
            case .idle:
                break
            }
            guard status != .idle else { continue }
            let window = snapshot.contextTokens > 200_000 ? 1_000_000 : defaultContextWindow
            sessions.append(Session(
                id: id, projectName: snapshot.projectName, status: status, detail: detail,
                contextTokens: snapshot.contextTokens, contextWindow: window,
                isDesktop: snapshot.isDesktop, lastActivity: modified))
        }
        // Something waiting on the user outranks work in progress, which outranks a finished turn.
        let rank: [Status: Int] = [.needsResponse: 0, .working: 1, .finished: 2]
        return sessions.min {
            let (a, b) = (rank[$0.status] ?? 3, rank[$1.status] ?? 3)
            return a != b ? a < b : $0.lastActivity > $1.lastActivity
        }
    }

    /// Reads the end of a transcript and works out where the conversation stands.
    private static func parseTail(of url: URL, size: UInt64) -> Snapshot {
        var snapshot = Snapshot()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return snapshot }
        defer { try? handle.close() }
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd() else { return snapshot }

        var statusFound = false
        var usageFound = false
        for line in data.split(separator: UInt8(ascii: "\n")).reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = entry["type"] as? String, type == "assistant" || type == "user",
                  entry["isSidechain"] as? Bool != true,
                  let message = entry["message"] as? [String: Any] else { continue }

            if snapshot.projectName.isEmpty, let cwd = entry["cwd"] as? String {
                snapshot.projectName = URL(fileURLWithPath: cwd).lastPathComponent
                snapshot.isDesktop = (entry["entrypoint"] as? String)?.contains("desktop") ?? false
            }
            if !usageFound, type == "assistant", let usage = message["usage"] as? [String: Any] {
                let keys = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                snapshot.contextTokens = keys.reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
                usageFound = true
            }
            if !statusFound, let resolved = status(of: entry, type: type, message: message) {
                snapshot.status = resolved.status
                snapshot.detail = resolved.detail
                statusFound = true
            }
            if statusFound && usageFound { break }
        }
        return snapshot
    }

    /// The status implied by one transcript entry, or nil when the entry says nothing about it.
    private static func status(of entry: [String: Any], type: String, message: [String: Any]) -> (status: Status, detail: String?)? {
        let blocks = message["content"] as? [[String: Any]] ?? []
        if type == "assistant" {
            let tools = blocks.filter { $0["type"] as? String == "tool_use" }.compactMap { $0["name"] as? String }
            if let asking = tools.first(where: askingTools.contains) { return (.needsResponse, asking) }
            if let tool = tools.last { return (.working, tool) }
            switch message["stop_reason"] as? String {
            case "end_turn", "stop_sequence", "max_tokens", "refusal": return (.finished, nil)
            default: return (.working, nil)   // still streaming, or text ahead of a tool call
            }
        }
        // User entries: real prompts and tool results mean Claude is (about to be) working.
        if entry["isMeta"] as? Bool == true { return nil }
        let text = (message["content"] as? String)
            ?? blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        if text.contains("[Request interrupted by user") { return (.idle, nil) }
        if text.hasPrefix("<local-command-") || text.hasPrefix("<command-name>") { return nil }
        return (.working, nil)
    }

    /// One-line description of a transcript's state, for `--claude-status <file>` on the command line.
    static func describeTranscript(at url: URL) -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let snapshot = parseTail(of: url, size: size)
        return "\(snapshot.status.rawValue) detail=\(snapshot.detail ?? "-") context=\(snapshot.contextTokens) project=\(snapshot.projectName)"
    }

    // MARK: Plan usage

    private static func readPlanUsage() -> PlanUsage {
        guard let data = try? Data(contentsOf: stateFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cache["utilization"] as? [String: Any] else { return PlanUsage() }
        let fiveHour = utilization["five_hour"] as? [String: Any]
        let sevenDay = utilization["seven_day"] as? [String: Any]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return PlanUsage(
            fiveHourPercent: (fiveHour?["utilization"] as? NSNumber)?.intValue,
            sevenDayPercent: (sevenDay?["utilization"] as? NSNumber)?.intValue,
            fiveHourResetsAt: (fiveHour?["resets_at"] as? String).flatMap(formatter.date(from:)),
            fetchedAt: (cache["fetchedAtMs"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
    }

    /// 1M-context models are selected with a "[1m]" suffix on the configured model name.
    private static func readDefaultContextWindow() -> Int {
        let settings = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? String else { return 200_000 }
        return model.contains("[1m]") ? 1_000_000 : 200_000
    }

    // MARK: Hook events

    private func drainHookEvents() {
        let directory = ClaudeHooks.eventsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let session = event["session_id"] as? String else { continue }
            let kind = event["notification_type"] as? String ?? ""
            guard kind == "permission_prompt" || kind == "elicitation_dialog" else { continue }
            hookOverrides[session] = (Date(), event["message"] as? String ?? "Permission needed")
        }
    }
}

/// Installs or removes the optional Notification hook in `~/.claude/settings.json`.
///
/// The hook is a one-line shell command that drops the event JSON into a folder this app
/// watches. It is only ever written when the user asks for it from the Developer settings.
enum ClaudeHooks {
    private static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Alcove Recreation")
    static let eventsDirectory = support.appendingPathComponent("claude-events")
    private static let scriptURL = support.appendingPathComponent("claude-hook.sh")
    /// Claude Code's user settings. Only the `--claude-hook-selftest` diagnostic points this elsewhere.
    static var settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    private static var backupURL: URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.before-alcove-recreation")
    }
    /// Marks our entry so it can be found again without touching anyone else's hooks.
    private static let marker = "Alcove Recreation/claude-hook.sh"

    private static let command =
        "/bin/sh \"$HOME/Library/Application Support/\(marker)\" 2>/dev/null || true"

    private static let script = """
    #!/bin/sh
    # Written by Alcove Recreation. Saves the hook event (JSON on stdin) for the app to pick up.
    d="$HOME/Library/Application Support/Alcove Recreation/claude-events"
    mkdir -p "$d" || exit 0
    # If the app is not running nothing drains the folder; stop adding to it.
    [ "$(ls "$d" | wc -l)" -gt 100 ] && exit 0
    f="$d/$(date +%s)-$$"
    cat > "$f.tmp" && mv "$f.tmp" "$f.json"
    exit 0

    """

    static var isInstalled: Bool {
        guard let root = readSettings(), let hooks = root["hooks"] as? [String: Any],
              let groups = hooks["Notification"] as? [[String: Any]] else { return false }
        return groups.contains(where: isOurs)
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(marker) ?? false }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return [:] }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func install() throws {
        guard var root = readSettings() else { throw CocoaError(.fileReadCorruptFile) }
        let manager = FileManager.default
        try manager.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = (hooks["Notification"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
        groups.append(["hooks": [["type": "command", "command": command, "timeout": 5]]])
        hooks["Notification"] = groups
        root["hooks"] = hooks
        try write(root)
    }

    static func uninstall() throws {
        guard var root = readSettings(), var hooks = root["hooks"] as? [String: Any] else { return }
        let groups = (hooks["Notification"] as? [[String: Any]] ?? []).filter { !isOurs($0) }
        hooks["Notification"] = groups.isEmpty ? nil : groups
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try write(root)
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: eventsDirectory)
    }

    private static func write(_ root: [String: Any]) throws {
        let manager = FileManager.default
        // Keep one pristine copy of the settings from before this app first changed them.
        if manager.fileExists(atPath: settingsURL.path), !manager.fileExists(atPath: backupURL.path) {
            try manager.copyItem(at: settingsURL, to: backupURL)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
    }
}

extension Int {
    /// 470_411 → "470k", 1_200_000 → "1.2M"
    var abbreviatedTokens: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return "\(self / 1_000)k" }
        return "\(self)"
    }
}
