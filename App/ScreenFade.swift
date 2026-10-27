import Cocoa

/// Softens the light/dark switch across every open app WITHOUT looking at the screen: a plain
/// veil in the old look's colour eases in over everything, the Mac switches underneath, and the
/// veil eases away. Nothing is captured, so Nox never needs (or asks for) Screen Recording.
@MainActor
enum ScreenFade {
    private static let duration: TimeInterval = 0.55
    /// How far the veil covers the screen at its peak (1 = fully opaque).
    private static let peak: CGFloat = 0.6
    private static let rampIn: TimeInterval = 0.14
    /// Extra settle time after our own look flips, so other apps have repainted underneath.
    private static let settle: TimeInterval = 0.35
    /// DarkSwitch's own windows, lifted above the veil while it fades, with their old levels.
    private static var lifted: [(NSWindow, NSWindow.Level)] = []
    /// DarkSwitch's own windows held in the old look until the fade reaches them.
    private static var pinned: [NSWindow] = []
    /// Tests only: treat every visible DarkSwitch window as one you're using (lifted and live).
    nonisolated(unsafe) static var liftAllForTest = false

    /// Shows the veil on every screen and returns its windows (empty when Reduce Motion is on).
    static func freezeScreens(keepLive hole: NSRect? = nil) async -> [NSWindow] {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return [] }
        let live = NSApp.windows.filter {
            $0.isVisible && (String(describing: type(of: $0)).contains("Popover")
                || liftAllForTest
                || ($0.isKeyWindow && NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()))
        }
        let popovers = live.filter { String(describing: type(of: $0)).contains("Popover") }
        let floor = NSWindow.Level.statusBar.rawValue + 1
        let popLevel = popovers.map { $0.level.rawValue }.min()
        let underPopover = popLevel.map { $0 > floor + 1 } ?? false
        // Just below pop-up menus and popovers (any app's), still above every window and the menu bar.
        let belowPopovers = NSWindow.Level.popUpMenu.rawValue - 1
        let level = NSWindow.Level(rawValue: underPopover ? min(belowPopovers, popLevel! - 1) : belowPopovers)
        let liftable = underPopover ? live.filter { !popovers.contains($0) } : live
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = dark ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor(calibratedWhite: 0.97, alpha: 1)
        let windows = NSScreen.screens.map { veil(tint, on: $0, level: level, hole: hole) }
        dlog("fade: veil on \(windows.count) screen(s), level \(level.rawValue)")
        lifted = liftable.map { ($0, $0.level) }
        lifted.forEach { $0.0.level = NSWindow.Level(rawValue: level.rawValue + 1) }
        holdOwnLook(except: windows)
        await step(windows, from: 0, to: peak, over: rampIn)
        return windows
    }

    /// macOS says "done" before apps have repainted: wait until our own look has flipped, then a
    /// short settle, so the veil lifts on a finished screen.
    static func waitForRepaint(dark: Bool, overlays: [NSWindow]) async {
        let flipped = { (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) == dark }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, !flipped() {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
    }

    /// Moves the veil's transparency by hand each frame (system animations get cut short by the switch).
    private static func step(_ windows: [NSWindow], from a: CGFloat, to b: CGFloat, over time: TimeInterval) async {
        let start = CACurrentMediaTime()
        while true {
            let p = min(1, (CACurrentMediaTime() - start) / time)
            windows.forEach { $0.alphaValue = a + (b - a) * CGFloat(p) }
            if p >= 1 { return }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    /// Keeps DarkSwitch's own windows in the current look while the Mac switches underneath, so
    /// they don't run ahead of the picture; the fade's clock then moves them over (fadeOut).
    private static func holdOwnLook(except overlays: [NSWindow]) {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        pinned = NSApp.windows.filter {
            $0.isVisible && $0.appearance == nil && !overlays.contains($0)
                && !String(describing: type(of: $0)).contains("StatusBar")
        }
        pinned.forEach { $0.appearance = NSAppearance(named: dark ? .darkAqua : .aqua) }
        NoxLook.shared.mix = dark ? 1 : 0
    }

    private static func releaseOwnLook() {
        pinned.forEach { $0.appearance = nil }
        pinned = []
    }

    static func fadeOut(_ windows: [NSWindow]) {
        guard !windows.isEmpty else { releaseOwnLook(); NoxLook.shared.mix = nil; return }
        // Give apps a moment to redraw in the new appearance before revealing them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Step the picture's transparency by hand every frame: animations handed to the system
            // were cut short by the Mac's own redraw during the switch.
            // Nox's own windows move from the old look to the new one on this same clock.
            let from = NoxLook.shared.mix ?? 0
            let to: CGFloat = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0
            let start = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { t in
                let p = min(1, (CACurrentMediaTime() - start) / duration)
                let eased = 1 - pow(1 - p, 3)   // ease out: starts moving at once, settles softly
                windows.forEach { $0.alphaValue = peak * CGFloat(1 - eased) }
                NoxLook.shared.mix = from + (to - from) * CGFloat(eased)
                // Early on, hand the window frames (buttons, borders) to the new look as well.
                if eased >= 0.5, !pinned.isEmpty { releaseOwnLook() }
                guard p >= 1 else { return }
                t.invalidate()
                windows.forEach { $0.orderOut(nil) }
                lifted.forEach { $0.0.level = $0.1 }
                lifted = []
                releaseOwnLook()
                NoxLook.shared.mix = nil
                liftAllForTest = false
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func veil(_ tint: NSColor, on screen: NSScreen, level: NSWindow.Level, hole: NSRect?) -> NSWindow {
        let w = FadePanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.level = level
        w.ignoresMouseEvents = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.alphaValue = 0
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        view.layer?.backgroundColor = tint.cgColor
        // Leave the whole menu bar uncovered: macOS changes it with its own cross-fade, and a veil over it with only the
        // switch cut out left the icon isolated in a box with bars either side while the bar changed look.
        let barH = screen.frame.maxY - screen.visibleFrame.maxY
        if barH > 0 || hole != nil {
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: screen.frame.size))
            if barH > 0 { path.addRect(CGRect(x: 0, y: screen.frame.height - barH, width: screen.frame.width, height: barH)) }
            if let hole, screen.frame.intersects(hole) { path.addRect(hole.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)) }
            let mask = CAShapeLayer()
            mask.path = path
            mask.fillRule = .evenOdd
            view.layer?.mask = mask
        }
        w.contentView = view
        w.setFrame(screen.frame, display: false)
        w.orderFrontRegardless()
        return w
    }
}

/// The veil: a panel that never becomes key or main, so showing it never activates Nox
/// and never closes another app's open popover.
final class FadePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Notes for troubleshooting, kept in ~/Library/Logs/DarkSwitch.log.
func dlog(_ text: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DarkSwitch.log")
    let line = "\(Date()) \(text)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}
