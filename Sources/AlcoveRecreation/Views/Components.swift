import SwiftUI

struct ArtworkView: View {
    let image: NSImage?
    let size: Double
    let cornerRadius: Double

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Animated bars beside the artwork. The original can drive these from a live audio tap;
/// this one is the simulated variant: seeded pseudo-random levels that ease between ticks
/// and settle into a flat line while paused.
struct Waveform: View {
    let isPlaying: Bool
    let colors: [Color]
    let size: CGSize
    var amplitudeCount = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: size.width * 0.09) {
                ForEach(0..<amplitudeCount, id: \.self) { index in
                    Capsule()
                        .fill(fill)
                        .frame(width: barWidth, height: barHeight(index: index, time: time))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .animation(.easeInOut(duration: 0.3), value: isPlaying)
    }

    private var barWidth: Double {
        let spacing = size.width * 0.09 * Double(amplitudeCount - 1)
        return max((size.width - spacing) / Double(amplitudeCount), 1.5)
    }

    private var fill: AnyShapeStyle {
        if colors.count >= 2 {
            return AnyShapeStyle(LinearGradient(colors: Array(colors.prefix(2)), startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(colors.first ?? .white)
    }

    private func barHeight(index: Int, time: Double) -> Double {
        guard isPlaying else { return barWidth }
        let phase = Double(index) * 1.7
        // Two detuned sines per bar read as organic movement without any audio input.
        let a = sin(time * (5.2 + Double(index) * 0.9) + phase)
        let b = sin(time * (8.7 - Double(index) * 0.6) + phase * 2.3)
        let level = 0.5 + 0.3 * a + 0.2 * b
        return max(barWidth, size.height * min(max(level, 0.18), 1))
    }
}

/// Single-line text that scrolls horizontally only when it does not fit.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = .white
    var isCentered = true
    var speed: Double = 28
    var gap: Double = 36

    @LocalState private var textWidth: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let overflow = textWidth > proxy.size.width + 0.5
            Group {
                if overflow {
                    TimelineView(.animation) { context in
                        let cycle = textWidth + gap
                        let pause = 1.5
                        let total = cycle / speed + pause
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: total)
                        let offset = t < pause ? 0 : (t - pause) * speed
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .offset(x: -offset)
                        .frame(width: proxy.size.width, alignment: .leading)
                    }
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                    .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
                } else {
                    label.frame(width: proxy.size.width, alignment: isCentered ? .center : .leading)
                }
            }
            .frame(height: proxy.size.height)
        }
        .background(
            label
                .hidden()
                .background(GeometryReader { inner in
                    Color.clear
                        .onAppear { textWidth = inner.size.width }
                        .onChange(of: text) { textWidth = inner.size.width }
                        .onChange(of: inner.size.width) { _, new in textWidth = new }
                }),
            alignment: .leading)
        .clipped()
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}

/// Scrubber used by the media player: thin track that thickens while hovered or dragged.
struct MediaProgressSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let fillColors: [Color]
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void

    @LocalState private var dragValue: Double?
    @LocalState private var isHovering = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max(((dragValue ?? value) - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let active = isHovering || dragValue != nil
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(LinearGradient(colors: fillColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.width * fraction, 0))
            }
            .frame(height: active ? 9 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragValue == nil { onEditingChanged(true) }
                        let ratio = min(max(drag.location.x / proxy.size.width, 0), 1)
                        dragValue = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        if let dragValue { onCommit(dragValue) }
                        dragValue = nil
                        onEditingChanged(false)
                    })
            .onHover { hovering in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { isHovering = hovering }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: active)
        }
        .frame(height: 14)
    }
}

/// Button style that dims and shrinks slightly on press, as the original's media controls do.
struct ScaleFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum AppInfo {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Alcove Recreation"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
}

extension Double {
    /// 83.4 → "1:23"
    var asPlaybackTime: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}

/// View-local state. On the macOS 27 SDK `@State` is a macro whose compiler plugin ships only
/// with Xcode; wrapping the underlying `State` struct keeps the project buildable with just
/// the Command Line Tools (`swift build`).
@propertyWrapper
struct LocalState<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
