import AppKit
import Observation
import SwiftUI

/// Borderless overlay that hosts the notch. Configuration mirrors the original's NotchPanel:
/// non-activating, shadowless, clear, pinned across every Space and above the menu bar.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        isMovable = false
        isReleasedWhenClosed = false
        canBecomeVisibleWithoutLogin = true
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// State machine for one display's notch.
@Observable
final class NotchController {
    enum LiveActivity: Equatable { case none, isLocked, isCalendar, isPlaying, isCoding }
    enum QuickPeek: Equatable { case none, isCalendar, isPlaying, isCoding }
    enum Notification: Equatable {
        case none, isCharging, isLowBattery, isLowPowerMode, didConnectAirPods, isFocus
        case didChangeVolume, didChangeBrightness
    }

    /// Fixed overlay size the original gives its panel; the notch animates inside it.
    static let panelSize = CGSize(width: 624, height: 320)

    let screen: NSScreen
    let displayUUID: String

    // Geometry
    private(set) var notchWidth: Double = 0
    private(set) var notchHeight: Double = 0
    private(set) var notchExpandedWidth: Double = 0
    private(set) var notchExpandedHeight: Double = 0
    private(set) var shapeStyle: NotchShape.Style = .notch
    private(set) var hasPhysicalNotch = false

    // Presentation state
    private(set) var isVisible = true
    private(set) var isExpanded = false
    var isMouseInside = false
    var isPressed = false
    private(set) var notification: Notification = .none
    private(set) var liveActivity: LiveActivity = .none
    private(set) var quickPeek: QuickPeek = .none
    private(set) var expandedActivity: ExpandedActivity = .nowPlaying
    /// True while the opened notch shows the Claude Code card instead of an idle activity.
    private(set) var showsCodingExpanded = false
    private(set) var connectedDevice: (name: String, symbol: String)?

    // Gestures
    var gestureHorizontalProgress: Double = 0
    var gestureVerticalProgress: Double = 0

    @ObservationIgnored private var panel: NotchPanel?
    @ObservationIgnored private var notificationWork: DispatchWorkItem?
    @ObservationIgnored private var quickPeekWork: DispatchWorkItem?
    @ObservationIgnored private var hoverWork: DispatchWorkItem?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var pointerTimer: Timer?
    @ObservationIgnored private var dismissedLiveActivity: LiveActivity = .none
    @ObservationIgnored private var expandedFromHover = false
    @ObservationIgnored private var scrollX: Double = 0
    @ObservationIgnored private var scrollY: Double = 0
    @ObservationIgnored private var hasTriggeredSwipe = false

    init(screen: NSScreen) {
        self.screen = screen
        self.displayUUID = screen.displayUUID
        updateDimensions()
    }

    // MARK: Geometry

    /// Reproduces the original's sizing: a physical notch is measured from the screen's
    /// auxiliary areas; other displays get a 74pt pill, or a 140pt simulated notch when forced.
    func updateDimensions() {
        let force = Prefs.bool(Key.forceSimulatedNotch)
        let menuBar = Double(screen.menuBarHeight)
        var width: Double, height: Double, expandedWidth: Double, expandedHeight: Double

        if screen.hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = Double(screen.frame.width - left.width - right.width)
            height = Double(screen.safeAreaInsets.top)
            expandedWidth = max(width + 160, 345)
            expandedHeight = max(height + 142, 175)
            shapeStyle = .notch
            hasPhysicalNotch = true
        } else if force {
            width = 140
            height = menuBar > 0 ? menuBar - 4 : 24
            expandedWidth = 345
            expandedHeight = 175
            shapeStyle = .notch
            hasPhysicalNotch = false
        } else {
            width = 74
            height = menuBar > 0 ? menuBar - 0.8125 : 19.5
            expandedWidth = 321
            expandedHeight = 175
            shapeStyle = .pill
            hasPhysicalNotch = false
        }
        notchWidth = width + Prefs.double(Key.notchAdjustedWidth)
        notchHeight = height + Prefs.double(Key.notchAdjustedHeight)
        notchExpandedWidth = expandedWidth
        notchExpandedHeight = expandedHeight
        positionPanel()
    }

    /// Width/height of the black shape for the current state.
    var currentSize: CGSize {
        if isExpanded {
            let width = expandedActivity == .duo ? min(notchExpandedWidth * 1.62, 596) : notchExpandedWidth
            return CGSize(width: width, height: notchExpandedHeight)
        }
        if notification != .none {
            return CGSize(width: notchWidth + 2 * notificationSideWidth, height: notchHeight)
        }
        if liveActivity != .none {
            var side = notchHeight + 6
            if liveActivity == .isCoding {
                // Room for the status word on the left and the usage figure on the right.
                side = Prefs.bool(Key.claudeShowLabel) ? 92 : max(side, 58)
            }
            let peek: Double = quickPeek == .none ? 0 : 30
            let minimumPeekWidth: Double = quickPeek == .none ? 0 : (quickPeek == .isCoding ? 310 : 250)
            return CGSize(width: max(notchWidth + 2 * side, minimumPeekWidth), height: notchHeight + peek)
        }
        return CGSize(width: notchWidth, height: notchHeight)
    }

    private var notificationSideWidth: Double {
        switch notification {
        case .didChangeVolume, .didChangeBrightness: 78
        case .isCharging, .isLowBattery, .isLowPowerMode: 84
        case .didConnectAirPods, .isFocus: 90
        case .none: 0
        }
    }

    /// The shape's frame in screen coordinates, used for hit-testing outside SwiftUI.
    var notchScreenRect: CGRect {
        let size = currentSize
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width, height: size.height)
    }

    // MARK: Window

    func show() {
        guard panel == nil else { return }
        let panel = NotchPanel()
        let hosting = NSHostingView(rootView: NotchView(notchController: self))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.sharingType = Prefs.bool(Key.hideFromScreenCapture) ? .none : .readOnly
        self.panel = panel
        positionPanel()
        // The panel is far larger than the notch it draws. It takes mouse events only while the
        // pointer is over the visible shape (see updateHover), so everything else under it —
        // menu bar items, windows — stays clickable.
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        installMonitors()
        refreshLiveActivity(animated: false)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pointerTimer?.invalidate()
        pointerTimer = nil
        panel?.close()
        panel = nil
    }

    private func positionPanel() {
        let size = Self.panelSize
        panel?.setFrame(
            CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height),
            display: false)
    }

    func applySettings() {
        panel?.sharingType = Prefs.bool(Key.hideFromScreenCapture) ? .none : .readOnly
        updateDimensions()
        evaluateVisibility()
        refreshLiveActivity(animated: true)
    }

    func evaluateVisibility() {
        var visible = true
        if Prefs.bool(Key.hideWhileInFullscreen), let id = screen.displayID,
           ScreenManager.shared.fullscreenDisplayIDs.contains(id) {
            visible = false
        }
        if Prefs.bool(Key.hideWhileGaming), ScreenManager.shared.isGaming {
            visible = false
        }
        guard visible != isVisible else { return }
        withAnimation(.easeInOut(duration: 0.25)) { isVisible = visible }
        if !visible { collapse() }
        updateHover()
    }

    // MARK: Notifications (transient HUDs)

    func present(_ notification: Notification, device: (name: String, symbol: String)? = nil) {
        // While hidden (fullscreen, gaming) only the volume and brightness HUDs still appear:
        // the system ones are suppressed, so without them the keys would give no feedback.
        guard isVisible || isHUD(notification), notification != .none, !isExpanded || isHUD(notification) else { return }
        if LockManager.shared.isLocked, !isAllowedWhenLocked(notification) { return }
        if FocusManager.shared.isFocus, !isAllowedWhenFocused(notification) { return }
        if let device { connectedDevice = device }
        notificationWork?.cancel()
        let isSwap = self.notification != .none && self.notification != notification
        withAnimation(isSwap ? .spring(response: 0.3, dampingFraction: 0.9) : NotchAnimation.open) {
            self.notification = notification
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(NotchAnimation.close) { self?.notification = .none }
        }
        notificationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration(for: notification), execute: work)
    }

    func isHUD(_ notification: Notification) -> Bool {
        notification == .didChangeVolume || notification == .didChangeBrightness
    }

    private func duration(for notification: Notification) -> Double {
        let value: Double
        switch notification {
        case .didChangeVolume: value = Prefs.double(Key.volumeDuration)
        case .didChangeBrightness: value = Prefs.double(Key.brightnessDuration)
        case .isCharging, .isLowBattery, .isLowPowerMode: value = Prefs.double(Key.batteryDuration)
        case .didConnectAirPods: value = Prefs.double(Key.connectivityDuration)
        case .isFocus: value = Prefs.double(Key.focusDuration)
        case .none: value = 0
        }
        return max(value, 0.5)
    }

    private func isAllowedWhenLocked(_ notification: Notification) -> Bool {
        let key: String
        switch notification {
        case .didChangeVolume: key = "allowVolumeWhenLocked"
        case .didChangeBrightness: key = "allowBrightnessWhenLocked"
        case .isCharging, .isLowBattery, .isLowPowerMode: key = "allowBatteryWhenLocked"
        case .didConnectAirPods: key = "allowConnectivityWhenLocked"
        case .isFocus: key = "allowFocusWhenLocked"
        case .none: return false
        }
        return Prefs.store.object(forKey: key) as? Bool ?? true
    }

    private func isAllowedWhenFocused(_ notification: Notification) -> Bool {
        let key: String
        switch notification {
        case .didChangeVolume: key = "allowVolumeWhenFocused"
        case .didChangeBrightness: key = "allowBrightnessWhenFocused"
        case .isCharging, .isLowBattery, .isLowPowerMode: key = "allowBatteryWhenFocused"
        case .didConnectAirPods: key = "allowConnectivityWhenFocused"
        case .isFocus, .none: return true
        }
        return Prefs.store.object(forKey: key) as? Bool ?? true
    }

    // MARK: Live activities

    /// Picks the persistent activity: lock, then an imminent calendar event, then playback.
    func refreshLiveActivity(animated: Bool) {
        let media = MediaManager.shared
        let calendar = CalendarManager.shared
        let idle = Prefs.value(Key.idleActivity, ExpandedActivity.nowPlaying)
        var next: LiveActivity = .none

        // "Hide while source app is active": the player itself is in front, so the notch steps back.
        let sourceIsActive = Prefs.bool(Key.hideWhileSourceIsActive) && media.appBundleId != nil
            && ScreenManager.shared.frontmostBundleID == media.appBundleId
        let playingAvailable = Prefs.bool(Key.enableNowPlaying) && media.hasTrack && !media.isHidden && !sourceIsActive
            && (media.isPlaying || media.hasRecentlyPaused || Prefs.bool(Key.forceEnableActivity))
        let calendarAvailable = Prefs.bool(Key.enableCalendar) && calendar.nextEventActivity != nil

        // A Claude Code session waiting on the user always wins; otherwise it takes the notch
        // from the other activities only when the user asked for that.
        let coding = Prefs.bool(Key.enableClaudeStatus) ? ClaudeManager.shared.current : nil
        let codingWins = coding.map {
            $0.status == .needsResponse || Prefs.bool(Key.claudePrioritize) || !(playingAvailable || calendarAvailable)
        } ?? false

        if LockManager.shared.isLocked, Prefs.bool(Key.enableLockScreen) {
            next = .isLocked
        } else if codingWins {
            next = .isCoding
        } else if calendarAvailable, !(playingAvailable && idle == .nowPlaying && media.isPlaying) {
            next = .isCalendar
        } else if playingAvailable {
            next = .isPlaying
        } else if calendarAvailable {
            next = .isCalendar
        }
        if next == dismissedLiveActivity { next = .none } else { dismissedLiveActivity = .none }

        guard next != liveActivity else { return }
        if animated {
            withAnimation(next == .none ? NotchAnimation.close : NotchAnimation.open) { liveActivity = next }
        } else {
            liveActivity = next
        }
        if next == .none { quickPeek = .none }
    }

    func showQuickPeek(_ peek: QuickPeek) {
        guard !isExpanded, isVisible, notification == .none else { return }
        let duration: Double
        switch peek {
        case .isPlaying:
            guard Prefs.bool(Key.enableQuickPeek), liveActivity == .isPlaying else { return }
            duration = Prefs.double(Key.peekDuration)
        case .isCalendar:
            guard Prefs.bool(Key.enableCalendarQuickPeek), liveActivity == .isCalendar else { return }
            duration = Prefs.double(Key.calendarPeekDuration)
        case .isCoding:
            guard Prefs.bool(Key.claudePeek), liveActivity == .isCoding else { return }
            duration = 4
        case .none:
            return
        }
        quickPeekWork?.cancel()
        withAnimation(NotchAnimation.open) { quickPeek = peek }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(NotchAnimation.close) { self?.quickPeek = .none }
        }
        quickPeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 1), execute: work)
    }

    // MARK: Expansion

    func expand(fromHover: Bool = false) {
        guard !isExpanded, isVisible else { return }
        let resolved = resolvedExpandedActivity()
        let coding = liveActivity == .isCoding
        guard resolved != .none || coding else { return }
        showsCodingExpanded = coding
        expandedFromHover = fromHover
        quickPeekWork?.cancel()
        notificationWork?.cancel()
        HapticFeedback.shared.tap(.levelChange)
        withAnimation(NotchAnimation.expand) {
            expandedActivity = resolved
            quickPeek = .none
            notification = .none
            isExpanded = true
        }
        MediaManager.shared.setPolling(true, source: "notchExpanded-\(displayUUID)")
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(NotchAnimation.collapse) { isExpanded = false }
        MediaManager.shared.setPolling(false, source: "notchExpanded-\(displayUUID)")
    }

    func toggle() { isExpanded ? collapse() : expand() }

    private func resolvedExpandedActivity() -> ExpandedActivity {
        let nowPlaying = Prefs.bool(Key.enableNowPlaying)
        let calendar = Prefs.bool(Key.enableCalendar) && CalendarManager.shared.isAuthorized
        var wanted = Prefs.value(Key.idleActivity, ExpandedActivity.nowPlaying)
        if Prefs.bool(Key.mostRecentActivity) {
            if liveActivity == .isCalendar { wanted = .calendar }
            if liveActivity == .isPlaying { wanted = .nowPlaying }
        }
        switch wanted {
        case .duo: return nowPlaying && calendar ? .duo : (nowPlaying ? .nowPlaying : (calendar ? .calendar : .none))
        case .calendar: return calendar ? .calendar : (nowPlaying ? .nowPlaying : .none)
        case .nowPlaying: return nowPlaying ? .nowPlaying : (calendar ? .calendar : .none)
        case .none: return nowPlaying ? .nowPlaying : (calendar ? .calendar : .none)
        }
    }

    /// Swipe down while expanded steps through Now Playing → Calendar → Duo.
    func cycleExpandedActivity() {
        let nowPlaying = Prefs.bool(Key.enableNowPlaying)
        let calendar = Prefs.bool(Key.enableCalendar) && CalendarManager.shared.isAuthorized
        if showsCodingExpanded {
            // First swipe leaves the Claude card for whatever the notch would normally open with.
            guard resolvedExpandedActivity() != .none else { return }
            HapticFeedback.shared.tap(.levelChange)
            withAnimation(NotchAnimation.expand) { showsCodingExpanded = false }
            return
        }
        guard nowPlaying, calendar else { return }
        let order: [ExpandedActivity] = [.nowPlaying, .calendar, .duo]
        let index = order.firstIndex(of: expandedActivity) ?? 0
        HapticFeedback.shared.tap(.levelChange)
        withAnimation(NotchAnimation.expand) { expandedActivity = order[(index + 1) % order.count] }
    }

    func dismissLiveActivity() {
        guard liveActivity != .none, liveActivity != .isLocked else { return }
        dismissedLiveActivity = liveActivity
        HapticFeedback.shared.tap(.generic)
        withAnimation(NotchAnimation.close) {
            liveActivity = .none
            quickPeek = .none
        }
    }

    // MARK: Pointer and gestures

    private func installMonitors() {
        // The shape also changes size on its own (HUDs, activities) while the pointer rests, and
        // no mouse event announces that; re-check a few times a second so a click never lands on
        // a stale answer.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.updateHover() }
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.updateHover() }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            moved(event)
            return event
        }) { monitors.append(monitor) }

        // Clicking anywhere else closes the expanded notch.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard let self, self.isExpanded, !self.notchScreenRect.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        }) { monitors.append(monitor) }

        let scrolled: (NSEvent) -> Void = { [weak self] event in self?.handleScroll(event) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: scrolled) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            scrolled(event)
            return event
        }) { monitors.append(monitor) }
    }

    private func updateHover() {
        let inside = isVisible && notchScreenRect.contains(NSEvent.mouseLocation)
        // Set on every pass, not only on change: the shape can grow or shrink under a still pointer.
        if panel?.ignoresMouseEvents != !inside { panel?.ignoresMouseEvents = !inside }
        guard inside != isMouseInside else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isMouseInside = inside }
        hoverWork?.cancel()
        if inside {
            if !isExpanded { HapticFeedback.shared.tap(.alignment) }
            guard Prefs.bool(Key.expandNotchOnHover), !isExpanded else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isMouseInside else { return }
                self.expand(fromHover: true)
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Prefs.double(Key.hoverDuration), execute: work)
        } else if isExpanded, expandedFromHover {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isMouseInside else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard isVisible, event.hasPreciseScrollingDeltas || event.phase == [] else { return }
        if event.phase == .began || event.phase == .mayBegin {
            scrollX = 0
            scrollY = 0
            hasTriggeredSwipe = false
        }
        let ended = event.phase == .ended || event.phase == .cancelled
        guard notchScreenRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) || (hasTriggeredSwipe && !ended) else {
            if ended { resetGesture() }
            return
        }
        if ended || event.momentumPhase != [] {
            resetGesture()
            return
        }
        guard !hasTriggeredSwipe else { return }
        let direction: Double = Prefs.bool(Key.naturalMovement) ? -1 : 1
        scrollX += Double(event.scrollingDeltaX)
        scrollY += Double(event.scrollingDeltaY) * direction

        let horizontalThreshold: Double = 70
        let verticalThreshold: Double = 46
        if abs(scrollX) > abs(scrollY) {
            guard Prefs.bool(Key.swipeToSkip), Prefs.bool(Key.enableNowPlaying), MediaManager.shared.hasTrack,
                  isExpanded ? expandedActivity != .calendar : liveActivity == .isPlaying else { return }
            gestureHorizontalProgress = max(min(scrollX / horizontalThreshold, 1), -1)
            if abs(scrollX) >= horizontalThreshold {
                hasTriggeredSwipe = true
                HapticFeedback.shared.tap(.levelChange)
                // Content follows the fingers: swiping left brings in the next track.
                scrollX < 0 ? MediaManager.shared.nextTrack() : MediaManager.shared.previousTrack()
                resetGesture()
            }
        } else {
            gestureVerticalProgress = max(min(scrollY / verticalThreshold, 1), -1)
            guard abs(scrollY) >= verticalThreshold else { return }
            hasTriggeredSwipe = true
            let isDown = scrollY > 0
            if isExpanded {
                if isDown, Prefs.bool(Key.swipeToCycleActivity) {
                    cycleExpandedActivity()
                } else if !isDown, Prefs.bool(Key.swipeToToggle) {
                    collapse()
                }
            } else if isDown {
                if Prefs.bool(Key.swipeToToggle) { expand() }
            } else if Prefs.bool(Key.swipeToDismiss) {
                dismissLiveActivity()
            }
            resetGesture()
        }
    }

    private func resetGesture() {
        guard gestureHorizontalProgress != 0 || gestureVerticalProgress != 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            gestureHorizontalProgress = 0
            gestureVerticalProgress = 0
        }
    }
}

enum NotchAnimation {
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let close = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let expand = Animation.spring(response: 0.45, dampingFraction: 0.8)
    static let collapse = Animation.spring(response: 0.4, dampingFraction: 0.92)
}

/// Owns one controller per eligible display, following the "Display on" setting.
final class NotchCoordinator {
    static let shared = NotchCoordinator()
    private(set) var controllers: [String: NotchController] = [:]

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        rebuild()
    }

    func rebuild() {
        let wanted = targetScreens()
        let wantedIDs = Set(wanted.map(\.displayUUID))
        for (uuid, controller) in controllers where !wantedIDs.contains(uuid) {
            controller.close()
            controllers[uuid] = nil
        }
        for screen in wanted {
            if let existing = controllers[screen.displayUUID], existing.screen == screen {
                existing.applySettings()
            } else {
                controllers[screen.displayUUID]?.close()
                let controller = NotchController(screen: screen)
                controllers[screen.displayUUID] = controller
                controller.show()
            }
        }
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch Prefs.value(Key.showOnDisplay, DisplayType.mainScreen) {
        case .allDisplays:
            return screens
        case .builtInDisplay:
            return [screens.first(where: \.isBuiltIn) ?? screens.first].compactMap { $0 }
        case .specificDisplay:
            let uuid = Prefs.string(Key.showOnDisplayUUID)
            return [screens.first(where: { $0.displayUUID == uuid }) ?? screens.first].compactMap { $0 }
        case .mainScreen:
            // "Main display" is the one carrying the menu bar, i.e. the first screen.
            return [screens.first].compactMap { $0 }
        }
    }

    func forEach(_ body: (NotchController) -> Void) { controllers.values.forEach(body) }
}
