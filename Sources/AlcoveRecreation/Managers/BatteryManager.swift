import AppKit
import IOKit.ps
import Observation

/// Watches power-source changes through IOKit and low power mode through ProcessInfo.
@Observable
final class BatteryManager {
    static let shared = BatteryManager()

    enum Event { case charging, lowBattery, lowPowerMode }

    private(set) var batteryLevel: Double = 1
    private(set) var isOnBattery = false
    private(set) var isCharging = false
    private(set) var hasBattery = false
    private(set) var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var remainingMinutes: Int?

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored private var hasPassedThreshold = false
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var powerStateObserver: NSObjectProtocol?

    func start() {
        read(initial: true)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue().read(initial: false)
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            let wasEnabled = self.isLowPowerModeEnabled
            self.isLowPowerModeEnabled = enabled
            if enabled, !wasEnabled, Prefs.bool(Key.enableBattery), Prefs.bool(Key.notifyOnLowPowerMode) {
                self.onEvent?(.lowPowerMode)
            }
        }
    }

    private func read(initial: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            let current = info[kIOPSCurrentCapacityKey] as? Double ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Double ?? 100
            let level = max > 0 ? current / max : 0
            let onBattery = info[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            let wasOnBattery = isOnBattery
            batteryLevel = level
            isOnBattery = onBattery
            isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            if let minutes = info[onBattery ? kIOPSTimeToEmptyKey : kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                remainingMinutes = minutes
            } else {
                remainingMinutes = nil
            }
            guard !initial, Prefs.bool(Key.enableBattery) else {
                hasPassedThreshold = onBattery && level * 100 <= Prefs.double(Key.lowBatteryThreshold)
                continue
            }
            if wasOnBattery && !onBattery {
                hasPassedThreshold = false
                onEvent?(.charging)
            }
            let threshold = Prefs.double(Key.lowBatteryThreshold)
            if onBattery, level * 100 <= threshold, !hasPassedThreshold {
                hasPassedThreshold = true
                if Prefs.bool(Key.warnOnLowBattery) {
                    if Prefs.bool(Key.playSoundOnLowBattery) { SoundManager.shared.play(.lowBattery) }
                    onEvent?(.lowBattery)
                }
            } else if level * 100 > threshold {
                hasPassedThreshold = false
            }
        }
    }

    var symbolName: String {
        if isCharging || !isOnBattery { return "battery.100percent.bolt" }
        switch batteryLevel {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
