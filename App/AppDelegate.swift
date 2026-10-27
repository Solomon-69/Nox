import Cocoa
import QuartzCore
import SafariServices
import ServiceManagement
import SwiftUI
import UserNotifications

private let extensionID = "com.solomon.DarkSwitch.Extension"
private let forceDarkKey = "forceDark"
let smoothFadeKey = "smoothFade"
private let onboardedKey = "onboardingDone"
private let scheduleKey = "nightSchedule"
private let darkAtKey = "darkAtMinutes"
private let lightAtKey = "lightAtMinutes"
private let showInDockKey = "showInDock"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let model = DarkSwitchModel()
    private var window: NSWindow?

    private let darkItem = NSMenuItem()
    private let forceItem = NSMenuItem()
    private let extensionItem = NSMenuItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Renamed/moved app: point the login item at this copy.
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.register() }
        // Old builds and Trash copies show up as extra "Nox" entries in Safari: forget them.
        RegistrationCleanup.runInBackground()
        UserDefaults.standard.register(defaults: [forceDarkKey: true, darkAtKey: 20 * 60, lightAtKey: 7 * 60])
        // Whatever look the Mac has right now was not set by this run of Nox, so web pages stay stock.
        NoxDark.apply(.launched(intentDark: NoxDark.intent, systemDark: systemIsDark))
        ChromeBridge.register()
        wireModel()
        applyDockPolicy()
        buildMenu()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
            installPressWatcher()
            installIconView()
        }
        refreshState()
        if !UserDefaults.standard.bool(forKey: onboardedKey) { showOnboarding() }
        startSchedule()
        // Tell our other apps where the quick switch is, so clicking it never closes their panels.
        publishToggleFrame()
        if let w = statusItem.button?.window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(publishToggleFrame), name: name, object: w)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(publishToggleFrame),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // One panel at a time: another of our apps opening its panel closes this one.
        PanelGroup.listen { [weak self] in self?.closePanel() }
        // Test hook (same idea as Sleepless): lets automated checks flip the switch or open the panel.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(testCommand(_:)), name: Notification.Name("com.solomon.DarkSwitch.test"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(appearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshExtensionState),
            name: NSApplication.didBecomeActiveNotification, object: nil)
        // Keep dark on everywhere while Nox's dark is on: check again whenever an app opens,
        // the Mac wakes, or you log back in.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(self, selector: #selector(keepDarkAfterWake), name: name, object: nil)
        }
        warmUpSystemEvents()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.keepDark(reason: "launch") }
    }

    // MARK: Keep dark on

    /// Puts dark mode back if Nox's dark is on but the Mac went light behind its back.
    private func keepDark(reason: String) {
        let sys = systemIsDark
        guard NoxDark.shouldReassertDark(intentDark: NoxDark.intent, systemDark: sys, switching: isSwitching) else {
            dlog("keepdark(\(reason)): ok intent=\(NoxDark.intent) systemDark=\(sys) pagesDark=\(NoxDark.flag)")
            return
        }
        dlog("keepdark(\(reason)): Mac is light but Nox dark is on: switching back to dark")
        toggleMacDark(fade: false)
    }

    @objc private func keepDarkAfterWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.keepDark(reason: "wake") }
    }

    @objc private func appLaunched(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier,
           (CFPreferencesCopyAppValue("NSRequiresAquaSystemAppearance" as CFString, id as CFString) as? Bool) == true {
            // That app forces itself light with its own setting; macOS lets it, Nox can't override it.
            dlog("keepdark: \(id) is set to stay light by its own setting")
        }
        keepDark(reason: "app \(app?.bundleIdentifier ?? "?")")
    }

    /// The first "tell System Events" after login starts System Events, which can take seconds and
    /// made the first click seem to do nothing. Start it quietly now (only once permission exists,
    /// so this never shows Apple's prompt by surprise).
    private func warmUpSystemEvents() {
        guard Permissions.automationState() == true else { return }
        Self.scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to get dark mode of appearance preferences")?
                .executeAndReturnError(&error)
            dlog("warmup: System Events \(error == nil ? "ready" : "error \(error!)")")
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Menu bar clicks: quick click flips dark mode, long press (or right click) opens the panel

    private var pressTimer: Timer?
    private var longPressFired = false
    private static let longPressDelay: TimeInterval = 0.4

    @objc private func statusClicked() {
        guard let event = NSApp.currentEvent else { dlog("click: no event"); return }
        dlog("click: \(event.type.rawValue) panel=\(panelIsShown) switching=\(isSwitching) held=\(longPressFired)")
        switch event.type {
        case .rightMouseUp:
            cancelHold()
            if panelIsShown { closePanel() } else { showPopover() }
        case .leftMouseDown:
            // macOS hands this over only on release, but its time stamp is when you really pressed.
            downStamp = event.timestamp
            if pressStart == nil { startHold() }   // normally already started by pollButton
        case .leftMouseUp where !event.modifierFlags.intersection([.option, .control]).isEmpty:
            // Option-click or Control-click opens the panel (a reliable alternative to holding).
            cancelHold()
            if panelIsShown { closePanel() } else { showPopover() }
        case .leftMouseUp:
            pressTimer?.invalidate(); pressTimer = nil
            // Measured with the click's own time stamp: on a busy Mac the release can arrive late,
            // which used to turn a normal click into a hold and open the panel by mistake.
            let held = (downStamp ?? pressStart).map { max(0, event.timestamp - $0) } ?? 0
            downStamp = nil
            pressStart = nil
            if longPressFired { return }
            if held >= Self.longPressDelay { longPressFired = true; showPopover(); return }
            if panelIsShown { closePanel() } else { toggleMacDark() }
        default:
            break
        }
    }

    // macOS holds back a menu bar icon's mouse-down until release (it waits to see if you
    // drag the icon), so a timer started from the click can never fire mid-hold. While the
    // pointer is over the icon, watch the real button state instead.
    private var downStamp: TimeInterval?
    private var pressStart: TimeInterval?   // system uptime, the same clock as event timestamps
    private var hoverTimer: Timer?
    private var buttonWasDown = false

    private func installPressWatcher() {
        guard let button = statusItem.button else { return }
        button.addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .assumeInside], owner: self, userInfo: nil))
        // macOS doesn't reliably say when the pointer reaches a menu bar icon, so also follow the
        // pointer itself and start or stop watching as it moves onto or off the icon.
        let follow: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        pointerMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: follow) as Any,
            NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { follow($0); return $0 } as Any,
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.pointerMoved() }
    }

    private var pointerMonitors: [Any] = []

    private func pointerMoved() {
        guard let frame = statusItem.button?.window?.frame else { return }
        let inside = frame.contains(NSEvent.mouseLocation)
        if inside, hoverTimer == nil { startHoverWatch() }
        if !inside, hoverTimer != nil { stopHoverWatch() }
    }

    @objc func mouseEntered(_ event: NSEvent) { startHoverWatch() }

    private func startHoverWatch() {
        hoverTimer?.invalidate()
        // A button already held when the pointer arrives (a drag from elsewhere) is not a press here.
        buttonWasDown = CGEventSource.buttonState(.hidSystemState, button: .left)
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.pollButton() }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t
    }

    @objc func mouseExited(_ event: NSEvent) { stopHoverWatch() }

    private func stopHoverWatch() {
        hoverTimer?.invalidate(); hoverTimer = nil
        if buttonWasDown, !longPressFired { cancelHold() }
        buttonWasDown = false
    }

    private func pollButton() {
        let down = CGEventSource.buttonState(.hidSystemState, button: .left)
        if down, !buttonWasDown { startHold() }
        buttonWasDown = down
    }

    private func startHold() {
        longPressFired = false
        pressStart = ProcessInfo.processInfo.systemUptime
        pressTimer?.invalidate()
        let t = Timer(timeInterval: Self.longPressDelay, repeats: false) { [weak self] _ in
            // Only a real hold: if the button is already up, the (late) release does a normal click.
            guard CGEventSource.buttonState(.hidSystemState, button: .left) else { return }
            self?.longPressFired = true
            self?.showPopover()
        }
        RunLoop.main.add(t, forMode: .common)
        pressTimer = t
    }

    private func cancelHold() {
        pressTimer?.invalidate(); pressTimer = nil; pressStart = nil
    }

    // Same panel behaviour as Sleepless: a real popover with the little arrow under the icon,
    // the icon gives a springy bounce, and the content springs in.
    private let popover = NSPopover()
    private var clickMonitor: Any?

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        refreshState()
        if popover.contentViewController == nil {
            popover.behavior = .applicationDefined
            popover.animates = true
            // No fixed look: the panel follows the Mac (light or dark) and cross-fades its colours.
            let host = NSHostingController(rootView: QuickPanel(model: model,
                openApp: { [weak self] in self?.closePanel(); self?.showWindow() },
                quit: { [weak self] in self?.quit() }))
            // Size the popover to the panel itself, so the arrow sits right under the icon.
            host.sizingOptions = [.preferredContentSize]
            popover.contentViewController = host
        }
        refreshState()
        bounceIcon()
        PanelGroup.announceOpen()   // close our other apps' panels (the quick switch never gets here)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Don't activate DarkSwitch (that would swap the menu bar to its menus and pull any of its
        // windows forward); a non-activating panel still takes clicks. Set once per window only:
        // changing it again on a live window makes it redraw badly.
        if let panel = popover.contentViewController?.view.window as? NSPanel,
           !panel.styleMask.contains(.nonactivatingPanel) {
            panel.styleMask.insert(.nonactivatingPanel)
        }
        // A view that asks for keys lets the non-activating panel become the key window (so Esc reaches it).
        if let w = popover.contentViewController?.view.window, let c = EscKeyCatcher.current { w.makeFirstResponder(c) }
        popover.contentViewController?.view.window?.makeKey()
        model.openCount += 1
        MenuBarStrip.startEsc(window: { [weak self] in self?.popover.contentViewController?.view.window }, close: { [weak self] in self?.closePanel() })
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if PanelGroup.isOnNoxSwitch() { return }   // Nox's quick dark-mode switch never closes a panel
            self?.closePanel()   // any other click outside (desktop, other apps, any menu bar item) closes it
        }
    }

    private var panelIsShown: Bool { popover.isShown }

    /// Writes the quick switch's screen rectangle for our other menu bar apps (see PanelGroup).
    @objc private func publishToggleFrame() {
        guard let b = statusItem.button, let w = b.window else { return }
        PanelGroup.publishNoxFrame(w.convertToScreen(b.convert(b.bounds, to: nil)))
    }

    private func closePanel() {
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        MenuBarStrip.stopEsc()
        if popover.isShown { popover.performClose(nil) }
    }

    private func bounceIcon() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let b = statusItem.button else { return }
        b.wantsLayer = true
        guard let layer = b.layer else { return }
        let c = CGPoint(x: b.bounds.midX, y: b.bounds.midY)
        var t = CATransform3DMakeTranslation(c.x, c.y, 0)
        t = CATransform3DScale(t, 1.12, 1.12, 1)
        t = CATransform3DTranslate(t, -c.x, -c.y, 0)
        let bounce = CASpringAnimation(keyPath: "transform")
        bounce.fromValue = t
        bounce.toValue = CATransform3DIdentity
        bounce.mass = 1; bounce.stiffness = 320; bounce.damping = 11
        bounce.duration = bounce.settlingDuration
        layer.add(bounce, forKey: "bounce")
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        darkItem.title = "Dark mode"
        darkItem.action = #selector(toggleMacDark as () -> Void)
        darkItem.target = self

        forceItem.title = "Websites follow Mac"
        forceItem.action = #selector(toggleForce)
        forceItem.target = self

        extensionItem.title = "Turn on Safari extension…"
        extensionItem.action = #selector(openExtensionSettings)
        extensionItem.target = self

        let open = NSMenuItem(title: "Settings…", action: #selector(showWindow), keyEquivalent: ",")
        open.target = self
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        [darkItem, forceItem, extensionItem, .separator(), open, quit].forEach { menu.addItem($0) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        darkItem.state = systemIsDark ? .on : .off
        forceItem.state = forceDarkOn ? .on : .off
        extensionItem.isHidden = model.extensionOn == true
        refreshExtensionState()
    }

    // MARK: First-launch setup

    private var onboardingWindow: NSWindow?

    @objc func showOnboarding() {
        if onboardingWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, setup: setupActions, finish: { [weak self] in
                UserDefaults.standard.set(true, forKey: onboardedKey)
                self?.onboardingWindow?.close()
            }))
            w.setContentSize(w.contentView!.fittingSize)
            w.center()
            onboardingWindow = w
        }
        applyDockPolicy()
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private var setupActions: SetupActions {
        SetupActions(
            automationGranted: { Permissions.automationState() },
            requestAutomation: { await Permissions.requestAutomation() },
            openSafari: { [weak self] in self?.openExtensionSettings() },
            setLogin: { [weak self] on in self?.setOpenAtLogin(on) })
    }

    // MARK: Window

    @objc private func showWindow() { presentWindow(activate: true) }

    private func presentWindow(activate: Bool) {
        refreshState()
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            let host = NSHostingController(rootView: MainView(model: model))
            host.sizingOptions = [.preferredContentSize]   // grows and shrinks with the rows shown
            w.contentViewController = host
            w.center()
            window = w
        }
        guard activate else {
            // Scripted (tests and screenshots): show above other windows without taking focus.
            window?.level = .floating
            window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window?.orderFrontRegardless()
            return
        }
        window?.level = .normal
        window?.collectionBehavior = []
        applyDockPolicy()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The window grows when rows appear: keep it fully on screen (top edge stays put when it can).
    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, w === window,
              let visible = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = w.frame
        if f.minY < visible.minY { f.origin.y = visible.minY }
        if f.maxY > visible.maxY { f.origin.y = max(visible.minY, visible.maxY - f.height) }
        if f != w.frame { w.setFrame(f, display: true, animate: false) }
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            UserDefaults.standard.set(true, forKey: onboardedKey)
        }
        let others = [window, onboardingWindow].compactMap { $0 }.filter { $0 !== notification.object as? NSWindow && $0.isVisible }
        guard others.isEmpty else { return }
        applyDockPolicy()
    }

    // MARK: State

    /// Reads the setting fresh every time (the cached copies lag a moment behind a switch,
    /// which made the switches jump back and forth).
    private var systemIsDark: Bool {
        let any = kCFPreferencesAnyApplication
        CFPreferencesAppSynchronize(any)
        if (CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, any) as? String) == "Dark" { return true }
        let auto = CFPreferencesCopyAppValue("AppleInterfaceStyleSwitchesAutomatically" as CFString, any) as? Bool ?? false
        return auto && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// While a switch is under way, this is what the Mac is switching to.
    private var pendingDark: Bool?
    private var shownDark: Bool { pendingDark ?? systemIsDark }

    private var forceDarkOn: Bool {
        UserDefaults.standard.bool(forKey: forceDarkKey)
    }

    private func wireModel() {
        model.toggleDark = { [weak self] in self?.toggleMacDark() }
        model.setForceDark = { [weak self] on in self?.setForceDark(on) }
        model.openExtensionSettings = { [weak self] in self?.openExtensionSettings() }
        model.setOpenAtLogin = { [weak self] on in self?.setOpenAtLogin(on) }
        model.setShowInDock = { [weak self] on in self?.setShowInDock(on) }
        model.setSmoothFade = { [weak self] on in self?.setSmoothFade(on) }
        model.setNightSchedule = { [weak self] on in self?.setNightSchedule(on) }
        model.setTimes = { [weak self] dark, light in self?.setTimes(dark: dark, light: light) }
        model.openSettings = { [weak self] in self?.closePanel(); self?.showWindow() }
    }

    private func refreshState() {
        let d = UserDefaults.standard
        if model.isDark != shownDark { model.isDark = shownDark }
        model.forceDark = forceDarkOn
        model.openAtLogin = SMAppService.mainApp.status == .enabled
        model.showInDock = d.bool(forKey: showInDockKey)
        model.smoothFade = d.bool(forKey: smoothFadeKey)
        model.nightSchedule = d.bool(forKey: scheduleKey)
        model.darkAt = d.integer(forKey: darkAtKey)
        model.lightAt = d.integer(forKey: lightAtKey)
        updateIcon()
        refreshExtensionState()
    }

    private var iconProgress: CGFloat = -1   // 0 = light (knob left), 1 = dark (knob right)
    private var iconTimer: Timer?
    private var iconTarget: CGFloat = -1
    private var iconColorOverride: NSColor?
    private var iconVelocity: CGFloat = 0
    // Spring matching SwiftUI .spring(response: 0.3, dampingFraction: 0.8): k = (2π/r)², c = 4πζ/r.
    private static let springK: CGFloat = pow(2 * .pi / 0.3, 2)
    private static let springC: CGFloat = 4 * .pi * 0.8 / 0.3
    private static let iconAnimationDuration: TimeInterval = 0.32

    private func updateIcon() {
        statusItem.button?.toolTip = "Nox: click to switch. Right-click or Option-click for options"
        animateIcon(to: shownDark ? 1 : 0)
    }

    /// Slides the knob and fades the track fill, matching macOS's own appearance fade.
    private func animateIcon(to target: CGFloat) {
        // Already sliding there: let the running slide finish instead of restarting it (no stutter).
        if iconTimer?.isValid == true, iconTarget == target { return }
        iconTarget = target
        iconTimer?.invalidate()
        if iconProgress < 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            iconProgress = target
            setIcon(progress: target)
            return
        }
        guard iconProgress != target else { return }
        // A real spring (same response and damping as the switches in the panel), stepped every frame.
        var last = CACurrentMediaTime()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = CACurrentMediaTime()
            var dt = min(now - last, 1.0 / 30.0); last = now
            while dt > 0 {   // small sub-steps keep the spring stable
                let h = min(dt, 1.0 / 240.0); dt -= h
                let accel = -Self.springK * (self.iconProgress - target) - Self.springC * self.iconVelocity
                self.iconVelocity += accel * h
                self.iconProgress += self.iconVelocity * h
            }
            if abs(self.iconProgress - target) < 0.002, abs(self.iconVelocity) < 0.02 {
                self.iconProgress = target; self.iconVelocity = 0; timer.invalidate()
            }
            self.setIcon(progress: min(1, max(0, self.iconProgress)))
        }
        RunLoop.main.add(iconTimer!, forMode: .common)
    }

    /// Menu bar toggle: drawn live by a small view on the button. (Swapping the button's picture
    /// every frame made macOS cross-fade the pictures, which left ghost knobs behind.)
    private let iconView = ToggleIconView()

    private func installIconView() {
        guard let button = statusItem.button else { return }
        let blank = NSImage(size: ToggleIconView.size)   // keeps the button the right width
        blank.isTemplate = true
        button.image = blank
        iconView.frame = button.bounds
        iconView.autoresizingMask = [.width, .height]
        button.addSubview(iconView)
    }

    private func setIcon(progress: CGFloat) {
        iconView.progress = progress
        iconView.ink = iconColorOverride
        iconView.needsDisplay = true
        statusItem.button?.image?.accessibilityDescription = progress >= 0.5 ? "Nox: dark" : "Nox: light"
    }

    @objc private func refreshExtensionState() { checkExtension(triesLeft: 4) }

    /// Asks Safari whether the extension is on. Safari sometimes can't answer for a moment (busy,
    /// just reinstalled), so a failed check is retried a few times instead of leaving "Checking".
    private func checkExtension(triesLeft: Int) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionID) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard error == nil, let state else {
                    dlog("safari extension check failed: \(error?.localizedDescription ?? "no state"), tries left \(triesLeft)")
                    // Keep the last known answer and ask again shortly.
                    if triesLeft > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.checkExtension(triesLeft: triesLeft - 1) }
                    } else if self.model.extensionOn == nil {
                        // Still no answer (usually SFErrorDomain 1, "no extension found": Safari clears
                        // "Allow unsigned extensions" each time it quits). Say it's off, with its Turn on
                        // button, rather than "Checking" forever.
                        self.model.extensionOn = false
                        self.extensionItem.isHidden = false
                    }
                    return
                }
                if self.model.extensionOn != state.isEnabled { self.model.extensionOn = state.isEnabled }
                self.extensionItem.isHidden = state.isEnabled
            }
        }
    }

    // MARK: Actions

    @objc private func appearanceChanged() {
        // Dark mode set any other way (Control Centre, System Settings, Apple's Auto) leaves web pages
        // to Safari, exactly like stock macOS.
        let byNox = isSwitching
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NoxDark.apply(.appearanceChanged(byNox: byNox || self.isSwitching, nowDark: self.systemIsDark))
            if !self.isSwitching { self.refreshState() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoxDark.apply(.quitting)
    }

    @objc private func testCommand(_ note: Notification) {
        switch note.object as? String {
        case "toggle": ScreenFade.liftAllForTest = false; toggleMacDark()
        case "togglelive": ScreenFade.liftAllForTest = true; toggleMacDark()   // as if pressed in Settings
        case "panel": if panelIsShown { closePanel() } else { showPopover() }
        case "window": showWindow()
        case "settings": presentWindow(activate: false)   // scripted: show without stealing focus
        case "close":
            closePanel()
            window?.orderOut(nil)
            window?.level = .normal
            applyDockPolicy()
        case "look:light": NSApp.appearance = NSAppearance(named: .aqua)   // app only, for screenshots
        case "look:dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "look:auto": NSApp.appearance = nil
        case "dock:on": setShowInDock(true)
        case "dock:off": setShowInDock(false)
        case let cmd? where cmd.hasPrefix("origin:"):
            // "origin:x,y" moves the window's top-left corner (screen points from the top left).
            let n = cmd.dropFirst(7).split(separator: ",").compactMap { Double($0) }
            if n.count == 2, let w = window, let screen = NSScreen.main {
                w.setFrameTopLeftPoint(NSPoint(x: n[0], y: screen.frame.height - n[1]))
            }
        case "frame":
            // Write the panel and window rectangles (screen points, origin bottom left) for screenshots.
            var lines: [String] = []
            if let f = popover.contentViewController?.view.window?.frame, popover.isShown { lines.append("panel \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))") }
            if let w = window, w.isVisible { let f = w.frame; lines.append("window \(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))") }
            lines.append("screen \(Int(NSScreen.main?.frame.width ?? 0)) \(Int(NSScreen.main?.frame.height ?? 0))")
            try? lines.joined(separator: "\n").write(toFile: "/tmp/nox-frames.txt", atomically: true, encoding: .utf8)
        case "notify": notify("Test: notifications now come from Nox.")
        case "quit": quit()
        case "bigtap": model.toggleDark()
        case let cmd? where cmd.hasPrefix("safarialert:"):
            // "safarialert:signed" / "safarialert:unsigned" / "safarialert:auto" -> /tmp/nox-alert-<kind>.png
            let kind = String(cmd.dropFirst(12))
            SafariSetup.forcedForTest = kind == "signed" ? true : kind == "unsigned" ? false : nil
            snapshotSafariAlert(to: "/tmp/nox-alert-\(kind).png")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { SafariSetup.forcedForTest = nil }
        case let cmd? where cmd.hasPrefix("welcomesnap:"):
            // "welcomesnap:light" / "welcomesnap:dark" -> /tmp/nox-welcome-<look>.png (off-screen)
            // optional page: "welcomesnap:dark:2" -> /tmp/nox-welcome-dark-2.png (pages 0 to 2)
            let bits = cmd.dropFirst(12).split(separator: ":").map(String.init)
            let look = bits.first ?? "light"
            let pg = Int(bits.count > 1 ? bits[1] : "") ?? 0
            NSApp.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)   // this app only, never the Mac
            snapshot(OnboardingView(model: model, setup: setupActions, finish: {}, page: pg), to: "/tmp/nox-welcome-\(look)-\(pg).png")
        case "welcome": showOnboarding()
        case "sharetest": ShareFriend.selfTest(report: "/tmp/nox-share-test.txt")
        case "iconslide":
            // Slide the menu bar knob across and back without switching the Mac (for recordings).
            animateIcon(to: iconTarget >= 0.5 ? 0 : 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.updateIcon() }
        case "iconrender":
            // Draw the menu bar switch at 4x, off and on, on light and dark menu bars -> /tmp/nox-icon-*.png
            // (plus "-selected": the grey pill the menu bar draws behind an open item, and "half" mid-slide)
            for (name, look, bg) in [("light", NSAppearance.Name.aqua, NSColor.white), ("dark", .darkAqua, NSColor.black),
                                     ("light-selected", .aqua, NSColor(white: 0.80, alpha: 1)),
                                     ("dark-selected", .darkAqua, NSColor(white: 0.30, alpha: 1))] {
                for p in [CGFloat(0), 0.5, 1] {
                    let v = ToggleIconView(frame: NSRect(origin: .zero, size: ToggleIconView.size))
                    v.appearance = NSAppearance(named: look)
                    v.progress = p
                    let scale: CGFloat = 4, sz = ToggleIconView.size
                    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sz.width * scale), pixelsHigh: Int(sz.height * scale),
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                    rep.size = sz
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    bg.setFill(); NSRect(origin: .zero, size: sz).fill()
                    v.draw(v.bounds)
                    NSGraphicsContext.restoreGraphicsState()
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "/tmp/nox-icon-\(name)-\(p == 0 ? "off" : p == 1 ? "on" : "half").png"))
                }
            }
        case "fadetest":
            Task { @MainActor in
                let o = await ScreenFade.freezeScreens()
                try? await Task.sleep(nanoseconds: 800_000_000)
                ScreenFade.fadeOut(o)
            }
        default: break
        }
    }

    @objc private func toggleMacDark() { toggleMacDark(fade: true) }

    private func toggleMacDark(fade: Bool) {
        // A press while the last switch is still finishing is kept and run right after, never dropped.
        guard !isSwitching else { queuedToggle = true; dlog("switch: busy, press queued"); return }
        isSwitching = true
        let wantDark = !systemIsDark
        pendingDark = wantDark
        // Noted before the switch, so pages darken together with the Mac.
        NoxDark.apply(.noxSwitching(toDark: wantDark))
        // Only fade once switching is allowed; otherwise Apple's permission window would be hidden
        // under the still picture.
        // (A switch that worked before proves permission too: Apple's check can answer "not sure".)
        let allowed = Permissions.automationState() == true || UserDefaults.standard.bool(forKey: "switchWorked")
        let fading = fade && UserDefaults.standard.bool(forKey: smoothFadeKey) && allowed
        dlog("fade: wanted=\(UserDefaults.standard.bool(forKey: smoothFadeKey)) allowed=\(allowed)")
        let barIsDark = statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Slide the menu bar switch and update the panel's title at the same moment as its switch.
        animateIcon(to: wantDark ? 1 : 0)
        model.isDark = wantDark
        let started = CACurrentMediaTime()
        Task { @MainActor in
            let overlays = fading ? await ScreenFade.freezeScreens(keepLive: self.statusItem.button?.window?.frame) : []
            // The bar behind the icon stays frozen in the old look until the fade, so the icon keeps
            // its current colour until then instead of flipping early (only when there is a picture).
            if !overlays.isEmpty { self.iconColorOverride = barIsDark ? .white : .black }
            // macOS freezes and cross-fades the whole menu bar while it changes look, which caught
            // the knob mid-slide (two ghost knobs). Let the knob finish its slide first.
            let waited = CACurrentMediaTime() - started
            if waited < Self.knobSlideTime {
                try? await Task.sleep(nanoseconds: UInt64((Self.knobSlideTime - waited) * 1_000_000_000))
            }
            let ok = await self.switchAppearance(dark: wantDark)
            if ok { UserDefaults.standard.set(true, forKey: "switchWorked") }
            // macOS repaints a moment after it says yes: keep the picture up until it really has.
            if ok, !overlays.isEmpty { await ScreenFade.waitForRepaint(dark: wantDark, overlays: overlays) }
            ScreenFade.fadeOut(overlays)
            // Halfway through the fade, hand the icon back to the system colour of the new bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + (overlays.isEmpty ? 0 : 0.45)) {
                self.iconColorOverride = nil
                self.setIcon(progress: self.iconProgress)
            }
            if !ok {
                NoxDark.apply(.noxSwitchFailed)
                NoxDark.intent = !wantDark
                self.pendingDark = nil
                self.animateIcon(to: wantDark ? 0 : 1)
                self.model.isDark = !wantDark
                if !self.lastSwitchTimedOut { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {   // after the picture is gone
                    self.alert("Nox needs permission to switch dark mode",
                               "Open System Settings, Privacy & Security, Automation, and allow Nox to control System Events. Then try again.")
                } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                self.isSwitching = false
                self.pendingDark = nil
                self.refreshState()
                if self.queuedToggle { self.queuedToggle = false; self.toggleMacDark(fade: true) }
            }
        }
    }

    private var isSwitching = false
    private var queuedToggle = false
    /// System Events hung (not a permission problem): don't show the permission alert.
    private var lastSwitchTimedOut = false
    private static let knobSlideTime: CFTimeInterval = 0.36


    private static let scriptQueue = DispatchQueue(label: "DarkSwitch.appearance")

    /// Runs the switch off the main thread, so animations keep running smoothly while macOS changes over.
    private func switchAppearance(dark: Bool) async -> Bool {
        let script = """
        tell application "System Events" to tell appearance preferences to set dark mode to \(dark ? "true" : "false")
        """
        // If System Events hangs (it sometimes does while other apps use it), give up after a few
        // seconds instead of waiting forever: a still picture left on screen would freeze the Mac.
        lastSwitchTimedOut = false
        let failed: Bool = await withCheckedContinuation { done in
            let once = OnceFlag()
            Self.scriptQueue.async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                if once.claim() { done.resume(returning: error != nil) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if once.claim() {
                    dlog("switch: System Events did not answer in 4 s")
                    self.lastSwitchTimedOut = true
                    done.resume(returning: true)
                }
            }
        }
        return !failed
    }

    @objc private func toggleForce() {
        setForceDark(!forceDarkOn)
    }

    private func setForceDark(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: forceDarkKey)
        model.forceDark = on
    }

    @objc private func openExtensionSettings() {
        // A copy built on this Mac is unsigned as far as Safari is concerned: Safari only lists it
        // after "Allow unsigned extensions" is ticked, and clears that tick every time it quits.
        // The Developer ID release is listed straight away. SafariSetup has the right steps.
        closePanel()
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { error in
            DispatchQueue.main.async {
                guard error != nil else { return }   // Safari opened straight on Nox's settings
                dlog("safari: could not open Nox's settings directly: \(error!.localizedDescription)")
                self.showSafariSteps()
            }
        }
    }

    private var safariStepsWindow: NSWindow?

    /// The steps to turn Nox on in Safari, with a button that opens Safari's extension settings.
    private func showSafariSteps() {
        safariStepsWindow?.close()
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.title = SafariSetup.title
        w.contentView = NSHostingView(rootView: SafariStepsView(
            openSafari: { [weak self] in self?.safariStepsWindow?.close(); self?.openSafariForSteps() },
            close: { [weak self] in self?.safariStepsWindow?.close() }))
        w.setContentSize(w.contentView!.fittingSize)
        w.center()
        safariStepsWindow = w
        NSApp.activate(ignoringOtherApps: true)   // only ever after you click Turn on
        w.makeKeyAndOrderFront(nil)
    }

    private func openSafariForSteps() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionID) { error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                // Nox isn't listed yet (unsigned copy): open Safari so the steps can be followed.
                if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                    NSWorkspace.shared.openApplication(at: safari, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }

    /// Tests: draws the Safari steps (or the welcome window) into a picture off-screen, without
    /// showing anything or taking focus.
    private func snapshotSafariAlert(to path: String) {
        snapshot(SafariStepsView(openSafari: {}, close: {}), to: path)
    }

    private func snapshot(_ view: some View, to path: String) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSApp.appearance
        let size = host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: size.width, height: size.height),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.appearance = NSApp.appearance
        w.contentView = host
        w.orderBack(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {   // let the springs settle
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            w.orderOut(nil)
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            alert("Could not change Open at login", error.localizedDescription)
        }
        model.openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Dock icon only when chosen in Settings. Off (the default), Nox lives in the menu bar alone,
    /// even while its window is open, so it can't be quit from the Dock by accident.
    private func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = UserDefaults.standard.bool(forKey: showInDockKey) ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private func setShowInDock(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: showInDockKey)
        model.showInDock = on
        applyDockPolicy()
        // Leaving the Dock hides the app's windows on some macOS versions: keep Settings in front.
        if !on, let w = window, w.isVisible { DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil) } }
    }

    private func setSmoothFade(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: smoothFadeKey)
        model.smoothFade = on
    }

    // MARK: Dark at night

    private var scheduleTimer: Timer?
    private var lastNight: Bool?

    private func startSchedule() {
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.checkSchedule() }
        RunLoop.main.add(t, forMode: .common)
        scheduleTimer = t
        // Not forced: opening Nox only notes whether it is night now and leaves the Mac exactly as it is.
        // It switches later, when the clock crosses a set time (forcing here flipped the Mac on every launch).
        checkSchedule()
    }

    private func setNightSchedule(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: scheduleKey)
        model.nightSchedule = on
        checkSchedule(force: true)
    }

    private func setTimes(dark: Int, light: Int) {
        UserDefaults.standard.set(dark, forKey: darkAtKey)
        UserDefaults.standard.set(light, forKey: lightAtKey)
        model.darkAt = dark; model.lightAt = light
        checkSchedule(force: true)
    }

    /// Switches only when the clock crosses a set time, so flipping by hand in between sticks.
    private func checkSchedule(force: Bool = false) {
        let d = UserDefaults.standard
        guard d.bool(forKey: scheduleKey) else { lastNight = nil; return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let dark = d.integer(forKey: darkAtKey), light = d.integer(forKey: lightAtKey)
        let night = dark > light ? (m >= dark || m < light) : (m >= dark && m < light)
        defer { lastNight = night }
        guard force || (lastNight != nil && lastNight != night) else { return }
        if night != systemIsDark, !isSwitching {
            toggleMacDark()
            notify(night ? "Dark mode on for the night." : "Good morning: light mode is back on.")
        }
    }

    /// A notification from Nox itself (its own name and icon).
    private func notify(_ message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Nox"
            content.body = message
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Fold the panel away with its normal close animation first, then quit.
    @objc private func quit() {
        guard popover.isShown else { NSApp.terminate(nil); return }
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { NSApp.terminate(nil) }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

/// The menu bar switch itself: an outlined pill whose knob slides left (light) to right (dark).
final class ToggleIconView: NSView {
    static let size = NSSize(width: 26, height: 16)
    var progress: CGFloat = 0
    var ink: NSColor?   // fixed colour while the screen fade runs; nil = follow the menu bar

    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks go to the button

    override func draw(_ dirtyRect: NSRect) {
        let s = Self.size
        let rect = NSRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2,
                          width: s.width, height: s.height)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let barIsDark = ink.map { $0 == .white } ?? (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            let color = ink ?? (barIsDark ? .white : .black)
            // On: Nox's purple (the same violet as the Settings switches for this look), with a
            // white knob. The colour fades in and out with the knob's position, so it follows the
            // slide exactly; at 0 it is the plain menu bar look.
            let p = min(1, max(0, progress))
            let accent = barIsDark ? Self.violetDark : Self.violetLight
            let edge = Self.mix(color, accent, p)
            let track = rect.insetBy(dx: 1.5, dy: 1.5)
            let pill = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
            if p > 0 {
                accent.withAlphaComponent(p).setFill()
                pill.fill()
            }
            edge.setStroke()
            pill.lineWidth = 1.5
            pill.stroke()
            // Knob flush with the inside edge of the outline (the stroke is centred on the path,
            // so its inside edge is half the line width in). It tucks 0.35 pt under the outline so
            // no faint seam shows between the two at Retina scale.
            let inset = pill.lineWidth / 2 - 0.35
            let d = track.height - 2 * inset
            let x = (track.minX + inset) + (track.maxX - d - inset - (track.minX + inset)) * p
            Self.mix(color, .white, p).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: track.minY + inset, width: d, height: d)).fill()
        }
    }

    // NoxTheme.dark.violet and NoxTheme.light.violet.
    private static let violetDark = NSColor(srgbRed: 0.55, green: 0.45, blue: 1.0, alpha: 1)
    private static let violetLight = NSColor(srgbRed: 0.45, green: 0.33, blue: 0.93, alpha: 1)

    private static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return t < 0.5 ? a : b }
        func l(_ p: CGFloat, _ q: CGFloat) -> CGFloat { p + (q - p) * t }
        return NSColor(srgbRed: l(x.redComponent, y.redComponent), green: l(x.greenComponent, y.greenComponent),
                       blue: l(x.blueComponent, y.blueComponent), alpha: l(x.alphaComponent, y.alphaComponent))
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Lets exactly one of several racing callers through (used to time out a hung script).
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}
