import SwiftUI

enum ClaudeUsageMetric: String, CaseIterable, Identifiable {
    case planLimit, context
    var id: String { rawValue }
    var title: String { self == .planLimit ? "Plan limit" : "Context window" }
}

extension ClaudeManager.Status {
    var title: String {
        switch self {
        case .working: "Coding"
        case .needsResponse: "Needs you"
        case .finished: "Finished"
        case .idle: "Idle"
        }
    }

    var symbol: String {
        switch self {
        case .working: "sparkle"
        case .needsResponse: "exclamationmark.bubble.fill"
        case .finished: "checkmark.circle.fill"
        case .idle: "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .working: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .needsResponse: .yellow
        case .finished: .green
        case .idle: .gray
        }
    }
}

extension ClaudeManager {
    /// The percentage the compact notch shows, following the "Usage" setting. Plan usage falls
    /// back to the context window when Claude Code has not cached any plan data.
    var displayedUsage: (fraction: Double, label: String)? {
        guard let current else { return nil }
        let metric = Prefs.value(Key.claudeUsageMetric, ClaudeUsageMetric.planLimit)
        if metric == .planLimit, let percent = planUsage.fiveHourPercent {
            return (Double(percent) / 100, "\(percent)%")
        }
        return (current.contextFraction, "\(Int((current.contextFraction * 100).rounded()))%")
    }
}

/// Status glyph with a motion that matches the state: breathing while working, a nudge when
/// Claude is waiting on the user.
struct ClaudeStatusIcon: View {
    let status: ClaudeManager.Status
    let size: Double

    var body: some View {
        Group {
            switch status {
            case .working:
                Image(systemName: status.symbol).symbolEffect(.pulse, options: .repeating)
            case .needsResponse:
                Image(systemName: status.symbol).symbolEffect(.bounce, options: .repeating.speed(0.5))
            default:
                Image(systemName: status.symbol)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(status.color)
        .contentTransition(.symbolEffect(.replace))
    }
}

struct UsageRing: View {
    let fraction: Double
    let size: Double

    private var color: Color {
        switch fraction {
        case ..<0.7: .white
        case ..<0.9: .yellow
        default: .red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: size * 0.16)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.02))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
    }
}

/// Collapsed-notch content for a Claude Code session: status on the left, usage on the right.
struct ClaudeCompactLeading: View {
    let iconSize: Double
    @AppStorage(Key.claudeShowLabel) private var showLabel = true
    private let claude = ClaudeManager.shared

    var body: some View {
        if let session = claude.current {
            HStack(spacing: 5) {
                ClaudeStatusIcon(status: session.status, size: iconSize * 0.66)
                if showLabel {
                    Text(session.status.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.opacity)
                }
            }
        }
    }
}

struct ClaudeCompactTrailing: View {
    let iconSize: Double
    @AppStorage(Key.claudeShowUsage) private var showUsage = true
    @AppStorage(Key.claudeUsageMetric) private var metric = ClaudeUsageMetric.planLimit
    private let claude = ClaudeManager.shared

    var body: some View {
        if showUsage, let usage = claude.displayedUsage {
            HStack(spacing: 5) {
                Text(usage.label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                UsageRing(fraction: usage.fraction, size: iconSize * 0.6)
            }
            .id(metric)
        }
    }
}

/// Opened-notch card with everything known about the session and the account's limits.
struct ClaudeExpandedView: View {
    private let claude = ClaudeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let session = claude.current {
                header(session)
                usageRow(
                    title: "Context", value: "\(session.contextTokens.abbreviatedTokens) / \(session.contextWindow.abbreviatedTokens)",
                    fraction: session.contextFraction)
            } else {
                HStack(spacing: 8) {
                    ClaudeStatusIcon(status: .idle, size: 16)
                    Text("No active Claude Code session")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let percent = claude.planUsage.fiveHourPercent {
                usageRow(title: "5-hour limit", value: "\(percent)%" + resetSuffix, fraction: Double(percent) / 100)
            }
            if let percent = claude.planUsage.sevenDayPercent {
                usageRow(title: "7-day limit", value: "\(percent)%", fraction: Double(percent) / 100)
            }
            if claude.planUsage.fiveHourPercent == nil {
                footnote("Plan usage appears once Claude Code has checked it (run /usage).")
            } else if let fetched = claude.planUsage.fetchedAt, Date().timeIntervalSince(fetched) > 10 * 60 {
                // The figures are whatever Claude Code last cached, which can lag behind.
                footnote("Limits last updated " + Self.relativeFormatter.localizedString(for: fetched, relativeTo: Date()))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
    }

    private var resetSuffix: String {
        guard let reset = claude.planUsage.fiveHourResetsAt, reset > Date() else { return "" }
        return " · resets " + CalendarManager.timeFormatter.string(from: reset)
    }

    private func header(_ session: ClaudeManager.Session) -> some View {
        HStack(spacing: 9) {
            ClaudeStatusIcon(status: session.status, size: 18)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(session.status.color.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.status.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle(session))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func subtitle(_ session: ClaudeManager.Session) -> String {
        var parts = [session.projectName.isEmpty ? "Claude Code" : session.projectName]
        parts.append(session.isDesktop ? "Claude desktop" : "Claude Code")
        if session.status != .finished, let detail = session.detail, !detail.isEmpty { parts.append(detail) }
        return parts.joined(separator: " · ")
    }

    private func usageRow(title: String, value: String, fraction: Double) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(value).foregroundStyle(.white).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(fraction < 0.7 ? Color.white : (fraction < 0.9 ? .yellow : .red))
                        .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 5))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Text for the quick peek shown when Claude finishes or starts waiting.
extension ClaudeManager.Session {
    var peekText: String {
        let project = projectName.isEmpty ? "Claude Code" : projectName
        switch status {
        case .finished: return "Finished · \(project)"
        case .needsResponse: return "Needs your response · \(project)"
        case .working: return "Coding · \(project)"
        case .idle: return project
        }
    }
}
