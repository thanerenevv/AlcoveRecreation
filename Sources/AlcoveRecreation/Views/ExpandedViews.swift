import SwiftUI

/// Content of the opened notch: Now Playing, Calendar, or both side by side ("Duo").
struct NotchExpandedView: View {
    let notchController: NotchController

    /// A physical notch occupies the top-middle, so content starts below it.
    private var topInset: Double {
        notchController.hasPhysicalNotch ? notchController.notchHeight + 2 : 16
    }

    var body: some View {
        Group {
            if notchController.showsCodingExpanded {
                ClaudeExpandedView()
            } else {
                switch notchController.expandedActivity {
                case .nowPlaying, .none:
                    MediaPlayer(notchController: notchController, compactMode: false)
                case .calendar:
                    CalendarView(compactMode: false)
                case .duo:
                    HStack(spacing: 14) {
                        MediaPlayer(notchController: notchController, compactMode: true)
                        Rectangle().fill(.white.opacity(0.1)).frame(width: 1).padding(.vertical, 6)
                        CalendarView(compactMode: true)
                    }
                }
            }
        }
        .padding(.top, topInset)
        // The notch outline's concave ears take 16pt off each side at the top.
        .padding(.horizontal, notchController.shapeStyle == .notch ? 34 : 22)
        .padding(.bottom, 16)
        .frame(width: notchController.currentSize.width, height: notchController.currentSize.height)
    }
}

// MARK: - Media player

struct MediaPlayer: View {
    let notchController: NotchController
    let compactMode: Bool

    @AppStorage(Key.controlChoice) private var controlChoice = ControlType.shuffle
    @AppStorage(Key.progressStyle) private var progressStyle = ColorStyle.mono
    @AppStorage(Key.showRemainingTime) private var showRemainingTime = true
    @AppStorage(Key.hideSongTitleExtras) private var hideSongTitleExtras = false
    @AppStorage(Key.disableAlbumArtFlip) private var disableAlbumArtFlip = false
    @AppStorage(Key.showVolumeControl) private var showVolumeControl = false

    private let media = MediaManager.shared
    private let volume = VolumeManager.shared
    @LocalState private var copyTrigger = false
    @LocalState private var flip = 0.0

    private var artworkSize: Double { compactMode ? 42 : 50 }

    private var title: String {
        guard media.hasTrack else { return "Not Playing" }
        return hideSongTitleExtras ? media.currentTrack.title.strippingTitleExtras : media.currentTrack.title
    }

    private var fillColors: [Color] {
        let colors = media.currentTrack.colors
        switch progressStyle {
        case .mono: return [.white, .white]
        case .color: return [colors.first ?? .white, colors.first ?? .white]
        case .gradient: return colors.count >= 2 ? Array(colors.prefix(2)) : [colors.first ?? .white, .white]
        }
    }

    var body: some View {
        VStack(spacing: compactMode ? 8 : 9) {
            header
            progress
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ArtworkView(image: media.currentTrack.albumArt, size: artworkSize, cornerRadius: artworkSize * 0.22)
                .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                .shadow(color: (media.currentTrack.colors.first ?? .black).opacity(0.45), radius: 10, y: 4)
                .scaleEffect(media.isPlaying ? 1 : 0.9)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: media.isPlaying)
                .onTapGesture { media.openSourceApp() }
                .onChange(of: media.songChangeToken) {
                    guard !disableAlbumArtFlip else { return }
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { flip += 360 }
                }
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: title, font: .system(size: 13.5, weight: .semibold), color: .white, isCentered: false)
                    .frame(height: 17)
                MarqueeText(
                    text: media.hasTrack ? media.currentTrack.artist : AppInfo.name,
                    font: .system(size: 12.5, weight: .medium), color: .white.opacity(0.55), isCentered: false)
                    .frame(height: 16)
            }
            if !compactMode {
                Waveform(
                    isPlaying: media.isPlaying, colors: media.currentTrack.colors,
                    size: CGSize(width: 20, height: 16))
            }
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let position = media.livePosition
            let duration = max(media.trackDuration, 0.01)
            HStack(spacing: 8) {
                timeLabel(position.asPlaybackTime, alignment: .leading)
                MediaProgressSlider(
                    value: position, range: 0...duration, fillColors: fillColors,
                    onEditingChanged: { media.isDraggingSlider = $0 },
                    onCommit: { media.seek(to: $0) })
                    .disabled(!media.hasTrack)
                timeLabel(
                    showRemainingTime ? "-" + max(duration - position, 0).asPlaybackTime : duration.asPlaybackTime,
                    alignment: .trailing)
                    .onTapGesture { showRemainingTime.toggle() }
            }
        }
    }

    private func timeLabel(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: compactMode ? 32 : 36, alignment: alignment)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if !compactMode {
                choiceControl.frame(maxWidth: .infinity)
            }
            controlButton("backward.fill", size: 17) {
                HapticFeedback.shared.tap(.generic)
                media.previousTrack()
            }
            .frame(maxWidth: .infinity)
            controlButton(media.isPlaying ? "pause.fill" : "play.fill", size: 24) {
                HapticFeedback.shared.tap(.generic)
                media.togglePlayPause()
            }
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity)
            controlButton("forward.fill", size: 17) {
                HapticFeedback.shared.tap(.generic)
                media.nextTrack()
            }
            .frame(maxWidth: .infinity)
            if !compactMode {
                trailingControl.frame(maxWidth: .infinity)
            }
        }
        .frame(height: 30)
        .disabled(!media.hasTrack)
        .opacity(media.hasTrack ? 1 : 0.4)
    }

    @ViewBuilder private var choiceControl: some View {
        switch controlChoice {
        case .shuffle:
            controlButton("shuffle", size: 14, tint: media.isShuffled ? .accentColor : .white.opacity(0.55)) { media.toggleShuffle() }
        case .repeating:
            controlButton("repeat", size: 14, tint: media.isRepeating ? .accentColor : .white.opacity(0.55)) { media.toggleRepeat() }
        case .like:
            controlButton(media.isLoved ? "star.fill" : "star", size: 14, tint: media.isLoved ? .yellow : .white.opacity(0.55)) { media.toggleLoved() }
        case .copyLink:
            controlButton(copyTrigger ? "checkmark" : "link", size: 14, tint: .white.opacity(0.55)) {
                media.copyShareLink()
                copyTrigger = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copyTrigger = false }
            }
            .contentTransition(.symbolEffect(.replace))
        }
    }

    @ViewBuilder private var trailingControl: some View {
        if showVolumeControl {
            controlButton(volume.symbolName, size: 14, tint: .white.opacity(0.55)) {
                volume.setMuted(!volume.isMuted)
            }
            .contentTransition(.symbolEffect(.replace))
        } else {
            controlButton(volume.outputDeviceSymbol, size: 14, tint: .white.opacity(0.55)) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func controlButton(_ symbol: String, size: Double, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScaleFadeButtonStyle())
    }
}

// MARK: - Calendar

struct CalendarView: View {
    let compactMode: Bool

    @AppStorage(Key.useEventIndicators) private var useEventIndicators = false

    private let calendar = CalendarManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if calendar.isAuthorized {
                weekStrip
                eventList
            } else {
                permission
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            if !compactMode {
                VStack(alignment: .leading, spacing: 0) {
                    Text(calendar.selectedMonthName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(calendar.selectedDayNumber)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .frame(width: 74, alignment: .leading)
            }
            ForEach(calendar.weekDays) { day in
                let selected = Calendar.current.isDate(day.date, inSameDayAs: calendar.selectedDate)
                VStack(spacing: 3) {
                    Text(day.symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(day.isWeekend ? 0.3 : 0.45))
                    Text("\(day.dayNumber)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? .black : (day.isToday ? .red : .white.opacity(day.isWeekend ? 0.5 : 0.9)))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(selected ? (day.isToday ? Color.red : .white) : .clear))
                    HStack(spacing: 2) {
                        ForEach(Array(day.eventColors.enumerated()), id: \.offset) { _, color in
                            Circle().fill(color).frame(width: 3, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .opacity(useEventIndicators ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticFeedback.shared.tap(.alignment)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { calendar.selectedDate = day.date }
                }
            }
        }
    }

    @ViewBuilder private var eventList: some View {
        if calendar.events.isEmpty {
            Text(calendar.emptyStateText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(calendar.events) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CalendarManager.EventModel) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(event.isAllDay
                     ? "All-day"
                     : "\(CalendarManager.timeFormatter.string(from: event.startDate)) – \(CalendarManager.timeFormatter.string(from: event.endDate))")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green))
                }
                .buttonStyle(ScaleFadeButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(event.color.opacity(0.16)))
        .opacity(event.endDate < Date() ? 0.5 : 1)
    }

    private var permission: some View {
        VStack(spacing: 8) {
            Text("\(AppInfo.name) needs your permission to display your upcoming calendar events.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Grant Permission") { calendar.requestAccess() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
