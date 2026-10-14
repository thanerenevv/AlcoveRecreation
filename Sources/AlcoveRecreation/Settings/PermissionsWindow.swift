import AppKit
import EventKit
import Observation
import SwiftUI

/// Live status of every privacy permission the app can use.
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    enum Status: Equatable {
        case granted
        /// Never asked; the system can still show its own prompt.
        case notDetermined
        /// Refused or not promptable; only System Settings can change it.
        case denied
        /// Automation target is not running, so macOS cannot be asked about it yet.
        case needsApp
    }

    enum Permission: String, CaseIterable, Identifiable {
        case accessibility, spotify, music, calendar, fullDiskAccess

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .spotify: "Automation · Spotify"
            case .music: "Automation · Music"
            case .calendar: "Calendar"
            case .fullDiskAccess: "Full Disk Access"
            }
        }

        var detail: String {
            switch self {
            case .accessibility: "Hide and replace the system volume and brightness HUDs."
            case .spotify: "Control and display what is playing in Spotify."
            case .music: "Control and display what is playing in Music."
            case .calendar: "Show your upcoming events and the next-event countdown."
            case .fullDiskAccess: "Read the current Focus so it can appear in the notch."
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: "accessibility"
            case .spotify: "music.note.list"
            case .music: "music.note"
            case .calendar: "calendar"
            case .fullDiskAccess: "externaldrive.fill"
            }
        }

        var isOptional: Bool { self == .calendar || self == .fullDiskAccess }

        var automationBundleID: String? {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            default: nil
            }
        }

        var settingsPane: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .spotify, .music: "Privacy_Automation"
            case .calendar: "Privacy_Calendars"
            case .fullDiskAccess: "Privacy_AllFiles"
            }
        }
    }

    private(set) var statuses: [Permission: Status] = [:]
    @ObservationIgnored private let queue = DispatchQueue(label: "permissions.status", qos: .userInitiated)
    @ObservationIgnored private var timer: Timer?

    /// Automation rows only make sense for players that are installed.
    var relevantPermissions: [Permission] {
        Permission.allCases.filter { permission in
            guard let bundleID = permission.automationBundleID else { return true }
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
    }

    func status(_ permission: Permission) -> Status { statuses[permission] ?? .notDetermined }

    /// Permissions cannot be observed, so poll while a window that shows them is open.
    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let permissions = relevantPermissions
        queue.async {
            var result: [Permission: Status] = [:]
            for permission in permissions { result[permission] = Self.currentStatus(of: permission) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.statuses != result else { return }
                let previous = self.statuses
                self.statuses = result
                self.statusesDidChange(from: previous)
            }
        }
    }

    private func statusesDidChange(from previous: [Permission: Status]) {
        for permission in [Permission.spotify, .music]
        where statuses[permission] == .granted && previous[permission] != .granted {
            MediaManager.shared.reload()
        }
        if statuses[.calendar] == .granted, previous[.calendar] != .granted {
            CalendarManager.shared.fetch()
        }
    }

    private static func currentStatus(of permission: Permission) -> Status {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .spotify, .music:
            return automationStatus(permission.automationBundleID ?? "", ask: false)
        case .calendar:
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .fullDiskAccess:
            // The user's TCC database is only readable with Full Disk Access; macOS has no API
            // to ask for it, so this one always goes through System Settings.
            let probe = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
            let readable = (try? FileHandle(forReadingFrom: probe))
                .map { handle in try? handle.close(); return true } ?? false
            return readable ? .granted : .denied
        }
    }

    /// With `ask` set this blocks until the user answers the system prompt, so call it off the main thread.
    private static func automationStatus(_ bundleID: String, ask: Bool) -> Status {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return .needsApp }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        switch AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask) {
        case noErr: return .granted
        case -1743: return .denied          // errAEEventNotPermitted
        case -1744: return .notDetermined   // errAEEventWouldRequireUserConsent
        case -600: return .needsApp         // procNotFound
        default: return .notDetermined
        }
    }

    // MARK: Requesting

    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            MediaKeyManager.promptForAccessibility()
            openSettings(for: permission)
        case .spotify, .music:
            requestAutomation(permission)
        case .calendar:
            if status(.calendar) == .notDetermined {
                CalendarManager.shared.requestAccess { [weak self] _ in self?.refresh() }
            } else {
                openSettings(for: permission)
            }
        case .fullDiskAccess:
            openSettings(for: permission)
        }
    }

    private func requestAutomation(_ permission: Permission) {
        guard let bundleID = permission.automationBundleID else { return }
        if status(permission) == .denied {
            openSettings(for: permission)
            return
        }
        let ask = { [weak self] in
            self?.queue.async {
                _ = Self.automationStatus(bundleID, ask: true)
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            // macOS only prompts for a running target, so open the player in the background first.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { _ = ask() }
            }
        } else {
            _ = ask()
        }
    }

    func openSettings(for permission: Permission) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permission.settingsPane)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The permissions window: first step of onboarding, and reachable later from the menu.
final class PermissionsController: NSObject, NSWindowDelegate {
    static let shared = PermissionsController()
    private var windowController: NSWindowController?

    /// - Parameter onboarding: when true, finishing turns on the features that the granted
    ///   permissions unlock and then calls `onContinue`.
    func show(onboarding: Bool, onContinue: (() -> Void)? = nil) {
        windowController?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Permissions"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: PermissionsView(isOnboarding: onboarding) { [weak self] in
            if onboarding { Self.enableUnlockedFeatures() }
            self?.windowController?.close()
            onContinue?()
        })
        window.center()
        windowController = NSWindowController(window: window)
        PermissionCenter.shared.startMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        PermissionCenter.shared.stopMonitoring()
        windowController = nil
    }

    /// The HUDs and the calendar ship switched off because they need a permission; once the
    /// user has granted it during onboarding there is no reason to leave them off.
    private static func enableUnlockedFeatures() {
        let center = PermissionCenter.shared
        if center.status(.accessibility) == .granted {
            Prefs.store.set(true, forKey: Key.enableVolume)
            Prefs.store.set(true, forKey: Key.enableBrightness)
        }
        if center.status(.calendar) == .granted {
            Prefs.store.set(true, forKey: Key.enableCalendar)
        }
    }
}

struct PermissionsView: View {
    let isOnboarding: Bool
    let onContinue: () -> Void

    private let center = PermissionCenter.shared

    private var grantedCount: Int {
        center.relevantPermissions.filter { center.status($0) == .granted }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Permissions").font(.system(size: 22, weight: .bold))
                Text("\(AppInfo.name) asks macOS for these so each feature can work. Optional ones can be skipped and granted here later.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 44)
            }
            .padding(.top, 34)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                let permissions = center.relevantPermissions
                ForEach(Array(permissions.enumerated()), id: \.element) { index, permission in
                    PermissionRow(permission: permission, status: center.status(permission)) {
                        center.request(permission)
                    }
                    if index < permissions.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.5)))
            .padding(.horizontal, 24)

            Spacer(minLength: 12)

            Text("\(grantedCount) of \(center.relevantPermissions.count) granted")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .padding(.bottom, 10)

            Button(action: onContinue) {
                Text(isOnboarding ? "Continue" : "Done")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 560)
        .background(.regularMaterial)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.statuses)
    }
}

private struct PermissionRow: View {
    let permission: PermissionCenter.Permission
    let status: PermissionCenter.Status
    let action: () -> Void

    private var buttonTitle: String {
        switch status {
        case .granted: ""
        case .notDetermined: permission == .accessibility ? "Open Settings..." : "Allow"
        case .denied: "Open Settings..."
        case .needsApp: permission == .spotify ? "Open Spotify" : "Open Music"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title).font(.system(size: 13, weight: .semibold))
                    if permission.isOptional {
                        Text("Optional")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(.secondary.opacity(0.22)))
                    }
                }
                Text(permission.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if status == .granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .transition(.blurReplace)
            } else {
                Button(buttonTitle, action: action)
                    .controlSize(.small)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
