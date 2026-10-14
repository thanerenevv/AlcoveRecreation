import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
enum AppMain {
    static func main() {
        // Diagnostic: print how a Claude Code transcript is interpreted, without starting the app.
        if let index = CommandLine.arguments.firstIndex(of: "--claude-status"), CommandLine.arguments.count > index + 1 {
            print(ClaudeManager.describeTranscript(at: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
            return
        }
        // Diagnostic: install and remove the hook against a copy of a settings file.
        if let index = CommandLine.arguments.firstIndex(of: "--claude-hook-selftest"), CommandLine.arguments.count > index + 1 {
            ClaudeHooks.settingsURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let step = CommandLine.arguments.count > index + 2 ? CommandLine.arguments[index + 2] : "install"
            do {
                try (step == "uninstall" ? ClaudeHooks.uninstall() : ClaudeHooks.install())
                print("\(step) ok, installed=\(ClaudeHooks.isInstalled)")
            } catch {
                print("\(step) failed: \(error)")
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        appState.installStatusItem()

        VolumeManager.shared.start()
        BrightnessManager.shared.start()
        BatteryManager.shared.start()
        MediaManager.shared.start()
        CalendarManager.shared.start()
        FocusManager.shared.start()
        LockManager.shared.start()
        ClaudeManager.shared.start()
        ScreenManager.shared.start()
        MediaKeyManager.shared.start()
        NotchCoordinator.shared.start()
        wireManagers()
        Updater.shared.start()

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.settingsDidChange() }

        if Prefs.bool(Key.isFirstLaunch) {
            AppState.startOnboarding()
        } else if (Prefs.bool(Key.enableVolume) || Prefs.bool(Key.enableBrightness)), !AXIsProcessTrusted() {
            // The HUDs are on but the keys cannot be intercepted yet, so macOS would still draw
            // its own. Ask once per launch; the system only shows its dialog the first time.
            MediaKeyManager.promptForAccessibility()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsController.shared.show()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // alcove-recreation://settings[/<tab>] | permissions | expand | collapse | preview/<volume|brightness|charging|
        // low-battery|low-power|connectivity|focus>
        for url in urls {
            let notches = NotchCoordinator.shared
            switch url.host {
            case "settings": SettingsController.shared.show(tab: SettingsTab(rawValue: url.lastPathComponent))
            case "permissions": PermissionsController.shared.show(onboarding: false)
            case "expand": notches.forEach { $0.expand() }
            case "collapse": notches.forEach { $0.collapse() }
            case "preview":
                let previews: [String: NotchController.Notification] = [
                    "volume": .didChangeVolume, "brightness": .didChangeBrightness, "charging": .isCharging,
                    "low-battery": .isLowBattery, "low-power": .isLowPowerMode, "connectivity": .didConnectAirPods,
                    "focus": .isFocus,
                ]
                guard let notification = previews[url.lastPathComponent] else { continue }
                notches.forEach { $0.present(notification) }
            default: break
            }
        }
    }

    /// Routes manager events to every notch on screen.
    private func wireManagers() {
        let notches = NotchCoordinator.shared

        VolumeManager.shared.onChange = {
            guard Prefs.bool(Key.enableVolume) else { return }
            notches.forEach { $0.present(.didChangeVolume) }
        }
        VolumeManager.shared.onOutputDeviceChange = { name, symbol in
            guard Prefs.bool(Key.enableConnectivity), VolumeManager.shared.isWirelessOutput else { return }
            notches.forEach { $0.present(.didConnectAirPods, device: (name, symbol)) }
        }
        BrightnessManager.shared.onChange = {
            guard Prefs.bool(Key.enableBrightness) else { return }
            notches.forEach { $0.present(.didChangeBrightness) }
        }
        BatteryManager.shared.onEvent = { event in
            let notification: NotchController.Notification
            switch event {
            case .charging: notification = .isCharging
            case .lowBattery: notification = .isLowBattery
            case .lowPowerMode: notification = .isLowPowerMode
            }
            notches.forEach { $0.present(notification) }
        }
        FocusManager.shared.onChange = {
            notches.forEach { $0.present(.isFocus) }
        }
        LockManager.shared.onChange = {
            notches.forEach { $0.refreshLiveActivity(animated: true) }
        }
        ScreenManager.shared.onChange = {
            notches.forEach {
                $0.evaluateVisibility()
                $0.refreshLiveActivity(animated: true)
            }
        }
        MediaManager.shared.onPlaybackChange = {
            notches.forEach { $0.refreshLiveActivity(animated: true) }
        }
        MediaManager.shared.onTrackChange = {
            notches.forEach {
                $0.refreshLiveActivity(animated: true)
                if Prefs.bool(Key.whenSongChanges) { $0.showQuickPeek(.isPlaying) }
            }
        }
        CalendarManager.shared.onActivityChange = {
            notches.forEach {
                $0.refreshLiveActivity(animated: true)
                if Prefs.bool(Key.beforeEventStarts) { $0.showQuickPeek(.isCalendar) }
            }
        }
        CalendarManager.shared.onEventStarting = { _ in
            guard Prefs.bool(Key.whenEventIsStarting) else { return }
            notches.forEach { $0.showQuickPeek(.isCalendar) }
        }
        ClaudeManager.shared.onChange = { previous in
            let status = ClaudeManager.shared.current?.status ?? .idle
            notches.forEach {
                $0.refreshLiveActivity(animated: true)
                // Finishing, or stopping to wait for the user, is worth a glance.
                if status != previous, status == .finished || status == .needsResponse {
                    $0.showQuickPeek(.isCoding)
                }
            }
            if status != previous, status == .needsResponse { HapticFeedback.shared.tap(.levelChange) }
        }
    }

    private var lastSnapshot: [String: String] = [:]

    private func settingsDidChange() {
        // Only react to keys that change layout or data sources; UserDefaults posts for every write.
        let watched = [
            Key.forceSimulatedNotch, Key.showOnDisplay, Key.showOnDisplayUUID, Key.notchAdjustedWidth,
            Key.notchAdjustedHeight, Key.hideFromScreenCapture, Key.hideWhileInFullscreen, Key.hideWhileGaming,
            Key.hideWhileSourceIsActive, Key.hideMenuBarIcon, Key.enableClaudeStatus, Key.claudePrioritize,
            Key.claudeShowLabel,
            Key.enableNowPlaying, Key.enableCalendar, Key.idleActivity, Key.forceEnableActivity,
            Key.excludedCalendars, Key.enableLockScreen, Key.launchAtLogin, Key.timeBeforeEvent,
        ]
        var snapshot: [String: String] = [:]
        for key in watched { snapshot[key] = Prefs.store.object(forKey: key).map { "\($0)" } ?? "" }
        guard snapshot != lastSnapshot else { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        guard !previous.isEmpty else { return }

        appState.updateStatusItemVisibility()
        if previous[Key.launchAtLogin] != snapshot[Key.launchAtLogin] { AppState.applyLaunchAtLogin() }
        if previous[Key.enableCalendar] != snapshot[Key.enableCalendar]
            || previous[Key.excludedCalendars] != snapshot[Key.excludedCalendars]
            || previous[Key.timeBeforeEvent] != snapshot[Key.timeBeforeEvent] {
            CalendarManager.shared.fetch()
        }
        NotchCoordinator.shared.rebuild()
    }
}

/// Menu bar item and app-level actions.
final class AppState: NSObject {
    private var statusItem: NSStatusItem?
    private var updateItem: NSMenuItem?
    private var updateObserver: AnyCancellable?

    func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.trayIcon()
        item.behavior = .removalAllowed
        let menu = NSMenu()
        menu.addItem(withTitle: "About \(AppInfo.name)", action: #selector(showAbout), keyEquivalent: "").target = self
        let update = menu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        updateItem = update
        updateObserver = MainActor.assumeIsolated { Updater.shared.$state }.receive(on: DispatchQueue.main).sink { [weak update] state in
            if case .available(let release) = state {
                update?.title = "Update Available: \(release.version)..."
            } else {
                update?.title = "Check for Updates..."
            }
        }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(withTitle: "Permissions...", action: #selector(showPermissions), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reset Onboarding", action: #selector(resetOnboarding), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        updateStatusItemVisibility()
    }

    func updateStatusItemVisibility() {
        statusItem?.isVisible = !Prefs.bool(Key.hideMenuBarIcon)
    }

    /// A small notch glyph drawn in code, standing in for the original's TrayIcon asset.
    private static func trayIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NotchShape(style: .notch, topCornerRadius: 2.5, bottomCornerRadius: 4)
                .path(in: CGRect(x: 1, y: 4, width: 16, height: 8))
            NSColor.black.setFill()
            NSBezierPath(cgPath: path.cgPath).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func applyLaunchAtLogin() {
        do {
            if Prefs.bool(Key.launchAtLogin) {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login change failed: \(error.localizedDescription)")
        }
    }

    @objc private func showAbout() { SettingsController.shared.show(tab: .about) }
    @objc private func showSettings() { SettingsController.shared.show() }

    /// The General tab's Software Update section holds the release notes and install button.
    @objc private func checkForUpdates() {
        SettingsController.shared.show(tab: .general)
        Task { @MainActor in
            if Updater.shared.availableRelease == nil { Updater.shared.check() }
        }
    }

    @objc private func showPermissions() { PermissionsController.shared.show(onboarding: false) }

    @objc private func resetOnboarding() {
        Prefs.store.set(true, forKey: Key.isFirstLaunch)
        Self.startOnboarding()
    }

    /// Onboarding is two windows: permissions first, then the welcome screen.
    static func startOnboarding() {
        PermissionsController.shared.show(onboarding: true) {
            IntroController.shared.show()
        }
    }
}
