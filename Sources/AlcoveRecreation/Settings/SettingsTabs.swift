import AppKit
import Combine
import SwiftUI

// Row titles are the original's English strings (Localizable.strings), so each toggle
// here corresponds to the same-named option there.

struct GeneralSettingsView: View {
    @AppStorage(Key.launchAtLogin) private var launchAtLogin = false
    @AppStorage(Key.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(Key.hideFromScreenCapture) private var hideFromScreenCapture = false
    @AppStorage(Key.hideWhileInFullscreen) private var hideWhileInFullscreen = true
    @AppStorage(Key.hideWhileGaming) private var hideWhileGaming = false
    @AppStorage(Key.forceSimulatedNotch) private var forceSimulatedNotch = false
    @AppStorage(Key.showOnDisplay) private var showOnDisplay = DisplayType.mainScreen
    @AppStorage(Key.showOnDisplayUUID) private var showOnDisplayUUID = ""
    @AppStorage(Key.contrastOutline) private var contrastOutline = true
    @AppStorage(Key.mostRecentActivity) private var mostRecentActivity = false
    @AppStorage(Key.idleActivity) private var idleActivity = ExpandedActivity.nowPlaying
    @AppStorage(Key.forceEnableActivity) private var forceEnableActivity = false
    @AppStorage(Key.enableHaptics) private var enableHaptics = true
    @AppStorage(Key.expandNotchOnHover) private var expandNotchOnHover = false
    @AppStorage(Key.hoverDuration) private var hoverDuration = 0.0
    @AppStorage(Key.naturalMovement) private var naturalMovement = false
    @AppStorage(Key.swipeToToggle) private var swipeToToggle = true
    @AppStorage(Key.swipeToCycleActivity) private var swipeToCycleActivity = true
    @AppStorage(Key.swipeToDismiss) private var swipeToDismiss = true
    @AppStorage(Key.swipeToSkip) private var swipeToSkip = true
    @AppStorage(Key.notchAdjustedWidth) private var notchAdjustedWidth = 0.0
    @AppStorage(Key.notchAdjustedHeight) private var notchAdjustedHeight = 0.0

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Hide menu bar icon", isOn: $hideMenuBarIcon)
                Toggle("Hide from screen capture", isOn: $hideFromScreenCapture)
                Toggle("Hide in fullscreen", isOn: $hideWhileInFullscreen)
                Toggle("Hide while gaming", isOn: $hideWhileGaming)
            }
            Section("Display") {
                OptionPicker(title: "Display on", selection: $showOnDisplay, label: \.title)
                if showOnDisplay == .specificDisplay {
                    Picker("Selected display", selection: $showOnDisplayUUID) {
                        ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                            Text(screen.localizedName).tag(screen.displayUUID)
                        }
                    }
                }
                Toggle("Force simulated notch", isOn: $forceSimulatedNotch)
            }
            Section("Behaviour") {
                Toggle("Contrast outline", isOn: $contrastOutline)
                Toggle("Haptic feedback", isOn: $enableHaptics)
                Toggle("Expand on hover", isOn: $expandNotchOnHover)
                if expandNotchOnHover {
                    ValueAdjuster(title: "Hover duration", value: $hoverDuration, range: 0...2, step: 0.1)
                }
            }
            Section("Idle Activity") {
                Toggle("Most Recent", isOn: $mostRecentActivity)
                OptionPicker(title: "Idle Activity", selection: $idleActivity, label: \.title, segmented: true)
                    .labelsHidden()
                    .disabled(mostRecentActivity)
                Toggle("Force enable activity", isOn: $forceEnableActivity)
            }
            Section("Gestures") {
                Toggle("Natural movement", isOn: $naturalMovement)
                Toggle("Swipe to toggle open", isOn: $swipeToToggle)
                Toggle("Swipe to cycle activity", isOn: $swipeToCycleActivity)
                Toggle("Swipe to dismiss activity", isOn: $swipeToDismiss)
                Toggle("Swipe to skip media", isOn: $swipeToSkip)
            }
            Section("Tuning") {
                ValueAdjuster(title: "Notch width", value: $notchAdjustedWidth, range: -20...20, step: 1, suffix: "pt")
                ValueAdjuster(title: "Notch height", value: $notchAdjustedHeight, range: -6...6, step: 0.5, suffix: "pt")
            }
        }
    }
}

struct BatterySettingsView: View {
    @AppStorage(Key.enableBattery) private var enableBattery = true
    @AppStorage(Key.batteryDuration) private var batteryDuration = 5.0
    @AppStorage(Key.notifyOnLowPowerMode) private var notifyOnLowPowerMode = true
    @AppStorage(Key.warnOnLowBattery) private var warnOnLowBattery = true
    @AppStorage(Key.lowBatteryThreshold) private var lowBatteryThreshold = 10.0
    @AppStorage(Key.playSoundOnLowBattery) private var playSoundOnLowBattery = true
    @AppStorage(Key.hideBatteryLabel) private var hideBatteryLabel = false
    @AppStorage(Key.hideBatteryPercentage) private var hideBatteryPercentage = false

    var body: some View {
        Form {
            Section {
                Toggle("Battery", isOn: $enableBattery)
                ValueAdjuster(title: "Duration", value: $batteryDuration, range: 1...10)
                Toggle("Hide label", isOn: $hideBatteryLabel)
                Toggle("Hide percentage", isOn: $hideBatteryPercentage)
            }
            Section {
                Toggle("Notify on low power mode", isOn: $notifyOnLowPowerMode)
                Toggle("Warn on low battery", isOn: $warnOnLowBattery)
                ValueAdjuster(title: "Low battery threshold", value: $lowBatteryThreshold, range: 5...50, step: 5, suffix: "%")
                    .disabled(!warnOnLowBattery)
                Toggle("Play sound on low battery", isOn: $playSoundOnLowBattery).disabled(!warnOnLowBattery)
            }
            Section {
                Button("Preview") { NotchCoordinator.shared.forEach { $0.present(.isCharging) } }
            }
        }
        .disabledSections(unless: enableBattery)
    }
}

struct ConnectivitySettingsView: View {
    @AppStorage(Key.enableConnectivity) private var enableConnectivity = true
    @AppStorage(Key.connectivityDuration) private var connectivityDuration = 5.0

    var body: some View {
        Form {
            Section {
                Toggle("Connectivity", isOn: $enableConnectivity)
                ValueAdjuster(title: "Duration", value: $connectivityDuration, range: 1...10)
            } footer: {
                Text("Shown when a Bluetooth audio device becomes the output. The original's 3D AirPods models and battery read-outs are not part of this recreation.")
            }
            Section {
                Button("Preview") {
                    NotchCoordinator.shared.forEach { $0.present(.didConnectAirPods, device: ("AirPods Pro", "airpods.pro")) }
                }
            }
        }
    }
}

struct FocusSettingsView: View {
    @AppStorage(Key.enableFocus) private var enableFocus = true
    @AppStorage(Key.focusDuration) private var focusDuration = 5.0
    @AppStorage(Key.playSoundOnSleepFocus) private var playSoundOnSleepFocus = false
    @AppStorage(Key.hideLabel) private var hideLabel = false
    private let focus = FocusManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Focus", isOn: $enableFocus)
                ValueAdjuster(title: "Duration", value: $focusDuration, range: 1...10)
                Toggle("Hide label", isOn: $hideLabel)
                Toggle("Play sound on sleep focus", isOn: $playSoundOnSleepFocus)
            } footer: {
                if !focus.isReadable {
                    Text("Focus changes are read from the system's Focus store, which requires Full Disk Access for \(AppInfo.name).")
                }
            }
            if !focus.isReadable {
                Section {
                    Button("Open Settings...") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
}

/// Shared by the Display (brightness) and Sound (volume) tabs, which the original also
/// builds from one set of HUD options.
struct HUDSettingsView: View {
    enum Kind { case brightness, volume }
    let kind: Kind

    @AppStorage(Key.enableBrightness) private var enableBrightness = false
    @AppStorage(Key.brightnessDuration) private var brightnessDuration = 1.5
    @AppStorage(Key.brightnessProgressStyle) private var brightnessProgressStyle = HUDProgressStyle.white
    @AppStorage(Key.brightnessSpeed) private var brightnessSpeed = HUDSpeed.fast
    @AppStorage(Key.showBrightnessPercentage) private var showBrightnessPercentage = false
    @AppStorage(Key.hideBrightnessLabel) private var hideBrightnessLabel = false

    @AppStorage(Key.enableVolume) private var enableVolume = false
    @AppStorage(Key.volumeDuration) private var volumeDuration = 1.5
    @AppStorage(Key.volumeProgressStyle) private var volumeProgressStyle = HUDProgressStyle.white
    @AppStorage(Key.volumeSpeed) private var volumeSpeed = HUDSpeed.fast
    @AppStorage(Key.showVolumePercentage) private var showVolumePercentage = false
    @AppStorage(Key.hideVolumeLabel) private var hideVolumeLabel = false
    @AppStorage(Key.volumeOutputDevice) private var volumeOutputDevice = OutputDevice.device

    @LocalState private var isTrusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("HUDs") {
                Toggle(kind == .brightness ? "Display" : "Sound", isOn: kind == .brightness ? $enableBrightness : $enableVolume)
                ValueAdjuster(title: "Duration", value: kind == .brightness ? $brightnessDuration : $volumeDuration, range: 0.5...5)
                OptionPicker(
                    title: "Speed", selection: kind == .brightness ? $brightnessSpeed : $volumeSpeed,
                    label: \.title, segmented: true)
                OptionPicker(
                    title: "Style", selection: kind == .brightness ? $brightnessProgressStyle : $volumeProgressStyle,
                    label: \.title, segmented: true)
                Toggle("Show percentage", isOn: kind == .brightness ? $showBrightnessPercentage : $showVolumePercentage)
                Toggle("Hide label", isOn: kind == .brightness ? $hideBrightnessLabel : $hideVolumeLabel)
                if kind == .volume {
                    OptionPicker(title: "Output device", selection: $volumeOutputDevice, label: \.title, segmented: true)
                }
            }
            Section {
                if isTrusted {
                    Label("Replacing the system HUD", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("The system HUD still appears", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("\(AppInfo.name) needs your permission to hide and replace the system HUDs. Turn it on under Privacy & Security → Accessibility; if it is already listed there, switch it off and on again.")
                        .foregroundStyle(.secondary)
                    Button("Grant Permission") {
                        MediaKeyManager.promptForAccessibility()
                        MediaKeyManager.openAccessibilitySettings()
                    }
                }
                Button("Preview") {
                    NotchCoordinator.shared.forEach { $0.present(kind == .brightness ? .didChangeBrightness : .didChangeVolume) }
                }
            }
        }
        .onReceive(timer) { _ in isTrusted = AXIsProcessTrusted() }
    }
}

struct NowPlayingSettingsView: View {
    @AppStorage(Key.enableNowPlaying) private var enableNowPlaying = true
    @AppStorage(Key.automaticMusicApp) private var automaticMusicApp = true
    @AppStorage(Key.musicApp) private var musicApp = MusicApp.system
    @AppStorage(Key.controlChoice) private var controlChoice = ControlType.shuffle
    @AppStorage(Key.progressStyle) private var progressStyle = ColorStyle.mono
    @AppStorage(Key.idleDuration) private var idleDuration = 3.0
    @AppStorage(Key.hideIdleDuration) private var hideIdleDuration = 10.0
    @AppStorage(Key.hideWhileSourceIsActive) private var hideWhileSourceIsActive = false
    @AppStorage(Key.enableQuickPeek) private var enableQuickPeek = true
    @AppStorage(Key.whenSongChanges) private var whenSongChanges = true
    @AppStorage(Key.peekDuration) private var peekDuration = 2.0
    @AppStorage(Key.disableAlbumArtFlip) private var disableAlbumArtFlip = false
    @AppStorage(Key.disableWaveform) private var disableWaveform = false
    @AppStorage(Key.hideSongTitleExtras) private var hideSongTitleExtras = false
    @AppStorage(Key.showVolumeControl) private var showVolumeControl = false
    private let media = MediaManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Now Playing", isOn: $enableNowPlaying)
                Toggle("Automatic", isOn: $automaticMusicApp)
                if !automaticMusicApp {
                    Picker("Source", selection: $musicApp) {
                        Text("Music").tag(MusicApp.music)
                        Text("Spotify").tag(MusicApp.spotify)
                    }
                    .pickerStyle(.segmented)
                }
            } footer: {
                if !media.appleEventsAllowed {
                    Text("\(AppInfo.name) needs your permission to control and display your playing music. Allow it under Privacy & Security → Automation.")
                } else {
                    Text("This recreation follows Spotify and Music. System-wide Now Playing (browsers and other apps) is not available to it.")
                }
            }
            Section {
                OptionPicker(title: "Control", selection: $controlChoice, label: \.title)
                OptionPicker(title: "Progress", selection: $progressStyle, label: \.title, segmented: true)
                Toggle("Hide while source app is active", isOn: $hideWhileSourceIsActive)
                Toggle("Show volume control", isOn: $showVolumeControl)
                Toggle("Disable artwork flip", isOn: $disableAlbumArtFlip)
                Toggle("Disable compact waveform", isOn: $disableWaveform)
                Toggle("Hide media title extras", isOn: $hideSongTitleExtras)
            }
            Section("Quick Peek") {
                Toggle("Quick Peek", isOn: $enableQuickPeek)
                Toggle("When media changes", isOn: $whenSongChanges).disabled(!enableQuickPeek)
                ValueAdjuster(title: "Peek duration", value: $peekDuration, range: 1...8).disabled(!enableQuickPeek)
            }
            Section {
                ValueAdjuster(title: "Idle duration", value: $idleDuration, range: 0...30, step: 1)
                ValueAdjuster(title: "Duration", value: $hideIdleDuration, range: 5...120, step: 5)
            } footer: {
                Text("How long a paused player keeps its activity before the notch returns to idle.")
            }
        }
    }
}

struct CalendarSettingsView: View {
    @AppStorage(Key.enableCalendar) private var enableCalendar = false
    @AppStorage(Key.timeBeforeEvent) private var timeBeforeEvent = 15.0
    @AppStorage(Key.playSoundOnCalendarEvent) private var playSoundOnCalendarEvent = true
    @AppStorage(Key.useCalendarColor) private var useCalendarColor = false
    @AppStorage(Key.useEventIndicators) private var useEventIndicators = false
    @AppStorage(Key.playHourlyChime) private var playHourlyChime = false
    @AppStorage(Key.enableCalendarQuickPeek) private var enableCalendarQuickPeek = true
    @AppStorage(Key.beforeEventStarts) private var beforeEventStarts = false
    @AppStorage(Key.whenEventIsStarting) private var whenEventIsStarting = true
    @AppStorage(Key.calendarPeekDuration) private var calendarPeekDuration = 4.0
    @LocalState private var excluded = Prefs.stringSet(Key.excludedCalendars)
    private let calendar = CalendarManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Calendar", isOn: $enableCalendar)
                    .onChange(of: enableCalendar) { _, enabled in
                        if enabled, !calendar.isAuthorized { calendar.requestAccess() }
                    }
                if enableCalendar, !calendar.isAuthorized {
                    Text("\(AppInfo.name) needs your permission to access your events.").foregroundStyle(.secondary)
                    Button("Ask Permission...") { calendar.requestAccess() }
                    Button("Open Settings...") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Section {
                ValueAdjuster(title: "Time before event", value: $timeBeforeEvent, range: 1...60, step: 1, suffix: "m")
                Toggle("Play sound on calendar event", isOn: $playSoundOnCalendarEvent)
                Toggle("Use calendar color", isOn: $useCalendarColor)
                Toggle("Use event indicators", isOn: $useEventIndicators)
                Toggle("Play hourly chime", isOn: $playHourlyChime)
            }
            Section("Quick Peek") {
                Toggle("Quick Peek", isOn: $enableCalendarQuickPeek)
                Toggle("Before event starts", isOn: $beforeEventStarts).disabled(!enableCalendarQuickPeek)
                Toggle("When event is starting", isOn: $whenEventIsStarting).disabled(!enableCalendarQuickPeek)
                ValueAdjuster(title: "Peek duration", value: $calendarPeekDuration, range: 1...10).disabled(!enableCalendarQuickPeek)
            }
            if calendar.isAuthorized {
                Section("Calendars") {
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(item.calendarIdentifier) },
                            set: { included in
                                if included { excluded.remove(item.calendarIdentifier) } else { excluded.insert(item.calendarIdentifier) }
                                Prefs.store.set(Array(excluded), forKey: Key.excludedCalendars)
                            })) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(nsColor: item.color)).frame(width: 9, height: 9)
                                Text(item.title)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FileTraySettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("File Tray").font(.title3.weight(.semibold))
            Text("Soon").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LockScreenSettingsView: View {
    @AppStorage(Key.enableLockScreen) private var enableLockScreen = true
    @AppStorage(Key.playSoundOnLock) private var playSoundOnLock = false
    @AppStorage(Key.playSoundOnUnlock) private var playSoundOnUnlock = true

    var body: some View {
        Form {
            Section {
                Toggle("Lock Screen", isOn: $enableLockScreen)
                Toggle("Play sound on lock", isOn: $playSoundOnLock)
                Toggle("Play sound on unlock", isOn: $playSoundOnUnlock)
            } footer: {
                Text("The original draws widgets on top of the macOS lock screen using private window-server Spaces. This recreation only tracks lock state for the lock activity and sounds.")
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            NotchShape(style: .notch, topCornerRadius: 8, bottomCornerRadius: 16)
                .fill(.black)
                .frame(width: 150, height: 44)
                .overlay(
                    Waveform(isPlaying: true, colors: [.pink, .orange], size: CGSize(width: 22, height: 16)))
            Text(AppInfo.name).font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("An independent recreation of the Alcove notch app, rebuilt from analysis of its shipped behaviour. Not affiliated with or endorsed by its developer; licensing and bundled media from the original are intentionally left out.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            UpdateStatusView()
            HStack {
                Button("Permissions...") { PermissionsController.shared.show(onboarding: false) }
                Button("Reset Onboarding") {
                    Prefs.store.set(true, forKey: Key.isFirstLaunch)
                    AppState.startOnboarding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Update controls for the About tab. Not in the original.
struct UpdateStatusView: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(Key.autoCheckForUpdates) private var autoCheck = true

    var body: some View {
        VStack(spacing: 8) {
            switch updater.state {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking for updates...").foregroundStyle(.secondary)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 220)
                Text("Downloading update...").foregroundStyle(.secondary)
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing and relaunching...").foregroundStyle(.secondary)
            case .available(let release):
                Text("Version \(release.version) is available").fontWeight(.medium)
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(release.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 380, maxHeight: 90)
                }
                HStack {
                    Button("Install and Relaunch") { updater.installAvailable() }.buttonStyle(.borderedProminent)
                    Button("Release Page") { updater.openReleasePage() }
                }
            case .upToDate:
                Text("You're up to date.").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red).multilineTextAlignment(.center).frame(maxWidth: 380)
                if updater.availableRelease != nil { Button("Release Page") { updater.openReleasePage() } }
            case .idle:
                if let last = updater.lastChecked {
                    Text("Last checked \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !updater.isBusy, updater.availableRelease == nil {
                Button("Check for Updates") { updater.check() }.disabled(!updater.isConfigured)
            }
            if !updater.isConfigured {
                Text("No update repository is set (UpdateRepository in Info.plist).").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Check for updates automatically", isOn: $autoCheck).toggleStyle(.checkbox)
        }
    }
}

private extension View {
    func disabledSections(unless enabled: Bool) -> some View {
        opacity(enabled ? 1 : 0.6)
    }
}

/// Not in the original: shows Claude Code sessions in the notch.
struct DeveloperSettingsView: View {
    @AppStorage(Key.enableClaudeStatus) private var enableClaudeStatus = false
    @AppStorage(Key.claudePrioritize) private var claudePrioritize = true
    @AppStorage(Key.claudeShowLabel) private var claudeShowLabel = true
    @AppStorage(Key.claudeShowUsage) private var claudeShowUsage = true
    @AppStorage(Key.claudeUsageMetric) private var claudeUsageMetric = ClaudeUsageMetric.planLimit
    @AppStorage(Key.claudePeek) private var claudePeek = true
    @AppStorage(Key.claudeFinishedDuration) private var claudeFinishedDuration = 8.0
    @LocalState private var hooksInstalled = ClaudeHooks.isInstalled
    @LocalState private var hookError: String?
    @LocalState private var confirmingInstall = false
    private let claude = ClaudeManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Claude Code status", isOn: $enableClaudeStatus)
                LabeledContent("Now") { Text(summary).foregroundStyle(.secondary) }
            } footer: {
                Text("Shows whether Claude is coding, finished, or waiting for you, for sessions in the terminal and in the Claude desktop app. Read from the session files Claude Code keeps under ~/.claude; nothing is sent anywhere.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Notch") {
                Toggle("Prioritize over Now Playing and Calendar", isOn: $claudePrioritize)
                Toggle("Show status label", isOn: $claudeShowLabel)
                Toggle("Show usage", isOn: $claudeShowUsage)
                OptionPicker(title: "Usage", selection: $claudeUsageMetric, label: \.title, segmented: true)
                    .disabled(!claudeShowUsage)
                Toggle("Peek when finished or waiting", isOn: $claudePeek)
                ValueAdjuster(title: "Keep \"Finished\" for", value: $claudeFinishedDuration, range: 3...60, step: 1)
            }
            .disabled(!enableClaudeStatus)
            Section {
                LabeledContent("Permission prompts") {
                    Text(hooksInstalled ? "Hook installed" : "Not detected").foregroundStyle(hooksInstalled ? .green : .secondary)
                }
                Button(hooksInstalled ? "Remove Hook" : "Install Hook...") {
                    if hooksInstalled { runHookChange(ClaudeHooks.uninstall) } else { confirmingInstall = true }
                }
                if let hookError { Text(hookError).foregroundStyle(.red) }
            } header: {
                Text("Hook")
            } footer: {
                Text("Claude Code writes nothing to a session while a permission prompt is open, so those look like work in progress. Installing adds one Notification hook to ~/.claude/settings.json (your other hooks are kept, and a backup is saved next to it) so prompts show as \"Needs you\".")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .confirmationDialog("Add a hook to Claude Code?", isPresented: $confirmingInstall) {
            Button("Install Hook") { runHookChange(ClaudeHooks.install) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This edits ~/.claude/settings.json. Sessions that are already running pick it up after a restart.")
        }
    }

    private var summary: String {
        guard enableClaudeStatus else { return "Off" }
        guard let session = claude.current else { return "No active session" }
        var parts = [session.status.title, session.projectName, "\(session.contextTokens.abbreviatedTokens) context"]
        if let percent = claude.planUsage.fiveHourPercent { parts.append("5h \(percent)%") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func runHookChange(_ change: () throws -> Void) {
        do {
            try change()
            hookError = nil
        } catch {
            hookError = "Could not update Claude Code settings: \(error.localizedDescription)"
        }
        hooksInstalled = ClaudeHooks.isInstalled
    }
}

/// Workarounds and diagnostics for problems that only show up on some Macs.
struct DebugSettingsView: View {
    @AppStorage(Key.fixBrightnessBug) private var fixBrightnessBug = true
    @LocalState private var copied = false

    private static let logCommand = "log show --last 30m --info --predicate 'subsystem == \"local.alcove-recreation\"'"

    var body: some View {
        Form {
            Section {
                Toggle("Fix Brightness Bug", isOn: $fixBrightnessBug)
            } header: {
                Text("Brightness")
            } footer: {
                Text("On: the brightness HUD appears only when you press a brightness key, F14/F15 (Scroll Lock/Pause on PC keyboards) are left alone, and keys sent by other apps are passed straight to macOS. Turn it off if your brightness keys stop showing the HUD, for example on a keyboard whose driver sends them through software.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent("Version", value: "\(AppInfo.version) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                LabeledContent("Key interception", value: MediaKeyManager.shared.isIntercepting ? "Active" : "Off (needs Accessibility)")
                Button(copied ? "Copied" : "Copy Log Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.logCommand, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Paste the command into Terminal to see which apps sent media keys that were ignored, and which brightness presses were handled. Useful to include in a bug report.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
