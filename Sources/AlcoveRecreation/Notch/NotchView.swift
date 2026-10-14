import SwiftUI

/// Root view of the overlay panel: the black notch shape plus whatever it currently hosts.
struct NotchView: View {
    @Bindable var notchController: NotchController
    @AppStorage(Key.contrastOutline) private var contrastOutline = true

    private var size: CGSize { notchController.currentSize }

    private var topCornerRadius: Double {
        notchController.isExpanded ? 16 : 6
    }

    private var bottomCornerRadius: Double {
        if notchController.shapeStyle == .pill {
            return notchController.isExpanded ? 30 : size.height / 2
        }
        if notchController.isExpanded { return 30 }
        return notchController.quickPeek != .none ? 18 : 11
    }

    /// Hover lifts the notch slightly; a press pushes it back.
    private var scale: Double {
        if notchController.isExpanded { return 1 }
        if notchController.isPressed { return 0.97 }
        return notchController.isMouseInside ? 1.045 : 1
    }

    private var shape: NotchShape {
        NotchShape(style: notchController.shapeStyle, topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    /// The pill floats a few points below the screen edge unless it has grown into a panel.
    private var pillInset: Double {
        guard notchController.shapeStyle == .pill else { return 0 }
        return notchController.isExpanded ? 6 : 3
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            shape
                .fill(.black)
                .overlay {
                    if contrastOutline {
                        shape.stroke(.white.opacity(notchController.isExpanded ? 0.12 : 0.06), lineWidth: 1)
                    }
                }
                .overlay(alignment: .top) { content }
                .clipShape(shape)
                .frame(width: size.width, height: size.height - (notchController.isExpanded ? 0 : pillInset * 2))
                .shadow(color: .black.opacity(notchController.isExpanded ? 0.45 : 0), radius: 18, y: 8)
                .scaleEffect(scale, anchor: .top)
                .offset(
                    x: notchController.gestureHorizontalProgress * 6,
                    y: pillInset + max(notchController.gestureVerticalProgress, 0) * 4)
                .contentShape(shape)
                .onTapGesture { notchController.toggle() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !notchController.isPressed, !notchController.isExpanded {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { notchController.isPressed = true }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { notchController.isPressed = false }
                        })
                .contextMenu { NotchContextMenu(notchController: notchController) }
                .opacity(notchController.isVisible || notchController.isHUD(notchController.notification) ? 1 : 0)
        }
        .frame(width: NotchController.panelSize.width, height: NotchController.panelSize.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if notchController.isExpanded {
            NotchExpandedView(notchController: notchController)
                .transition(.blurReplace.combined(with: .scale(0.9, anchor: .top)))
        } else if notchController.notification != .none {
            NotchNotificationsView(notchController: notchController)
                .transition(.blurReplace)
        } else if notchController.liveActivity != .none {
            NotchLiveActivitiesView(notchController: notchController)
                .transition(.blurReplace)
        }
    }
}

/// Right-click menu on the notch; entries follow the original's menu strings.
struct NotchContextMenu: View {
    let notchController: NotchController
    private let media = MediaManager.shared

    var body: some View {
        if media.hasTrack {
            Button(media.isPlaying ? "Pause" : "Play") { media.togglePlayPause() }
            Button("Next") { media.nextTrack() }
            Button("Previous") { media.previousTrack() }
            Button("Show in \(media.sourceAppName)") { media.openSourceApp() }
            if media.shareUrl != nil {
                Button("Copy Link") { media.copyShareLink() }
            }
            Divider()
        }
        if notchController.liveActivity == .isCalendar {
            Button("Dismiss Event") { CalendarManager.shared.dismissCurrentEvent() }
            Divider()
        }
        Button("Settings...") { SettingsController.shared.show() }
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
    }
}

/// Shared two-slot layout for the collapsed notch: content on each side of the camera housing.
struct NotchSideLayout<Left: View, Right: View>: View {
    let notchController: NotchController
    var horizontalPadding: Double = 9
    @ViewBuilder let left: Left
    @ViewBuilder let right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            // Nothing is drawn behind a physical notch; other displays can use the middle.
            Color.clear.frame(width: notchController.hasPhysicalNotch ? notchController.notchWidth - 8 : 0)
            right.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: notchController.notchHeight - (notchController.shapeStyle == .pill ? 6 : 0))
    }
}

// MARK: - Live activities

struct NotchLiveActivitiesView: View {
    let notchController: NotchController
    @AppStorage(Key.disableWaveform) private var disableWaveform = false
    @AppStorage(Key.useCalendarColor) private var useCalendarColor = false
    @AppStorage(Key.hideSongTitleExtras) private var hideSongTitleExtras = false

    private let media = MediaManager.shared
    private let calendar = CalendarManager.shared

    private var iconSize: Double { max(notchController.notchHeight - 14, 14) }

    var body: some View {
        VStack(spacing: 0) {
            NotchSideLayout(notchController: notchController) {
                leading
            } right: {
                trailing
            }
            if notchController.quickPeek != .none {
                peek
                    .frame(height: 30, alignment: .top)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder private var leading: some View {
        switch notchController.liveActivity {
        case .isPlaying:
            ArtworkView(image: media.currentTrack.albumArt, size: iconSize, cornerRadius: iconSize * 0.24)
                .id(media.songChangeToken)
                .transition(.blurReplace)
                .opacity(media.isPlaying ? 1 : 0.6)
        case .isCalendar:
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(useCalendarColor ? (calendar.nextEventActivity?.color ?? .red) : .red)
                    .frame(width: 3, height: iconSize * 0.72)
                Image(systemName: "calendar")
                    .font(.system(size: iconSize * 0.62, weight: .semibold))
                    .foregroundStyle(.white)
            }
        case .isLocked:
            Image(systemName: "lock.fill")
                .font(.system(size: iconSize * 0.66, weight: .semibold))
                .foregroundStyle(.white)
        case .isCoding:
            ClaudeCompactLeading(iconSize: iconSize)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch notchController.liveActivity {
        case .isPlaying:
            if !disableWaveform {
                Waveform(
                    isPlaying: media.isPlaying,
                    colors: media.currentTrack.colors,
                    size: CGSize(width: iconSize * 0.95, height: iconSize * 0.72))
            }
        case .isCalendar:
            Text(calendar.countdownText)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(calendar.timeUntilStart == nil ? .green : .white)
                .contentTransition(.numericText())
        case .isCoding:
            ClaudeCompactTrailing(iconSize: iconSize)
        case .isLocked, .none:
            EmptyView()
        }
    }

    @ViewBuilder private var peek: some View {
        switch notchController.quickPeek {
        case .isPlaying:
            let title = hideSongTitleExtras ? media.currentTrack.title.strippingTitleExtras : media.currentTrack.title
            MarqueeText(
                text: media.currentTrack.artist.isEmpty ? title : "\(title) — \(media.currentTrack.artist)",
                font: .system(size: 12, weight: .medium), color: .white.opacity(0.9))
                .padding(.horizontal, 16)
        case .isCalendar:
            if let event = calendar.nextEventActivity {
                HStack(spacing: 6) {
                    Circle().fill(event.color).frame(width: 6, height: 6)
                    Text(event.title).lineLimit(1)
                    Text(CalendarManager.timeFormatter.string(from: event.startDate)).foregroundStyle(.white.opacity(0.55))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
            }
        case .isCoding:
            if let session = ClaudeManager.shared.current {
                MarqueeText(text: session.peekText, font: .system(size: 12, weight: .medium), color: .white.opacity(0.9))
                    .padding(.horizontal, 16)
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Notifications

struct NotchNotificationsView: View {
    let notchController: NotchController

    @AppStorage(Key.volumeProgressStyle) private var volumeProgressStyle = HUDProgressStyle.white
    @AppStorage(Key.brightnessProgressStyle) private var brightnessProgressStyle = HUDProgressStyle.white
    @AppStorage(Key.volumeSpeed) private var volumeSpeed = HUDSpeed.fast
    @AppStorage(Key.brightnessSpeed) private var brightnessSpeed = HUDSpeed.fast
    @AppStorage(Key.showVolumePercentage) private var showVolumePercentage = false
    @AppStorage(Key.showBrightnessPercentage) private var showBrightnessPercentage = false
    @AppStorage(Key.hideVolumeLabel) private var hideVolumeLabel = false
    @AppStorage(Key.hideBrightnessLabel) private var hideBrightnessLabel = false
    @AppStorage(Key.volumeOutputDevice) private var volumeOutputDevice = OutputDevice.device
    @AppStorage(Key.hideBatteryLabel) private var hideBatteryLabel = false
    @AppStorage(Key.hideBatteryPercentage) private var hideBatteryPercentage = false
    @AppStorage(Key.hideLabel) private var hideFocusLabel = false

    private let volume = VolumeManager.shared
    private let brightness = BrightnessManager.shared
    private let battery = BatteryManager.shared
    private let focus = FocusManager.shared

    private var iconSize: Double { max(notchController.notchHeight - 20, 13) }

    var body: some View {
        NotchSideLayout(notchController: notchController, horizontalPadding: 12) {
            leading
        } right: {
            trailing
        }
    }

    @ViewBuilder private var leading: some View {
        switch notchController.notification {
        case .didChangeVolume:
            HStack(spacing: 6) {
                Image(systemName: volumeOutputDevice == .device && !volume.isMuted ? volume.outputDeviceSymbol : volume.symbolName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: iconSize * 1.5)
                if !hideVolumeLabel, !notchController.hasPhysicalNotch { label("Volume") }
            }
            .foregroundStyle(.white)
        case .didChangeBrightness:
            HStack(spacing: 6) {
                Image(systemName: brightness.symbolName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: iconSize * 1.5)
                if !hideBrightnessLabel, !notchController.hasPhysicalNotch { label("Brightness") }
            }
            .foregroundStyle(.white)
        case .isCharging:
            if !hideBatteryLabel { label("Charging") }
        case .isLowBattery:
            if !hideBatteryLabel { label("Low Battery") }
        case .isLowPowerMode:
            if !hideBatteryLabel { label("Low Power") }
        case .didConnectAirPods:
            Image(systemName: notchController.connectedDevice?.symbol ?? "headphones")
                .font(.system(size: iconSize + 2, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: notchController.connectedDevice?.name)
        case .isFocus:
            Image(systemName: focus.focusMode?.symbol ?? "moon.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(focus.isFocus ? (focus.focusMode?.tintColor ?? .indigo) : .white.opacity(0.5))
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch notchController.notification {
        case .didChangeVolume:
            hudProgress(
                value: Double(volume.isMuted ? 0 : volume.volume), style: volumeProgressStyle,
                showPercentage: showVolumePercentage, animation: volumeSpeed.animation)
        case .didChangeBrightness:
            hudProgress(
                value: Double(brightness.currentBrightness), style: brightnessProgressStyle,
                showPercentage: showBrightnessPercentage, animation: brightnessSpeed.animation)
        case .isCharging:
            batteryStatus(color: Color("ChargingColor", fallback: .green), symbol: "battery.100percent.bolt")
        case .isLowBattery:
            batteryStatus(color: .red, symbol: "battery.25percent")
        case .isLowPowerMode:
            batteryStatus(color: .yellow, symbol: battery.symbolName)
        case .didConnectAirPods:
            Text("Connected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .isFocus:
            if !hideFocusLabel {
                Text(focus.isFocus ? "On" : "Off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(focus.isFocus ? (focus.focusMode?.tintColor ?? .indigo) : .white.opacity(0.5))
            }
        case .none:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
    }

    private func batteryStatus(color: Color, symbol: String) -> some View {
        HStack(spacing: 5) {
            if !hideBatteryPercentage {
                Text("\(Int((battery.batteryLevel * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(color)
    }

    private func hudProgress(value: Double, style: HUDProgressStyle, showPercentage: Bool, animation: Animation?) -> some View {
        HStack(spacing: 6) {
            HUDProgressBar(value: value, style: style)
                .frame(width: showPercentage ? 30 : 54, height: 5.5)
                .animation(animation, value: value)
            if showPercentage {
                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 24, alignment: .trailing)
                    .contentTransition(.numericText(value: value))
                    .animation(animation, value: value)
            }
        }
    }
}

struct HUDProgressBar: View {
    let value: Double
    let style: HUDProgressStyle

    private var fill: AnyShapeStyle {
        switch style {
        case .white: AnyShapeStyle(.white)
        case .accent: AnyShapeStyle(Color.accentColor)
        case .stylized: AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.55), .white], startPoint: .leading, endPoint: .trailing))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(fill)
                    .frame(width: max(proxy.size.height, proxy.size.width * min(max(value, 0), 1)))
                    .opacity(value <= 0.001 ? 0 : 1)
                    .shadow(color: style == .stylized ? .white.opacity(0.6) : .clear, radius: 3)
            }
        }
    }
}

extension Color {
    /// Uses a named asset color when the bundle has one, otherwise the fallback.
    init(_ name: String, fallback: Color) {
        self = NSColor(named: name).map(Color.init(nsColor:)) ?? fallback
    }
}

extension String {
    /// "Song (feat. X) - Remastered 2011" → "Song", for the "Hide media title extras" option.
    var strippingTitleExtras: String {
        var result = self
        for pattern in [#"\s*[\(\[][^\)\]]*[\)\]]"#, #"\s+-\s+.*$"#] {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? self : trimmed
    }
}
