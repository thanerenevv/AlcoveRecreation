import AppKit

/// Plays short feedback sounds. The original ships its own .caf files; this recreation
/// maps each cue onto a built-in system sound instead of redistributing those assets.
final class SoundManager {
    static let shared = SoundManager()

    enum Cue: String {
        case lowBattery = "Sosumi"
        case lowPower = "Tink"
        case event = "Glass"
        case chime = "Blow"
        case lock = "Bottle"
        case unlock = "Pop"
        case sleep = "Submarine"
        case volume = "Funk"
    }

    private var cache: [Cue: NSSound] = [:]
    private let defaultVolume: Float = 0.6

    func play(_ cue: Cue) {
        let sound = cache[cue] ?? NSSound(named: cue.rawValue)
        guard let sound else { return }
        cache[cue] = sound
        sound.stop()
        sound.volume = defaultVolume
        sound.play()
    }
}

/// Trackpad haptics with a short debounce, mirroring the original's HapticFeedback type.
final class HapticFeedback {
    static let shared = HapticFeedback()
    private var hasRecentlyTriggered = false

    func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
        guard Prefs.bool(Key.enableHaptics), !hasRecentlyTriggered else { return }
        hasRecentlyTriggered = true
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.hasRecentlyTriggered = false
        }
    }
}
