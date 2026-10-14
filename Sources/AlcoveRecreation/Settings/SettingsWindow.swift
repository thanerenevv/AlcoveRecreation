import AppKit
import Observation
import SwiftUI

/// Tabs and grouping follow the original's SettingsTab enum and sidebar section strings.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, battery, connectivity, focus, display, sound, nowPlaying, calendar, fileTray, lockScreen, developer, debug, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .battery: "Battery"
        case .connectivity: "Connectivity"
        case .focus: "Focus"
        case .display: "Display"
        case .sound: "Sound"
        case .nowPlaying: "Now Playing"
        case .calendar: "Calendar"
        case .fileTray: "File Tray"
        case .lockScreen: "Lock Screen"
        case .developer: "Developer"
        case .debug: "Debug Mode"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .battery: "battery.75percent"
        case .connectivity: "airpods.gen3"
        case .focus: "moon.fill"
        case .display: "sun.max.fill"
        case .sound: "speaker.wave.2.fill"
        case .nowPlaying: "music.note"
        case .calendar: "calendar"
        case .fileTray: "tray.fill"
        case .lockScreen: "lock.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .debug: "ladybug.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .battery: .green
        case .connectivity: .blue
        case .focus: .indigo
        case .display: .orange
        case .sound: .pink
        case .nowPlaying: .red
        case .calendar: .red
        case .fileTray: .teal
        case .lockScreen: .gray
        case .developer: .orange
        case .debug: .red
        case .about: .blue
        }
    }

    static let sections: [(title: String?, tabs: [SettingsTab])] = [
        (nil, [.general]),
        ("Notifications", [.battery, .connectivity, .focus, .display, .sound]),
        ("Live Activities", [.nowPlaying, .calendar, .fileTray]),
        (nil, [.lockScreen, .developer, .debug, .about]),
    ]
}

@Observable
final class SettingsController {
    static let shared = SettingsController()

    var currentTab: SettingsTab = .general
    @ObservationIgnored private var windowController: NSWindowController?

    func show(tab: SettingsTab? = nil) {
        if let tab { currentTab = tab }
        if windowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "\(AppInfo.name) Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsWindowView(controller: self))
            window.center()
            windowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsWindowView: View {
    @Bindable var controller: SettingsController

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 720, height: 600)
        .background(.regularMaterial)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(SettingsTab.sections.enumerated()), id: \.offset) { _, section in
                if let title = section.title {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                } else {
                    Spacer().frame(height: 8)
                }
                ForEach(section.tabs) { tab in
                    sidebarRow(tab)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 40)
        .frame(width: 200)
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let active = controller.currentTab == tab
        return Button {
            controller.currentTab = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tab.color.gradient))
                Text(tab.title).font(.system(size: 13, weight: .medium))
                Spacer()
                if tab == .fileTray {
                    Text("Soon")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.secondary.opacity(0.25)))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Color.primary.opacity(0.1) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        Group {
            switch controller.currentTab {
            case .general: GeneralSettingsView()
            case .battery: BatterySettingsView()
            case .connectivity: ConnectivitySettingsView()
            case .focus: FocusSettingsView()
            case .display: HUDSettingsView(kind: .brightness)
            case .sound: HUDSettingsView(kind: .volume)
            case .nowPlaying: NowPlayingSettingsView()
            case .calendar: CalendarSettingsView()
            case .fileTray: FileTraySettingsView()
            case .lockScreen: LockScreenSettingsView()
            case .developer: DeveloperSettingsView()
            case .debug: DebugSettingsView()
            case .about: AboutSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 20)
    }
}

/// Labelled slider with a formatted trailing value, the recreation's take on ValueAdjuster.
struct ValueAdjuster: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5
    var suffix = "s"

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step).frame(width: 160)
                Text(formatted).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var formatted: String {
        let number = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return number + suffix
    }
}

/// Picker over a CaseIterable option enum stored by raw value.
struct OptionPicker<Option: CaseIterable & Identifiable & Hashable>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option
    let label: (Option) -> String
    var segmented = false

    var body: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(Option.allCases) { option in
                Text(label(option)).tag(option)
            }
        }
        if segmented { picker.pickerStyle(.segmented) } else { picker }
    }
}
