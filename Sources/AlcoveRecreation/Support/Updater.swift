import AppKit
import CryptoKit
import Foundation
import os
import Security

/// Not in the original: checks GitHub Releases for a newer build, downloads it, and swaps it in.
///
/// A release is expected to carry a `.zip` asset holding `Alcove Recreation.app` (Scripts/release.sh
/// builds one). The repository comes from `UpdateRepository` in Info.plist (`owner/name`); the
/// `updateRepository` default overrides it for testing.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let pageURL: URL
        let assetURL: URL
        let assetSize: Int
        /// Hex SHA-256 from GitHub's asset metadata, when it provides one.
        let sha256: String?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    private let log = Logger(subsystem: "local.alcove-recreation", category: "Updater")
    private var timer: Timer?
    private var task: Task<Void, Never>?

    private static let checkInterval: TimeInterval = 24 * 3600

    private init() {
        lastChecked = Prefs.store.object(forKey: Key.lastUpdateCheck) as? Date
    }

    // MARK: Configuration

    static var repository: String? {
        let value = Prefs.string(Key.updateRepository)
            ?? Bundle.main.object(forInfoDictionaryKey: "UpdateRepository") as? String
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.split(separator: "/").count == 2 else { return nil }
        return value
    }

    var isConfigured: Bool { Self.repository != nil }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// True while a check or install is under way, so the UI can disable its buttons.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    // MARK: Scheduling

    /// Checks shortly after launch and then about once a day, when the user has not turned it off.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard Prefs.bool(Key.autoCheckForUpdates), isConfigured, !isBusy, availableRelease == nil else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    // MARK: Checking

    func check(userInitiated: Bool = true) {
        guard !isBusy else { return }
        guard let repository = Self.repository else {
            if userInitiated { state = .failed("No update repository is configured.") }
            return
        }
        state = .checking
        task = Task {
            do {
                let release = try await Self.fetchLatest(repository: repository)
                lastChecked = Date()
                Prefs.store.set(lastChecked, forKey: Key.lastUpdateCheck)
                if let release, Self.isNewer(release.version, than: AppInfo.version) {
                    log.info("Update available: \(release.version, privacy: .public)")
                    state = .available(release)
                } else {
                    state = userInitiated ? .upToDate : .idle
                }
            } catch {
                log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                state = userInitiated ? .failed(error.localizedDescription) : .idle
            }
        }
    }

    private struct APIRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int
            let digest: String?
            let browserDownloadURL: URL
            enum CodingKeys: String, CodingKey {
                case name, size, digest
                case browserDownloadURL = "browser_download_url"
            }
        }
        let tagName: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name", body, assets
            case htmlURL = "html_url"
        }
    }

    private static func fetchLatest(repository: String) async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil } // no published release yet
        guard status == 200 else { throw UpdateError.http(status) }

        let api = try JSONDecoder().decode(APIRelease.self, from: data)
        let asset = api.assets.first { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset else { throw UpdateError.noAsset }
        var digest: String?
        if let value = asset.digest, value.hasPrefix("sha256:") { digest = String(value.dropFirst(7)).lowercased() }
        return Release(
            version: normalized(api.tagName), notes: api.body ?? "", pageURL: api.htmlURL,
            assetURL: asset.browserDownloadURL, assetSize: asset.size, sha256: digest)
    }

    /// "v1.2.3" → "1.2.3"
    nonisolated static func normalized(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Numeric, component-wise comparison; missing components count as zero ("1.1" == "1.1.0").
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let new = parts(candidate), old = parts(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    // MARK: Installing

    func installAvailable() {
        guard let release = availableRelease else { return }
        state = .downloading(0)
        task = Task {
            do {
                let staging = try await Self.prepare(release) { [weak self] fraction in
                    Task { @MainActor in self?.state = .downloading(fraction) }
                }
                state = .installing
                try Self.relaunch(into: staging.app, workDirectory: staging.directory)
                NSApp.terminate(nil)
            } catch {
                log.error("Update failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasePage() {
        if let release = availableRelease { NSWorkspace.shared.open(release.pageURL) }
    }

    /// Downloads, unpacks and vets the release; returns the new bundle inside a temporary directory.
    private nonisolated static func prepare(
        _ release: Release, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (app: URL, directory: URL) {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("alcove-update-\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var request = URLRequest(url: release.assetURL)
            request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
            let (downloaded, response) = try await URLSession.shared.download(
                for: request, delegate: ProgressDelegate(progress))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError.http(status) }

            if let expected = release.sha256, try sha256(of: downloaded) != expected { throw UpdateError.checksum }

            let archive = directory.appendingPathComponent("update.zip")
            try fm.moveItem(at: downloaded, to: archive)
            let unpacked = directory.appendingPathComponent("unpacked")
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path])

            let apps = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "app" }
            guard apps.count == 1, let app = apps.first else { throw UpdateError.badArchive }
            try verify(app, expectedVersion: release.version)
            return (app, directory)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    /// The new bundle must be intact, signed by the same team as this one, and the version announced.
    private nonisolated static func verify(_ app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              normalized(version) == expectedVersion,
              isNewer(version, than: AppInfo.version)
        else { throw UpdateError.badBundle }

        guard let code = staticCode(app),
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate
                  | kSecCSCheckNestedCode), nil) == errSecSuccess
        else { throw UpdateError.signature }

        // Privacy grants and trust follow the signing identity, so never swap in a different one.
        if let current = staticCode(Bundle.main.bundleURL).flatMap(teamIdentifier), teamIdentifier(of: code) != current {
            throw UpdateError.signature
        }
    }

    private nonisolated static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess ? code : nil
    }

    private nonisolated static func teamIdentifier(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.badArchive }
    }

    /// Hands the swap to a detached script: this process cannot replace its own bundle while it runs.
    private static func relaunch(into newApp: URL, workDirectory: URL) throws {
        let destination = Bundle.main.bundleURL
        let parent = destination.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else { throw UpdateError.notWritable(parent) }

        // Arguments are passed positionally, so no path is ever interpolated into the script.
        let script = """
            #!/bin/zsh
            pid="$1"; new="$2"; dest="$3"; work="$4"
            for _ in {1..120}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
            backup="$dest.previous"
            rm -rf "$backup"
            mv "$dest" "$backup" || exit 1
            if ditto "$new" "$dest"; then
                rm -rf "$backup"
            else
                rm -rf "$dest"; mv "$backup" "$dest"
            fi
            open "$dest"
            rm -rf "$work"
            """
        let scriptURL = workDirectory.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = [String(ProcessInfo.processInfo.processIdentifier), newApp.path, destination.path, workDirectory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

enum UpdateError: LocalizedError {
    case http(Int), noAsset, checksum, badArchive, badBundle, signature, notWritable(String)

    var errorDescription: String? {
        switch self {
        case .http(0): "Could not reach GitHub."
        case .http(403), .http(429): "GitHub is rate limiting requests. Try again later."
        case .http(let code): "GitHub answered with status \(code)."
        case .noAsset: "The latest release has no .zip download."
        case .checksum: "The download did not match its checksum."
        case .badArchive: "The download could not be unpacked."
        case .badBundle: "The download is not the expected version of \(AppInfo.name)."
        case .signature: "The download is not signed by the same developer as this app."
        case .notWritable(let folder): "\(folder) is not writable, so the app cannot replace itself. Download the release instead."
        }
    }
}

/// Reports a download task's progress.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
            report(progress.fractionCompleted)
        }
    }
}
