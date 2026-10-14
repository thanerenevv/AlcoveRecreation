import AppKit
import CoreAudio
import Observation

/// Tracks and controls the default output device's volume through CoreAudio.
@Observable
final class VolumeManager {
    static let shared = VolumeManager()

    private(set) var volume: Float = 0
    private(set) var isMuted = false
    private(set) var canControlVolume = true
    private(set) var outputDeviceName = ""
    private(set) var outputDeviceSymbol = "speaker.wave.2.fill"

    /// Fired when the level, mute state or device changes outside of `silently` writes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onOutputDeviceChange: ((String, String) -> Void)?
    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var hasStarted = false

    private static let volumeElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.bindDefaultDevice(notify: true)
        }
        bindDefaultDevice(notify: false)
    }

    // MARK: Device binding

    private func bindDefaultDevice(notify: Bool) {
        if let deviceListener, deviceID != kAudioObjectUnknown {
            for var address in listenedAddresses(for: deviceID) {
                AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, deviceListener)
            }
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        deviceID = id

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh(notify: true)
        }
        deviceListener = listener
        for var address in listenedAddresses(for: id) {
            AudioObjectAddPropertyListenerBlock(id, &address, .main, listener)
        }

        outputDeviceName = Self.stringProperty(id, kAudioObjectPropertyName) ?? ""
        outputDeviceSymbol = Self.symbol(forDeviceNamed: outputDeviceName, transport: Self.transportType(id))
        refresh(notify: false)
        if notify { onOutputDeviceChange?(outputDeviceName, outputDeviceSymbol) }
    }

    private func listenedAddresses(for id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        var result: [AudioObjectPropertyAddress] = []
        for element in Self.volumeElements {
            let address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            var probe = address
            if AudioObjectHasProperty(id, &probe) { result.append(address) }
        }
        result.append(AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain))
        return result
    }

    // MARK: Reading

    private func refresh(notify: Bool) {
        let newVolume = readVolume()
        let newMuted = readMuted()
        let changed = abs(newVolume - volume) > 0.0005 || newMuted != isMuted
        volume = newVolume
        isMuted = newMuted
        if notify && changed { onChange?() }
    }

    private func readVolume() -> Float {
        var values: [Float] = []
        for element in Self.volumeElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr {
                if element == kAudioObjectPropertyElementMain { canControlVolume = true; return value }
                values.append(value)
            }
        }
        canControlVolume = !values.isEmpty
        return values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
    }

    private func readMuted() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        return value != 0
    }

    // MARK: Writing

    func setVolume(_ newValue: Float) {
        let clamped = min(max(newValue, 0), 1)
        for element in Self.volumeElements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value = Float32(clamped)
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
        volume = clamped
        if clamped > 0, isMuted { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(deviceID, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
    }

    /// One media-key step: 1/16 of the range, or 1/64 when fine adjusting.
    func step(up: Bool, fine: Bool) {
        let delta: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0
        setVolume(volume + (up ? delta : -delta))
    }

    var symbolName: String {
        if isMuted || volume <= 0.001 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: Device helpers

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func transportType(_ id: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    static func symbol(forDeviceNamed name: String, transport: UInt32) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods pro") { return "airpods.pro" }
        if lower.contains("airpods") { return "airpods.gen3" }
        if lower.contains("homepod mini") { return "homepod.mini.fill" }
        if lower.contains("homepod") { return "homepod.fill" }
        if lower.contains("beats") { return "beats.headphones" }
        if lower.contains("earpods") { return "earpods" }
        if lower.contains("studio display") || lower.contains("pro display") { return "display" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return lower.contains("headphone") ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        default:
            return "hifispeaker.fill"
        }
    }

    var isWirelessOutput: Bool {
        let transport = Self.transportType(deviceID)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
