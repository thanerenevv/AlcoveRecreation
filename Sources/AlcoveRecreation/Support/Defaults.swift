import Foundation
import SwiftUI

/// UserDefaults keys. Names match the keys recovered from the original binary's
/// reflection metadata so the settings model lines up one-to-one.
enum Key {
    // General
    static let isFirstLaunch = "isFirstLaunch"
    static let launchAtLogin = "launchAtLogin"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let hideFromScreenCapture = "hideFromScreenCapture"
    static let forceSimulatedNotch = "forceSimulatedNotch"
    static let hideWhileInFullscreen = "hideWhileInFullscreen"
    static let hideWhileGaming = "hideWhileGaming"
    static let hideWhileInMissionControl = "hideWhileInMissionControl"
    static let showOnDisplay = "showOnDisplay"
    static let showOnDisplayUUID = "showOnDisplayUUID"
    static let contrastOutline = "contrastOutline"
    static let progressiveBlur = "progressiveBlur"
    static let mostRecentActivity = "mostRecentActivity"
    static let idleActivity = "idleActivity"
    static let forceEnableActivity = "forceEnableActivity"
    static let enableHaptics = "enableHaptics"
    static let expandNotchOnHover = "expandNotchOnHover"
    static let hoverDuration = "hoverDuration"
    static let naturalMovement = "naturalMovement"
    static let swipeToToggle = "swipeToToggle"
    static let swipeToCycleActivity = "swipeToCycleActivity"
    static let swipeToDismiss = "swipeToDismiss"
    static let swipeToSkip = "swipeToSkip"
    static let notchAdjustedWidth = "notchAdjustedWidth"
    static let notchAdjustedHeight = "notchAdjustedHeight"

    // Battery
    static let enableBattery = "enableBattery"
    static let batteryDuration = "batteryDuration"
    static let notifyOnLowPowerMode = "notifyOnLowPowerMode"
    static let warnOnLowBattery = "warnOnLowBattery"
    static let lowBatteryThreshold = "lowBatteryThreshold"
    static let playSoundOnLowBattery = "playSoundOnLowBattery"
    static let hideBatteryLabel = "hideBatteryLabel"
    static let hideBatteryPercentage = "hideBatteryPercentage"

    // Connectivity
    static let enableConnectivity = "enableConnectivity"
    static let connectivityDuration = "connectivityDuration"
    static let connectivityModel = "connectivityModel"

    // Focus
    static let enableFocus = "enableFocus"
    static let focusDuration = "focusDuration"
    static let playSoundOnSleepFocus = "playSoundOnSleepFocus"
    static let hideLabel = "hideLabel"

    // Display (brightness HUD)
    static let enableBrightness = "enableBrightness"
    static let brightnessDuration = "brightnessDuration"
    static let brightnessProgressStyle = "brightnessProgressStyle"
    static let brightnessSpeed = "brightnessSpeed"
    static let showBrightnessPercentage = "showBrightnessPercentage"
    static let hideBrightnessLabel = "hideBrightnessLabel"
    /// Not in the original; see BrightnessManager and MediaKeyManager.
    static let fixBrightnessBug = "fixBrightnessBug"

    // Sound (volume HUD)
    static let enableVolume = "enableVolume"
    static let volumeDuration = "volumeDuration"
    static let volumeProgressStyle = "volumeProgressStyle"
    static let volumeSpeed = "volumeSpeed"
    static let volumeOutputDevice = "volumeOutputDevice"
    static let showVolumePercentage = "showVolumePercentage"
    static let hideVolumeLabel = "hideVolumeLabel"

    // Now Playing
    static let enableNowPlaying = "enableNowPlaying"
    static let idleDuration = "idleDuration"
    static let hideIdleDuration = "hideIdleDuration"
    static let hideWhileSourceIsActive = "hideWhileSourceIsActive"
    static let controlChoice = "controlChoice"
    static let automaticMusicApp = "automaticMusicApp"
    static let musicApp = "musicApp"
    static let enableQuickPeek = "enableQuickPeek"
    static let whenSongChanges = "whenSongChanges"
    static let peekDuration = "peekDuration"
    static let disableAlbumArtFlip = "disableAlbumArtFlip"
    static let disableWaveform = "disableWaveform"
    static let hideSongTitleExtras = "hideSongTitleExtras"
    static let songTitleBadge = "songTitleBadge"
    static let showVolumeControl = "showVolumeControl"
    static let showRemainingTime = "showRemainingTime"
    static let progressStyle = "progressStyle"

    // Calendar
    static let enableCalendar = "enableCalendar"
    static let timeBeforeEvent = "timeBeforeEvent"
    static let playSoundOnCalendarEvent = "playSoundOnCalendarEvent"
    static let useCalendarColor = "useCalendarColor"
    static let disableActivityDuringEvents = "disableActivityDuringEvents"
    static let useEventIndicators = "useEventIndicators"
    static let alwaysShowMonthView = "alwaysShowMonthView"
    static let playHourlyChime = "playHourlyChime"
    static let excludedCalendars = "excludedCalendars"
    static let enableCalendarQuickPeek = "enableCalendarQuickPeek"
    static let beforeEventStarts = "beforeEventStarts"
    static let whenEventIsStarting = "whenEventIsStarting"
    static let useColoredCalendarIndicator = "useColoredCalendarIndicator"
    static let calendarPeekDuration = "calendarPeekDuration"

    // Lock Screen
    static let enableLockScreen = "enableLockScreen"
    static let playSoundOnLock = "playSoundOnLock"
    static let playSoundOnUnlock = "playSoundOnUnlock"

    // Developer (not part of the original app)
    static let enableClaudeStatus = "enableClaudeStatus"
    static let claudePrioritize = "claudePrioritize"
    static let claudeShowLabel = "claudeShowLabel"
    static let claudeShowUsage = "claudeShowUsage"
    static let claudeUsageMetric = "claudeUsageMetric"
    static let claudePeek = "claudePeek"
    static let claudeFinishedDuration = "claudeFinishedDuration"

    // Updates (not part of the original app)
    static let autoCheckForUpdates = "autoCheckForUpdates"
    static let lastUpdateCheck = "lastUpdateCheck"
    /// Optional "owner/name" override of Info.plist's UpdateRepository, for testing.
    static let updateRepository = "updateRepository"
}

enum Prefs {
    static let store = UserDefaults.standard

    static func registerDefaults() {
        // Default values below are the ones the original registers for the same keys
        // (recovered from its Defaults.Key initializers).
        store.register(defaults: [
            Key.isFirstLaunch: true,
            Key.launchAtLogin: false,
            Key.hideMenuBarIcon: false,
            Key.hideFromScreenCapture: false,
            Key.forceSimulatedNotch: false,
            Key.hideWhileInFullscreen: true,
            Key.hideWhileGaming: false,
            Key.hideWhileInMissionControl: true,
            Key.showOnDisplay: DisplayType.mainScreen.rawValue,
            Key.contrastOutline: true,
            Key.progressiveBlur: true,
            Key.mostRecentActivity: false,
            Key.idleActivity: ExpandedActivity.nowPlaying.rawValue,
            Key.forceEnableActivity: false,
            Key.enableHaptics: true,
            Key.expandNotchOnHover: false,
            Key.hoverDuration: 0.0,
            Key.naturalMovement: false,
            Key.swipeToToggle: true,
            Key.swipeToCycleActivity: true,
            Key.swipeToDismiss: true,
            Key.swipeToSkip: true,
            Key.notchAdjustedWidth: 0.0,
            Key.notchAdjustedHeight: 0.0,

            Key.enableBattery: true,
            Key.batteryDuration: 5.0,
            Key.notifyOnLowPowerMode: true,
            Key.warnOnLowBattery: true,
            Key.lowBatteryThreshold: 10.0,
            Key.hideBatteryLabel: false,
            Key.hideBatteryPercentage: false,
            Key.playSoundOnLowBattery: true,

            Key.enableConnectivity: true,
            Key.connectivityDuration: 5.0,
            Key.connectivityModel: ConnectivityModel.threeDimensional.rawValue,

            Key.enableFocus: true,
            Key.focusDuration: 5.0,
            Key.playSoundOnSleepFocus: false,
            Key.hideLabel: false,

            Key.enableBrightness: false,
            Key.brightnessDuration: 1.5,
            Key.brightnessProgressStyle: HUDProgressStyle.white.rawValue,
            Key.brightnessSpeed: HUDSpeed.fast.rawValue,
            Key.showBrightnessPercentage: false,
            Key.hideBrightnessLabel: false,

            Key.fixBrightnessBug: true,

            Key.enableVolume: false,
            Key.volumeDuration: 1.5,
            Key.volumeProgressStyle: HUDProgressStyle.white.rawValue,
            Key.volumeSpeed: HUDSpeed.fast.rawValue,
            Key.volumeOutputDevice: OutputDevice.device.rawValue,
            Key.showVolumePercentage: false,
            Key.hideVolumeLabel: false,

            Key.enableNowPlaying: true,
            Key.idleDuration: 3.0,
            Key.hideIdleDuration: 10.0,
            Key.hideWhileSourceIsActive: false,
            Key.controlChoice: ControlType.shuffle.rawValue,
            Key.automaticMusicApp: true,
            Key.musicApp: MusicApp.system.rawValue,
            Key.enableQuickPeek: true,
            Key.whenSongChanges: true,
            Key.peekDuration: 2.0,
            Key.disableAlbumArtFlip: false,
            Key.disableWaveform: false,
            Key.hideSongTitleExtras: false,
            Key.songTitleBadge: NowPlayingTitleBadge.explicit.rawValue,
            Key.showVolumeControl: false,
            Key.showRemainingTime: true,
            Key.progressStyle: ColorStyle.mono.rawValue,

            Key.enableCalendar: false,
            Key.timeBeforeEvent: 15.0,
            Key.playSoundOnCalendarEvent: true,
            Key.useCalendarColor: false,
            Key.disableActivityDuringEvents: false,
            Key.useEventIndicators: false,
            Key.alwaysShowMonthView: false,
            Key.playHourlyChime: false,
            Key.enableCalendarQuickPeek: true,
            Key.beforeEventStarts: false,
            Key.whenEventIsStarting: true,
            Key.calendarPeekDuration: 4.0,
            Key.useColoredCalendarIndicator: true,

            Key.enableLockScreen: true,
            Key.playSoundOnLock: false,
            Key.playSoundOnUnlock: true,

            Key.enableClaudeStatus: false,
            Key.claudePrioritize: true,
            Key.claudeShowLabel: true,
            Key.claudeShowUsage: true,
            Key.claudeUsageMetric: ClaudeUsageMetric.planLimit.rawValue,
            Key.claudePeek: true,
            Key.claudeFinishedDuration: 8.0,

            Key.autoCheckForUpdates: true,
        ])
    }

    static func bool(_ key: String) -> Bool { store.bool(forKey: key) }
    static func double(_ key: String) -> Double { store.double(forKey: key) }
    static func string(_ key: String) -> String? { store.string(forKey: key) }
    static func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        store.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
    static func stringSet(_ key: String) -> Set<String> { Set(store.stringArray(forKey: key) ?? []) }
}

// MARK: - Option enums (case names recovered from the original's type metadata)

enum DisplayType: String, CaseIterable, Identifiable {
    case builtInDisplay, mainScreen, allDisplays, specificDisplay
    var id: String { rawValue }
    var title: String {
        switch self {
        case .builtInDisplay: "Built-in display"
        case .mainScreen: "Main display"
        case .allDisplays: "All displays"
        case .specificDisplay: "Selected display"
        }
    }
}

enum ExpandedActivity: String, CaseIterable, Identifiable {
    case none, nowPlaying, calendar, duo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .nowPlaying: "Playing"
        case .calendar: "Calendar"
        case .duo: "Duo"
        }
    }
}

enum HUDProgressStyle: String, CaseIterable, Identifiable {
    case white, accent, stylized
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HUDSpeed: String, CaseIterable, Identifiable {
    case smooth, fast, instant
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var animation: Animation? {
        switch self {
        case .smooth: .spring(response: 0.4, dampingFraction: 0.85)
        case .fast: .spring(response: 0.2, dampingFraction: 0.9)
        case .instant: nil
        }
    }
}

enum OutputDevice: String, CaseIterable, Identifiable {
    case symbol, device
    var id: String { rawValue }
    var title: String { self == .symbol ? "Show symbol" : "Show device" }
}

enum ConnectivityModel: String, CaseIterable, Identifiable {
    case threeDimensional, symbol
    var id: String { rawValue }
    var title: String { self == .symbol ? "Symbols" : "3D models" }
}

enum ControlType: String, CaseIterable, Identifiable {
    case like, shuffle, repeating, copyLink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .like: "Favorite"
        case .shuffle: "Shuffle"
        case .repeating: "Repeat"
        case .copyLink: "Copy"
        }
    }
}

enum MusicApp: String, CaseIterable, Identifiable {
    case music, spotify, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var bundleID: String? {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        case .system: nil
        }
    }
}

enum NowPlayingTitleBadge: String, CaseIterable, Identifiable {
    case none, explicit, format
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ColorStyle: String, CaseIterable, Identifiable {
    case mono, color, gradient
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mono: "Monochrome"
        case .color: "Colored"
        case .gradient: "Gradient"
        }
    }
}
