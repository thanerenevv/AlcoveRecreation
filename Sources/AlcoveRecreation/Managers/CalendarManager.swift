import AppKit
import EventKit
import Observation
import SwiftUI

/// EventKit-backed calendar model: today's events, the compact week strip and the
/// "next event" live activity with its countdown.
@Observable
final class CalendarManager {
    static let shared = CalendarManager()

    struct EventModel: Identifiable, Equatable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let color: Color
        let location: String?
        let meetingURL: URL?
    }

    struct CalendarDayCell: Identifiable {
        let id: Int
        let date: Date
        let dayNumber: Int
        let symbol: String
        let isWeekend: Bool
        let isToday: Bool
        let eventColors: [Color]
    }

    private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var events: [EventModel] = []
    private(set) var weekDays: [CalendarDayCell] = []
    /// The upcoming or in-progress event that owns the live activity, if any.
    private(set) var nextEventActivity: EventModel?
    private(set) var timeUntilStart: TimeInterval?
    private(set) var progressUntilEnd: Double?
    var selectedDate = Calendar.current.startOfDay(for: Date()) {
        didSet { rebuild() }
    }

    @ObservationIgnored var onEventStarting: ((EventModel) -> Void)?
    @ObservationIgnored var onActivityChange: (() -> Void)?
    @ObservationIgnored private let eventStore = EKEventStore()
    @ObservationIgnored private var countdownTimer: Timer?
    @ObservationIgnored private var hourlyChimeTimer: Timer?
    @ObservationIgnored private var fetched: [EKEvent] = []
    @ObservationIgnored private var announcedEventIDs: Set<String> = []
    @ObservationIgnored private var dismissedEventIDs: Set<String> = []

    var isAuthorized: Bool { authorizationStatus == .fullAccess }

    func start() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            self?.fetch()
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            self?.selectedDate = Calendar.current.startOfDay(for: Date())
            self?.fetch()
        }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        scheduleHourlyChime()
        fetch()
    }

    func requestAccess(completion: ((Bool) -> Void)? = nil) {
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                self?.fetch()
                completion?(granted)
            }
        }
    }

    var calendars: [EKCalendar] { isAuthorized ? eventStore.calendars(for: .event) : [] }

    func dismissCurrentEvent() {
        guard let event = nextEventActivity else { return }
        dismissedEventIDs.insert(event.id)
        tick()
    }

    // MARK: Fetching

    func fetch() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized, Prefs.bool(Key.enableCalendar) else {
            fetched = []
            rebuild()
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let end = calendar.date(byAdding: .day, value: 8, to: weekStart) ?? today
        let excluded = Prefs.stringSet(Key.excludedCalendars)
        let included = eventStore.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !included.isEmpty else { fetched = []; rebuild(); return }
        let predicate = eventStore.predicateForEvents(withStart: weekStart, end: end, calendars: included)
        fetched = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
        rebuild()
    }

    private func model(_ event: EKEvent) -> EventModel {
        EventModel(
            id: (event.eventIdentifier ?? UUID().uuidString) + "|\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color),
            location: event.location,
            meetingURL: Self.meetingURL(in: event))
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap(\.url).first(where: isMeeting)
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return url.scheme == "facetime" }
        return ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
            .contains { host.hasSuffix($0) }
    }

    private func rebuild() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        events = fetched.filter { calendar.isDate($0.startDate, inSameDayAs: selectedDate) || ($0.startDate < selectedDate && $0.endDate > selectedDate) }
            .map(model)

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? today
        let symbols = calendar.veryShortWeekdaySymbols
        weekDays = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let colors = fetched.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
                .map { Color(nsColor: $0.calendar.color) }
            var unique: [Color] = []
            for color in colors where !unique.contains(color) { unique.append(color) }
            return CalendarDayCell(
                id: offset, date: date,
                dayNumber: calendar.component(.day, from: date),
                symbol: symbols[weekday - 1],
                isWeekend: calendar.isDateInWeekend(date),
                isToday: calendar.isDate(date, inSameDayAs: today),
                eventColors: Array(unique.prefix(3)))
        }
        tick()
    }

    // MARK: Live activity

    private func tick() {
        let now = Date()
        let lead = Prefs.double(Key.timeBeforeEvent) * 60
        let candidate = fetched.lazy
            .filter { !$0.isAllDay && $0.endDate > now && $0.startDate.timeIntervalSince(now) <= lead }
            .map(model)
            .first { !self.dismissedEventIDs.contains($0.id) }

        let previous = nextEventActivity
        nextEventActivity = Prefs.bool(Key.enableCalendar) ? candidate : nil
        if let event = nextEventActivity {
            let untilStart = event.startDate.timeIntervalSince(now)
            timeUntilStart = untilStart > 0 ? untilStart : nil
            let total = event.endDate.timeIntervalSince(event.startDate)
            progressUntilEnd = untilStart <= 0 && total > 0 ? min(max(now.timeIntervalSince(event.startDate) / total, 0), 1) : nil
            if untilStart <= 0, !announcedEventIDs.contains(event.id) {
                announcedEventIDs.insert(event.id)
                // Only announce events we actually watched start, not ones already running at launch.
                if now.timeIntervalSince(event.startDate) < 5 {
                    if Prefs.bool(Key.playSoundOnCalendarEvent) { SoundManager.shared.play(.event) }
                    onEventStarting?(event)
                }
            }
        } else {
            timeUntilStart = nil
            progressUntilEnd = nil
        }
        if previous?.id != nextEventActivity?.id { onActivityChange?() }
    }

    private func scheduleHourlyChime() {
        let calendar = Calendar.current
        guard let nextHour = calendar.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        hourlyChimeTimer = Timer(fire: nextHour, interval: 3600, repeats: true) { _ in
            if Prefs.bool(Key.playHourlyChime) { SoundManager.shared.play(.chime) }
        }
        if let hourlyChimeTimer { RunLoop.main.add(hourlyChimeTimer, forMode: .common) }
    }

    // MARK: Formatting

    var countdownText: String {
        guard let event = nextEventActivity else { return "" }
        if let timeUntilStart {
            let minutes = Int(ceil(timeUntilStart / 60))
            return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(minutes, 1))m"
        }
        let remaining = Int(ceil(event.endDate.timeIntervalSinceNow / 60))
        return remaining >= 60 ? "\(remaining / 60)h \(remaining % 60)m" : "\(max(remaining, 1))m"
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var selectedDayNumber: String { "\(Calendar.current.component(.day, from: selectedDate))" }

    var selectedMonthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: selectedDate)
    }

    var shortDayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: Date()).uppercased()
    }

    var dayNumber: String { "\(Calendar.current.component(.day, from: Date()))" }

    var emptyStateText: String {
        let calendar = Calendar.current
        if !calendar.isDateInToday(selectedDate) { return "This day is clear" }
        let hadEarlier = fetched.contains { calendar.isDateInToday($0.startDate) && $0.endDate < Date() }
        return hadEarlier ? "No more events today" : "Your day is clear"
    }
}
