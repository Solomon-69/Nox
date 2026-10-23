import Cocoa
import ScreenCaptureKit

/// Makes the light/dark switch fade across every open app, the way the wallpaper does:
/// a still picture of each screen covers everything, the Mac switches underneath, and the
/// picture fades away. Needs Screen Recording permission; without it the switch is instant.
@MainActor
enum ScreenFade {
    private static let duration: TimeInterval = 0.6
    /// Extra settle time after the Mac says the look changed, so every app has repainted
    /// before the still picture starts to fade (no light patches left among dark ones).
    private static let settle: TimeInterval = 0.4
    private static var askedForPermission = false
    /// DarkSwitch's own windows, lifted above the still picture while it fades, with their old levels.
    private static var lifted: [(NSWindow, NSWindow.Level)] = []
    /// DarkSwitch's own windows held in the old look until the fade reaches them.
    private static var pinned: [NSWindow] = []
    /// Tests only: treat every visible DarkSwitch window as one you're using (lifted and live),
    /// so the "pressed in Settings" case can be checked without taking focus from other apps.
    nonisolated(unsafe) static var liftAllForTest = false

    static func freezeScreens(keepLive hole: NSRect? = nil) async -> [NSWindow] {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return [] }
        guard CGPreflightScreenCaptureAccess() else {
            dlog("fade: no Screen Recording permission")
            if !askedForPermission {
                askedForPermission = true
                CGRequestScreenCaptureAccess()
            }
            return []
        }
        guard #available(macOS 14.0, *) else { return [] }
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        catch { dlog("fade: screen list failed: \(error)"); return [] }

        // Keep every DarkSwitch window live and out of the still picture (the menu bar switch, the
        // panel, the main window), so its switches slide in step instead of freezing and jumping.
        // Popovers already float above everything and are never moved; the rest are lifted above it.
        // Only windows you're using: a Settings window hidden behind other apps stays put.
        // A Settings window sitting behind other apps stays where it is (lifting it made it pop up).
        let live = NSApp.windows.filter {
            $0.isVisible && (String(describing: type(of: $0)).contains("Popover")
                || liftAllForTest
                || ($0.isKeyWindow && NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid()))
        }
        let popovers = live.filter { String(describing: type(of: $0)).contains("Popover") }
        // Leave the whole app out of the picture (matching window numbers one by one crashed),
        // unless one of its windows stays under the picture (a Settings window behind other apps):
        // then it must be in the picture, or it would vanish while the picture is up.
        let stayingUnder = NSApp.windows.filter {
            let kind = String(describing: type(of: $0))
            return $0.isVisible && !live.contains($0) && !kind.contains("StatusBar") && !kind.contains("Popover")
        }
        let me = stayingUnder.isEmpty ? content.applications.filter { $0.processID == getpid() } : []
        // Sit just under any open popover; otherwise right at the top.
        let floor = NSWindow.Level.statusBar.rawValue + 1   // must cover every app and the menu bar
        // (With no popover open, the picture goes at screen-saver height: an empty list used to give
        // an impossible level, so macOS never showed the picture and the fade never happened.)
        let popLevel = popovers.map { $0.level.rawValue }.min()
        let underPopover = popLevel.map { $0 > floor + 1 } ?? false
        // Just below pop-up menus and popovers (any app's), still above every window and the menu bar,
        // so other apps' open popovers and menus stay visible and live during the fade.
        let belowPopovers = NSWindow.Level.popUpMenu.rawValue - 1
        let level = NSWindow.Level(rawValue: underPopover ? min(belowPopovers, popLevel! - 1) : belowPopovers)
        let liftable = underPopover ? live.filter { !popovers.contains($0) } : live
        var windows: [NSWindow] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image: CGImage
            do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
            catch { dlog("fade: capture failed: \(error)"); continue }
            windows.append(overlay(image, on: screen, level: level, hole: hole))
        }
        dlog("fade: covered \(windows.count) screen(s), level \(level.rawValue)")
        if !windows.isEmpty {
            lifted = liftable.map { ($0, $0.level) }
            lifted.forEach { $0.0.level = NSWindow.Level(rawValue: level.rawValue + 1) }
            holdOwnLook(except: windows)
        }
        return windows
    }

    /// macOS says "done" before apps have repainted (some, like the Claude app, take over a
    /// second, and each window repaints at its own moment). Keep the picture up until our own look
    /// has flipped AND the live screen underneath has stopped changing, so no window is still
    /// half-way when the picture starts to fade (no light patches among dark ones).
    static func waitForRepaint(dark: Bool, overlays: [NSWindow]) async {
        let flipped = { (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) == dark }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, !flipped() {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        let flippedAt = Date()
        let minWait = 0.45, maxWait = 1.6, quiet = 0.30
        guard #available(macOS 14.0, *), CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.current, let display = content.displays.first else {
            try? await Task.sleep(nanoseconds: 900_000_000); return
        }
        // Look at the live screen with the still picture left out of view.
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
    private static func grid(_ image: CGImage) -> [UInt8]? {
        let w = 16, h = 10
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let d = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: d.assumingMemoryBound(to: UInt8.self), count: w * h))
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
                windows.forEach { $0.alphaValue = CGFloat(1 - eased) }
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

    private static func overlay(_ image: CGImage, on screen: NSScreen, level: NSWindow.Level, hole: NSRect?) -> NSWindow {
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
        w.animationBehavior = .none      // appear instantly, no zoom/fade of its own
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // A plain layer holding the picture: nothing redraws it when the Mac changes appearance,
        // so the fade can't be cut short.
        w.appearance = NSAppearance(named: .aqua)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layerContentsRedrawPolicy = .never
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        // Cut the menu bar switch out of the picture, so the live switch slides on its own
        // instead of showing the old knob and the new one at once.
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

/// The still picture: a panel that never becomes key or main, so showing it never activates Nox
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
