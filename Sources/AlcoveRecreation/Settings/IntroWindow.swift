import AppKit
import SwiftUI

/// Welcome window, shown after the permissions step of onboarding. Copy and gesture hints come
/// from the original's intro strings.
final class IntroController {
    static let shared = IntroController()
    private var windowController: NSWindowController?

    func show() {
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: IntroView { [weak self] in self?.finish() })
            window.center()
            windowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
    }

    private func finish() {
        Prefs.store.set(false, forKey: Key.isFirstLaunch)
        windowController?.close()
        windowController = nil
    }
}

struct IntroView: View {
    let onFinish: () -> Void

    @LocalState private var hasEntered = false

    private let gestures: [(symbol: String, text: String)] = [
        ("hand.tap.fill", "Tap to show expanded view"),
        ("arrow.up.and.down", "Swipe vertically to toggle open"),
        ("arrow.left.and.right", "Swipe horizontally to skip media"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            NotchShape(style: .notch, topCornerRadius: 8, bottomCornerRadius: 18)
                .fill(.black)
                .frame(width: hasEntered ? 230 : 150, height: 46)
                .overlay(
                    HStack {
                        ArtworkView(image: nil, size: 28, cornerRadius: 7)
                        Spacer()
                        Waveform(isPlaying: true, colors: [.pink, .orange], size: CGSize(width: 24, height: 18))
                    }
                    .padding(.horizontal, 14)
                    .opacity(hasEntered ? 1 : 0))
                .padding(.top, 34)

            Text(AppInfo.name).font(.system(size: 26, weight: .bold))
            Text("It bubbles up notifications, alerts and activities, fluidly transforming itself into your notch.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(gestures, id: \.text) { gesture in
                    HStack(spacing: 10) {
                        Image(systemName: gesture.symbol).frame(width: 22).foregroundStyle(.tint)
                        Text(gesture.text).font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)

            Button {
                onFinish()
            } label: {
                Text("Get Started").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 26)
        }
        .frame(width: 420, height: 440)
        .background(.regularMaterial)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3)) { hasEntered = true }
        }
    }
}
