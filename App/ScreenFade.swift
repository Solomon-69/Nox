import Cocoa
import ScreenCaptureKit

/// Softens the light/dark switch across every open app. Two ways, picked each time:
/// - Picture fade (when Screen Recording is ALREADY allowed): a still picture of each screen,
///   menu bar included, covers everything, the Mac switches underneath, and the picture fades away.
/// - Veil fade (otherwise): a plain veil in the old look's colour eases in and away.
/// Nox never asks for Screen Recording by itself; Settings only offers a button to open the pane.
@MainActor
enum ScreenFade {
    private static let duration: TimeInterval = 0.55
    private static let pictureDuration: TimeInterval = 0.6
    /// True while the current fade is the still picture (fully opaque at the start).
    nonisolated(unsafe) private static var usingPicture = false
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
        usingPicture = false
        // Only checks; never shows Apple's permission request.
        if pictureAllowed {
            let pics = await pictureScreens(hole: hole)
            if !pics.isEmpty { usingPicture = true; return pics }
            dlog("fade: picture failed, using the veil")
        }
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

    /// Screen Recording already allowed (checked silently, no pop-up) on a Mac that can take the picture.
    nonisolated static var pictureAllowed: Bool {
        guard #available(macOS 14.0, *) else { return false }
        return CGPreflightScreenCaptureAccess()
    }

    /// Covers each screen with a still picture of itself, menu bar and Nox's own switch included,
    /// so the whole screen fades as one (no live cut-out or box around the switch).
    private static func pictureScreens(hole: NSRect?) async -> [NSWindow] {
        guard #available(macOS 14.0, *) else { return [] }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { dlog("fade: screen list failed: \(error)"); return [] }
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
        var windows: [NSWindow] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            // Nothing left out: the menu bar switch is in the picture, so it fades with everything else.
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image: CGImage
            do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
            catch { dlog("fade: capture failed: \(error)"); continue }
            windows.append(pictureWindow(image, on: screen, level: level))
        }
        guard !windows.isEmpty else { return [] }
        dlog("fade: picture on \(windows.count) screen(s), level \(level.rawValue)")
        lifted = liftable.map { ($0, $0.level) }
        lifted.forEach { $0.0.level = NSWindow.Level(rawValue: level.rawValue + 1) }
        holdOwnLook(except: windows)
        return windows
    }

    /// macOS says "done" before apps have repainted: wait until our own look has flipped, then
    /// (picture) until the live screen underneath stops changing, or (veil) a short settle.
    static func waitForRepaint(dark: Bool, overlays: [NSWindow]) async {
        let flipped = { (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) == dark }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, !flipped() {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        if usingPicture, #available(macOS 14.0, *) { await waitForQuietScreen(overlays: overlays); return }
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
    }

    /// Watches a tiny view of the live screen (picture left out) until it stops changing.
    @available(macOS 14.0, *)
    private static func waitForQuietScreen(overlays: [NSWindow]) async {
        let flippedAt = Date()
        let minWait = 0.45, maxWait = 1.6, quiet = 0.30
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.current, let display = content.displays.first else {
            try? await Task.sleep(nanoseconds: 900_000_000); return
        }
        let ids = Set(overlays.map { CGWindowID($0.windowNumber) })
        let hidden = content.windows.filter { ids.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: hidden)
        let config = SCStreamConfiguration()
        config.width = 64; config.height = 40; config.showsCursor = false
        var previous: [UInt8]?
        var quietSince: Date?
        while Date().timeIntervalSince(flippedAt) < maxWait {
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
               let now = grid(img) {
                if let prev = previous {
                    // Still counts as quiet if at most one cell (a spinner, a clock) keeps moving.
                    let moving = zip(now, prev).filter { abs(Int($0) - Int($1)) > 4 }.count
                    if moving <= 1 { quietSince = quietSince ?? Date() } else { quietSince = nil }
                }
                previous = now
                if let q = quietSince, Date().timeIntervalSince(q) >= quiet,
                   Date().timeIntervalSince(flippedAt) >= minWait { break }
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        dlog("fade: screen settled after \(String(format: "%.2f", Date().timeIntervalSince(flippedAt))) s")
    }

    /// Brightness of the screen on a coarse 16 x 10 grid.
    static func grid(_ image: CGImage) -> [UInt8]? {
        let w = 16, h = 10
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let d = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: d.assumingMemoryBound(to: UInt8.self), count: w * h))
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
            let startAlpha: CGFloat = usingPicture ? 1 : peak
            let length = usingPicture ? pictureDuration : duration
            let to: CGFloat = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0
            let start = CACurrentMediaTime()
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { t in
                let p = min(1, (CACurrentMediaTime() - start) / length)
                let eased = 1 - pow(1 - p, 3)   // ease out: starts moving at once, settles softly
                windows.forEach { $0.alphaValue = startAlpha * CGFloat(1 - eased) }
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
                usingPicture = false
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private static func pictureWindow(_ image: CGImage, on screen: NSScreen, level: NSWindow.Level) -> NSWindow {
        let w = panel(on: screen, level: level)
        // A plain layer holding the picture: nothing redraws it when the Mac changes look,
        // so the fade can't be cut short.
        w.appearance = NSAppearance(named: .aqua)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        w.contentView = view
        w.alphaValue = 1
        w.setFrame(screen.frame, display: false)
        w.orderFrontRegardless()
        return w
    }

    /// A see-through, click-through panel over one whole screen that never activates Nox.
    private static func panel(on screen: NSScreen, level: NSWindow.Level) -> FadePanel {
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
        return w
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
        // Cut the menu bar switch out of the veil, so the live switch stays crisp while it slides.
        if let hole, screen.frame.intersects(hole) {
            let local = hole.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: screen.frame.size))
            path.addRect(local)
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

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Notes for troubleshooting, kept in ~/Library/Logs/DarkSwitch.log.
func dlog(_ text: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DarkSwitch.log")
    let line = "\(Date()) \(text)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}
