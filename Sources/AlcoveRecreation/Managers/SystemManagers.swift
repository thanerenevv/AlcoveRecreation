import AppKit
import os
import Observation
import SwiftUI

// MARK: - Focus

/// Focus (Do Not Disturb) state.
///
/// The original follows Focus changes by streaming unified-log messages through the private
/// LoggingSupport framework. This recreation reads the Focus assertion store instead, which
/// needs no private API but is only readable when the app has Full Disk Access; without it
/// the Focus notification simply stays quiet.
@Observable
final class FocusManager {
    static let shared = FocusManager()

    struct FocusMode: Equatable {
        let identifier: String
        let name: String
        let symbol: String
        let tintColor: Color
    }

    private(set) var isFocus = false
    private(set) var focusMode: FocusMode?
    private(set) var isReadable = false

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastIdentifier: String?
    @ObservationIgnored private var hasLoadedOnce = false

    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")

    /// Identifiers recovered from the original's string table, with matching labels.
    private static let builtIn: [String: (name: String, symbol: String, color: Color)] = [
        "com.apple.donotdisturb.mode.default": ("Do Not Disturb", "moon.fill", .indigo),
        "com.apple.donotdisturb.mode.driving": ("Driving", "car.fill", .indigo),
        "com.apple.donotdisturb.mode.workout": ("Fitness", "figure.run", .green),
        "com.apple.focus.gaming": ("Gaming", "gamecontroller.fill", .blue),
        "com.apple.focus.mindfulness": ("Mindfulness", "brain.head.profile", .mint),
        "com.apple.focus.personal-time": ("Personal", "person.fill", .purple),
        "com.apple.focus.reading": ("Reading", "book.fill", .orange),
        "com.apple.focus.reduce-interruptions": ("Reduce Interruptions", "apple.intelligence", .indigo),
        "com.apple.focus.work": ("Work", "person.crop.rectangle.stack.fill", .teal),
        "com.apple.sleep.sleep-mode": ("Sleep", "bed.double.fill", .cyan),
    ]

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let url = Self.directory.appendingPathComponent("Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            isReadable = false
            return
        }
        isReadable = true
        var identifier: String?
        if let stores = root["data"] as? [[String: Any]] {
            for store in stores {
                guard let records = store["storeAssertionRecords"] as? [[String: Any]] else { continue }
                for record in records {
                    if let details = record["assertionDetails"] as? [String: Any],
                       let mode = details["assertionDetailsModeIdentifier"] as? String {
                        identifier = mode
                    }
                }
            }
        }
        defer { hasLoadedOnce = true }
        guard identifier != lastIdentifier || !hasLoadedOnce else { return }
        lastIdentifier = identifier
        isFocus = identifier != nil
        focusMode = identifier.map(Self.mode(for:)) ?? focusMode
        if hasLoadedOnce, Prefs.bool(Key.enableFocus) {
            if identifier == "com.apple.sleep.sleep-mode", Prefs.bool(Key.playSoundOnSleepFocus) {
                SoundManager.shared.play(.sleep)
            }
            onChange?()
        }
    }

    private static func mode(for identifier: String) -> FocusMode {
        if let known = builtIn[identifier] {
            return FocusMode(identifier: identifier, name: known.name, symbol: known.symbol, tintColor: known.color)
        }
        return FocusMode(identifier: identifier, name: "Focus", symbol: "moon.fill", tintColor: .indigo)
    }
}

// MARK: - Lock

/// Screen lock state from the loginwindow distributed notifications the original also observes.
@Observable
final class LockManager {
    static let shared = LockManager()

    private(set) var isLocked = false
    @ObservationIgnored var onChange: (() -> Void)?

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.set(locked: true)
        }
        center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.set(locked: false)
        }
    }

    private func set(locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        guard Prefs.bool(Key.enableLockScreen) else { return }
        if locked, Prefs.bool(Key.playSoundOnLock) { SoundManager.shared.play(.lock) }
        if !locked, Prefs.bool(Key.playSoundOnUnlock) { SoundManager.shared.play(.unlock) }
        onChange?()
    }
}

// MARK: - Screen

/// Tracks what is in front of the user: which displays are showing something fullscreen,
/// whether the frontmost app is a game, and which app is frontmost.
@Observable
final class ScreenManager {
    static let shared = ScreenManager()

    private(set) var fullscreenDisplayIDs: Set<CGDirectDisplayID> = []
    private(set) var isGaming = false
    private(set) var frontmostBundleID: String?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    @ObservationIgnored private var mainConnectionID: MainConnectionID?
    @ObservationIgnored private var copyManagedDisplaySpaces: CopyManagedDisplaySpaces?

    /// Space type the window server reports for a fullscreen (or Split View) Space.
    private static let fullscreenSpaceType = 4
    private static let gameBundleIdentifiers: Set<String> = ["com.roblox.RobloxPlayer", "com.mojang.minecraftlauncher"]
    private static let gamePathFragments = ["/steamapps/", "/Epic Games/", "/GOG Games/", "/CrossOver/Bottles/", "/Wine", "/Whisky/"]

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return }
        if let symbol = dlsym(handle, "CGSMainConnectionID") {
            mainConnectionID = unsafeBitCast(symbol, to: MainConnectionID.self)
        }
        if let symbol = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
            copyManagedDisplaySpaces = unsafeBitCast(symbol, to: CopyManagedDisplaySpaces.self)
        }
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Once right away for the frontmost app, once more after the Space animation settles.
                self?.evaluate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.evaluate() }
            }
        }
        // Borderless fullscreen windows appear without any notification, so keep a slow poll too.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    private func evaluate() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isOwnApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        let fullscreen = fullscreenSpaceDisplays().union(isOwnApp ? [] : displaysCovered(by: frontmost))
        let gaming = frontmost.map(Self.isGame) ?? false
        let bundleID = frontmost?.bundleIdentifier

        guard fullscreen != fullscreenDisplayIDs || gaming != isGaming || bundleID != frontmostBundleID else { return }
        fullscreenDisplayIDs = fullscreen
        isGaming = gaming
        frontmostBundleID = bundleID
        onChange?()
    }

    /// Displays whose current Space is a native fullscreen Space.
    private func fullscreenSpaceDisplays() -> Set<CGDirectDisplayID> {
        guard let mainConnectionID, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnectionID())?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result: Set<CGDirectDisplayID> = []
        for display in displays {
            // Fullscreen Spaces also carry a tile layout (they can hold a Split View pair).
            guard let current = display["Current Space"] as? [String: Any],
                  current["type"] as? Int == Self.fullscreenSpaceType || current["TileLayoutManager"] != nil,
                  let identifier = display["Display Identifier"] as? String else { continue }
            // With "Displays have separate Spaces" off there is a single entry named "Main".
            let screens = identifier == "Main" ? NSScreen.screens : NSScreen.screens.filter { $0.displayUUID == identifier }
            result.formUnion(screens.compactMap(\.displayID))
        }
        return result
    }

    /// Displays that a window of the frontmost app covers edge to edge, menu bar included:
    /// how games and players that skip native fullscreen take over the screen.
    private func displaysCovered(by app: NSRunningApplication?) -> Set<CGDirectDisplayID> {
        guard let app, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var result: Set<CGDirectDisplayID> = []
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int ?? -1) >= 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                if bounds.insetBy(dx: -1, dy: -1).contains(CGDisplayBounds(id)) { result.insert(id) }
            }
        }
        return result
    }

    private static func isGame(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, gameBundleIdentifiers.contains(id) { return true }
        let paths = [app.bundleURL?.path, app.executableURL?.path].compactMap { $0 }
        if paths.contains(where: { path in gamePathFragments.contains(where: path.contains) }) { return true }
        guard let url = app.bundleURL,
              let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String else { return false }
        return category.contains("games")
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var displayUUID: String {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var isBuiltIn: Bool { displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }

    /// Same test the original performs: a top safe-area inset plus two non-empty auxiliary areas.
    var hasNotch: Bool {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return false }
        return !left.isEmpty && !right.isEmpty
    }

    var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }
}

// MARK: - Media keys

/// Intercepts the volume and brightness keys so the notch HUD replaces the system one.
///
/// Swallowing the key event is what keeps macOS from drawing its own HUD, and an active event
/// tap needs Accessibility permission, exactly like the original. Without it the keys keep
/// their stock behaviour and the notch HUD only mirrors the resulting changes.
///
/// The tap matches the original's: session level, head-inserted, listening for system-defined
/// events (the media keys) plus key down/up (keyboards that send brightness as plain keys).
final class MediaKeyManager {
    static let shared = MediaKeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    private static let systemDefinedType = CGEventType(rawValue: 14)!
    private static let auxControlSubtype: Int16 = 8
    private enum AuxKey { static let soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7 }
    /// Plain key codes that mean brightness. The original also takes F15/F14 (113/107), but those
    /// are Pause and Scroll Lock on PC keyboards and are sent by keep-awake utilities and KVM
    /// switches, which can dim the screen on their own. "Fix Brightness Bug" drops them.
    private static var brightnessUpKeyCodes: Set<Int64> { Prefs.bool(Key.fixBrightnessBug) ? [144] : [144, 113] }
    private static var brightnessDownKeyCodes: Set<Int64> { Prefs.bool(Key.fixBrightnessBug) ? [145] : [145, 107] }
    private let log = Logger(subsystem: "local.alcove-recreation", category: "MediaKeys")

    /// True while the keys are being intercepted, i.e. the system HUD is suppressed.
    private(set) var isIntercepting = false

    func start() {
        installIfPossible()
        // Pick the permission up as soon as it is granted, and drop the tap if it is revoked.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted, self.eventTap == nil { self.installIfPossible() }
            if !trusted, self.eventTap != nil { self.stop() }
        }
    }

    static func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installIfPossible() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventMask(Self.systemDefinedType.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue))
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<MediaKeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return manager.handle(event, type: type) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("MediaKeyManager: event tap could not be created")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isIntercepting = true
        NSLog("MediaKeyManager: intercepting media keys")
    }

    private func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isIntercepting = false
        NSLog("MediaKeyManager: stopped intercepting (Accessibility permission missing)")
    }

    /// Returns true when the event was consumed, which hides the system HUD for that press.
    private func handle(_ cgEvent: CGEvent, type: CGEventType) -> Bool {
        // Only act on keys pressed on a real keyboard. Events posted by other software carry
        // that process's ID; they are left for the system so this app never ends up in a loop
        // with brightness tools or keep-awake utilities.
        // Part of "Fix Brightness Bug"; with it off, posted events are handled like real ones.
        let sourcePID = pid_t(truncatingIfNeeded: cgEvent.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID != 0, Prefs.bool(Key.fixBrightnessBug) {
            if isMediaKey(cgEvent, type: type) {
                let name = NSRunningApplication(processIdentifier: sourcePID)?.localizedName ?? "unknown"
                log.info("Ignored media key posted by \(name, privacy: .public) (pid \(sourcePID, privacy: .public))")
            }
            return false
        }
        if type == .keyDown || type == .keyUp {
            let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
            let up = Self.brightnessUpKeyCodes.contains(keyCode)
            guard up || Self.brightnessDownKeyCodes.contains(keyCode) else { return false }
            // Command combinations belong to the system (e.g. display mirroring shortcuts).
            guard !cgEvent.flags.contains(.maskCommand) else { return false }
            return adjustBrightness(up: up, isDown: type == .keyDown, flags: cgEvent.flags)
        }

        guard type == Self.systemDefinedType, let event = NSEvent(cgEvent: cgEvent),
              event.subtype.rawValue == Self.auxControlSubtype else { return false }
        let keyCode = Int((event.data1 & 0xFFFF0000) >> 16)
        let isDown = ((event.data1 & 0xFF00) >> 8) == 0xA

        switch keyCode {
        case AuxKey.soundUp, AuxKey.soundDown, AuxKey.mute:
            guard Prefs.bool(Key.enableVolume), VolumeManager.shared.canControlVolume else { return false }
            if isDown {
                // Option+Shift is the system's quarter-step modifier.
                let fine = cgEvent.flags.contains(.maskAlternate) && cgEvent.flags.contains(.maskShift)
                DispatchQueue.main.async {
                    let volume = VolumeManager.shared
                    if keyCode == AuxKey.mute {
                        volume.setMuted(!volume.isMuted)
                    } else {
                        volume.step(up: keyCode == AuxKey.soundUp, fine: fine)
                    }
                    volume.onChange?()
                }
            }
            return true
        case AuxKey.brightnessUp, AuxKey.brightnessDown:
            return adjustBrightness(up: keyCode == AuxKey.brightnessUp, isDown: isDown, flags: cgEvent.flags)
        default:
            return false
        }
    }

    private func isMediaKey(_ cgEvent: CGEvent, type: CGEventType) -> Bool {
        if type == .keyDown || type == .keyUp {
            let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
            return Self.brightnessUpKeyCodes.contains(keyCode) || Self.brightnessDownKeyCodes.contains(keyCode)
        }
        guard let event = NSEvent(cgEvent: cgEvent), event.subtype.rawValue == Self.auxControlSubtype else { return false }
        return [AuxKey.soundUp, AuxKey.soundDown, AuxKey.mute, AuxKey.brightnessUp, AuxKey.brightnessDown]
            .contains(Int((event.data1 & 0xFFFF0000) >> 16))
    }

    private func adjustBrightness(up: Bool, isDown: Bool, flags: CGEventFlags) -> Bool {
        guard Prefs.bool(Key.enableBrightness), BrightnessManager.shared.isAvailable else { return false }
        if isDown {
            log.info("Brightness \(up ? "up" : "down", privacy: .public) key handled")
            let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
            DispatchQueue.main.async {
                BrightnessManager.shared.step(up: up, fine: fine)
                BrightnessManager.shared.onChange?()
            }
        }
        return true
    }
}
