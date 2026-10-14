import AppKit
import Observation
import SwiftUI

/// Now Playing state for Spotify and Music.
///
/// The original reads system-wide Now Playing from the private MediaRemote framework through
/// an XPC helper, and talks to Spotify/Music over ScriptingBridge for the extra controls
/// (favorite, shuffle, repeat, share link). MediaRemote is closed to ordinary processes on
/// current macOS, so this recreation drives everything through the two scriptable players:
/// distributed notifications for change events, AppleScript for state and control.
@Observable
final class MediaManager {
    static let shared = MediaManager()

    struct Track: Equatable {
        var title = ""
        var artist = ""
        var album = ""
        var albumArt: NSImage?
        var colors: [Color] = []

        static func == (lhs: Track, rhs: Track) -> Bool {
            lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
        }
    }

    private(set) var currentTrack = Track()
    private(set) var isPlaying = false
    private(set) var isHidden = true
    private(set) var isShuffled = false
    private(set) var isRepeating = false
    private(set) var isLoved = false
    private(set) var hasShuffle = true
    private(set) var trackDuration: Double = 0
    private(set) var appBundleId: String?
    private(set) var shareUrl: String?
    private(set) var songChangeToken = 0
    private(set) var hasRecentlyPaused = false
    private(set) var appleEventsAllowed = true
    var isDraggingSlider = false

    /// Position at `positionTimestamp`; the live position is interpolated while playing.
    private(set) var seekerPosition: Double = 0
    @ObservationIgnored private var positionTimestamp = Date()

    @ObservationIgnored var onTrackChange: (() -> Void)?
    @ObservationIgnored var onPlaybackChange: (() -> Void)?

    @ObservationIgnored private let scriptQueue = DispatchQueue(label: "media.applescript", qos: .userInitiated)
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var hideIdleWork: DispatchWorkItem?
    @ObservationIgnored private var pauseWork: DispatchWorkItem?
    @ObservationIgnored private var artworkGeneration = 0
    @ObservationIgnored private var artworkIdentity: String?
    @ObservationIgnored private var pollingSources: Set<String> = []

    private static let spotifyID = "com.spotify.client"
    private static let musicID = "com.apple.Music"
    private static let separator = "\u{1F}"

    var hasTrack: Bool { !currentTrack.title.isEmpty }

    var livePosition: Double {
        guard isPlaying else { return seekerPosition }
        let elapsed = Date().timeIntervalSince(positionTimestamp)
        return min(seekerPosition + elapsed, trackDuration > 0 ? trackDuration : .greatestFiniteMagnitude)
    }

    var sourceAppName: String {
        switch appBundleId {
        case Self.spotifyID: "Spotify"
        case Self.musicID: "Music"
        default: "Music"
        }
    }

    // MARK: Lifecycle

    func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.refresh(from: Self.spotifyID)
        }
        center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            self?.refresh(from: Self.musicID)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let id = app?.bundleIdentifier, id == self.appBundleId { self.clear() }
        }
        reload()
    }

    /// Re-reads every running player, e.g. right after Automation permission is granted.
    func reload() {
        for id in preferredSources() where isRunning(id) { refresh(from: id) }
    }

    /// While something is on screen that shows the scrubber, poll the player position.
    func setPolling(_ enabled: Bool, source: String) {
        if enabled { pollingSources.insert(source) } else { pollingSources.remove(source) }
        if pollingSources.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, let id = self.appBundleId, self.isPlaying else { return }
                self.refresh(from: id)
            }
        }
    }

    private func preferredSources() -> [String] {
        if !Prefs.bool(Key.automaticMusicApp), let id = Prefs.value(Key.musicApp, MusicApp.system).bundleID {
            return [id]
        }
        return [Self.spotifyID, Self.musicID]
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: State refresh

    private func refresh(from bundleID: String) {
        guard Prefs.bool(Key.enableNowPlaying), preferredSources().contains(bundleID), isRunning(bundleID) else { return }
        let script = bundleID == Self.spotifyID ? Self.spotifyStateScript : Self.musicStateScript
        runScript(script) { [weak self] result in
            guard let self, let result else { return }
            self.apply(result.split(separator: Self.separator, omittingEmptySubsequences: false).map(String.init), from: bundleID)
        }
    }

    private func apply(_ fields: [String], from bundleID: String) {
        guard fields.count >= 9, fields[0] != "stopped" else {
            if bundleID == appBundleId { clear() }
            return
        }
        let playing = fields[5] == "playing"
        // A paused player never steals the notch from one that is playing.
        if bundleID != appBundleId, isPlaying, !playing { return }

        var duration = Double(fields[3].replacingOccurrences(of: ",", with: ".")) ?? 0
        if bundleID == Self.spotifyID { duration /= 1000 }
        let position = Double(fields[4].replacingOccurrences(of: ",", with: ".")) ?? 0
        let track = Track(title: fields[0], artist: fields[1], album: fields[2])
        let trackChanged = track != currentTrack || bundleID != appBundleId
        let playbackChanged = playing != isPlaying

        appBundleId = bundleID
        trackDuration = duration
        if !isDraggingSlider {
            seekerPosition = position
            positionTimestamp = Date()
        }
        isShuffled = fields[6] == "true"
        isRepeating = fields[7] == "true" || fields[7] == "one" || fields[7] == "all"
        if bundleID == Self.spotifyID {
            shareUrl = Self.shareLink(fromSpotifyURI: fields[8])
            isLoved = false
        } else {
            isLoved = fields[8] == "true"
            shareUrl = nil
        }

        if trackChanged {
            var next = track
            // Keep the old artwork up until the new one arrives so the flip has both sides.
            next.albumArt = currentTrack.albumArt
            next.colors = currentTrack.colors
            currentTrack = next
            songChangeToken += 1
            loadArtwork(for: track, bundleID: bundleID, spotifyArtworkURL: fields.count > 9 ? fields[9] : nil)
        }
        if playbackChanged {
            isPlaying = playing
            if !playing {
                hasRecentlyPaused = true
                pauseWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.hasRecentlyPaused = false }
                pauseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Prefs.double(Key.idleDuration), execute: work)
            }
        }
        scheduleIdleHide()
        if trackChanged { onTrackChange?() }
        if playbackChanged { onPlaybackChange?() }
    }

    /// After `hideIdleDuration` seconds of paused playback the activity leaves the notch.
    private func scheduleIdleHide() {
        hideIdleWork?.cancel()
        if isPlaying {
            isHidden = false
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.isHidden = true
            self.onPlaybackChange?()
        }
        hideIdleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(Prefs.double(Key.hideIdleDuration), 1), execute: work)
        isHidden = false
    }

    private func clear() {
        currentTrack = Track()
        isPlaying = false
        isHidden = true
        appBundleId = nil
        trackDuration = 0
        seekerPosition = 0
        onPlaybackChange?()
    }

    // MARK: Artwork

    private func loadArtwork(for track: Track, bundleID: String, spotifyArtworkURL: String?) {
        artworkGeneration += 1
        let generation = artworkGeneration
        let identity = "\(bundleID)|\(track.title)|\(track.artist)|\(track.album)"
        artworkIdentity = identity

        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkGeneration == generation else { return }
                self.currentTrack.albumArt = image
                self.currentTrack.colors = image.map(ArtworkColors.extract) ?? []
            }
        }

        if bundleID == Self.spotifyID, let string = spotifyArtworkURL, let url = URL(string: string) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                finish(data.flatMap(NSImage.init(data:)))
            }.resume()
        } else {
            scriptQueue.async {
                var error: NSDictionary?
                let descriptor = NSAppleScript(source: Self.musicArtworkScript)?.executeAndReturnError(&error)
                finish(descriptor.flatMap { NSImage(data: $0.data) })
            }
        }
    }

    // MARK: Controls

    func togglePlayPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command(appBundleId == Self.musicID ? "back track" : "previous track") }

    func seek(to position: Double) {
        seekerPosition = position
        positionTimestamp = Date()
        command("set player position to \(String(format: "%.2f", position))", refreshAfter: false)
    }

    func toggleShuffle() {
        guard hasShuffle else { return }
        isShuffled.toggle()
        if appBundleId == Self.musicID {
            command("set shuffle enabled to \(isShuffled)")
        } else {
            command("set shuffling to \(isShuffled)")
        }
    }

    func toggleRepeat() {
        isRepeating.toggle()
        if appBundleId == Self.musicID {
            command("set song repeat to \(isRepeating ? "all" : "off")")
        } else {
            command("set repeating to \(isRepeating)")
        }
    }

    func toggleLoved() {
        guard appBundleId == Self.musicID else { return }
        isLoved.toggle()
        command("set favorited of current track to \(isLoved)")
    }

    func copyShareLink() {
        guard let shareUrl else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareUrl, forType: .string)
    }

    func openSourceApp() {
        guard let id = appBundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func command(_ body: String, refreshAfter: Bool = true) {
        guard let id = appBundleId, isRunning(id) else { return }
        let name = id == Self.spotifyID ? "Spotify" : "Music"
        runScript("tell application \"\(name)\" to \(body)") { [weak self] _ in
            guard refreshAfter else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.refresh(from: id) }
        }
    }

    // MARK: AppleScript

    private func runScript(_ source: String, completion: @escaping (String?) -> Void) {
        scriptQueue.async { [weak self] in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let denied = (error?[NSAppleScript.errorNumber] as? Int) == -1743
            DispatchQueue.main.async {
                if denied { self?.appleEventsAllowed = false } else if error == nil { self?.appleEventsAllowed = true }
                completion(error == nil ? result?.stringValue : nil)
            }
        }
    }

    private static func shareLink(fromSpotifyURI uri: String) -> String? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return "https://open.spotify.com/\(parts[1])/\(parts[2])"
    }

    private static let spotifyStateScript = """
    tell application "Spotify"
        if player state is stopped then return "stopped"
        set s to (character id 31)
        set t to current track
        return (name of t) & s & (artist of t) & s & (album of t) & s & (duration of t) & s & (player position) & s & (player state as string) & s & (shuffling) & s & (repeating) & s & (spotify url of t) & s & (artwork url of t)
    end tell
    """

    private static let musicStateScript = """
    tell application "Music"
        if player state is stopped then return "stopped"
        set s to (character id 31)
        set t to current track
        set fav to false
        try
            set fav to favorited of t
        end try
        return (name of t) & s & (artist of t) & s & (album of t) & s & (duration of t) & s & (player position) & s & (player state as string) & s & (shuffle enabled) & s & (song repeat as string) & s & fav
    end tell
    """

    private static let musicArtworkScript = """
    tell application "Music"
        return raw data of artwork 1 of current track
    end tell
    """
}

/// Pulls a few vivid colors out of the artwork for the waveform and progress gradient.
enum ArtworkColors {
    static func extract(from image: NSImage) -> [Color] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Bucket by hue, weighting saturated mid-bright pixels so the result is not muddy.
        var buckets = [(weight: Double, h: Double, s: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let color = NSColor(
                red: CGFloat(pixels[index]) / 255, green: CGFloat(pixels[index + 1]) / 255,
                blue: CGFloat(pixels[index + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let weight = Double(s) * Double(b) + 0.02
            let slot = min(Int(h * 12), 11)
            buckets[slot].weight += weight
            buckets[slot].h += Double(h) * weight
            buckets[slot].s += Double(s) * weight
            buckets[slot].b += Double(b) * weight
        }
        return buckets.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }.prefix(2).map { bucket in
            Color(
                hue: bucket.h / bucket.weight,
                saturation: min(max(bucket.s / bucket.weight, 0.35), 0.9),
                brightness: min(max(bucket.b / bucket.weight, 0.75), 1))
        }
    }
}
