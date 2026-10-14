import AppKit
import Observation

/// Reads and writes display brightness through the private DisplayServices framework,
/// the same framework the original links against.
@Observable
final class BrightnessManager {
    static let shared = BrightnessManager()

    private(set) var currentBrightness: Float = 0
    private(set) var isAvailable = false

    /// Called after a brightness key press was applied, to show the HUD.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Value written by the last key press. Rapid presses step from this rather than from a
    /// fresh read, which can still report the old level while the panel is ramping.
    @ObservationIgnored private var localTarget: Float?
    @ObservationIgnored private var localTargetExpiry = Date.distantPast
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var suppressUntil = Date.distantPast

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    @ObservationIgnored private var getBrightness: GetBrightness?
    @ObservationIgnored private var setBrightness: SetBrightness?
    @ObservationIgnored private var canChange: CanChange?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return }
        if let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightness = unsafeBitCast(symbol, to: GetBrightness.self)
        }
        if let symbol = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightness = unsafeBitCast(symbol, to: SetBrightness.self)
        }
        if let symbol = dlsym(handle, "DisplayServicesCanChangeBrightness") {
            canChange = unsafeBitCast(symbol, to: CanChange.self)
        }
    }

    /// The display whose brightness the keys control: the built-in panel when present.
    private var targetDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        if let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) { return builtIn }
        return displays.first(where: { canChange?($0) ?? false })
    }

    /// With "Fix Brightness Bug" on (the default), brightness is read only when a key is
    /// pressed. With it off, the older behaviour returns: a poll four times a second that shows
    /// the HUD for every change, including automatic ambient-light adjustments, which on some
    /// Macs popped the HUD every few seconds.
    func start() {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, !Prefs.bool(Key.fixBrightnessBug) else { return }
            let previous = self.currentBrightness
            guard let value = self.refresh(), abs(value - previous) > 0.004, Date() > self.suppressUntil else { return }
            self.onChange?()
        }
    }

    @discardableResult
    private func refresh() -> Float? {
        guard let display = targetDisplay, let getBrightness else { isAvailable = false; return nil }
        var value: Float = 0
        guard getBrightness(display, &value) == 0 else { isAvailable = false; return nil }
        isAvailable = true
        currentBrightness = value
        return value
    }

    func set(_ value: Float) {
        guard let display = targetDisplay, let setBrightness else { return }
        let clamped = min(max(value, 0), 1)
        _ = setBrightness(display, clamped)
        currentBrightness = clamped
        localTarget = clamped
        localTargetExpiry = Date().addingTimeInterval(1)
        // Keeps the legacy poll from announcing our own write a second time.
        suppressUntil = Date().addingTimeInterval(0.4)
    }

    func step(up: Bool, fine: Bool) {
        let delta: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        let base = (Date() < localTargetExpiry ? localTarget : nil) ?? refresh() ?? currentBrightness
        set(base + (up ? delta : -delta))
    }

    var symbolName: String { currentBrightness < 0.5 ? "sun.min.fill" : "sun.max.fill" }
}
