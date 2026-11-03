import Cocoa

/// Softens the light/dark switch across every open app. Nox never uses or asks for Screen Recording.
/// Two ways, picked each time:
/// - Cross-fade: macOS's own window server holds the screen as it is (menu bar included), the Mac
///   switches underneath, then the window server cross-fades to the new look. Nox never sees the
///   screen: the window server keeps the picture to itself, so no permission is involved.
/// - Veil (if the cross-fade isn't available on this Mac): a soft veil in the old look's
///   background colour eases in over the whole screen and eases away once apps have repainted.
@MainActor
enum ScreenFade {
    private enum Mode { case none, crossFade(Int32), veil([NSWindow]) }
    private static var mode: Mode = .none

    /// Cross-fade length once macOS has repainted.
    private static let crossFadeLength: Float = 0.5
    /// If the switch itself hangs, let go of the held screen after this long.
    private static let holdLimit: TimeInterval = 2.5
    /// Veil: how far it covers the screen at its peak (1 = fully opaque), and its timings.
    private static let peak: CGFloat = 0.82
    private static let rampIn: TimeInterval = 0.12
    private static let veilOut: TimeInterval = 0.5
    /// Extra settle time after our own look flips, so other apps have repainted underneath.
    private static let settle: TimeInterval = 0.38
    /// DarkSwitch's own windows, lifted above the veil while it fades, with their old levels.
    private static var lifted: [(NSWindow, NSWindow.Level)] = []
    /// DarkSwitch's own windows held in the old look until the veil fade reaches them.
    private static var pinned: [NSWindow] = []
    /// Tests only: treat every visible DarkSwitch window as one you're using (lifted and live).
    nonisolated(unsafe) static var liftAllForTest = false

    /// True while the veil (not the cross-fade) is up.
    static var isVeil: Bool { if case .veil = mode { return true }; return false }

    /// Starts the fade before the switch. Returns false when there is no fade (Reduce Motion).
    static func freezeScreens() async -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        if let handle = WindowServerFade.hold() {
            mode = .crossFade(handle)
            dlog("fade: cross-fade holding the screen")
            // Never leave the screen held: if the switch hangs, let go anyway.
            DispatchQueue.main.asyncAfter(deadline: .now() + holdLimit) {
                if case .crossFade(let h) = mode, h == handle { dlog("fade: hold limit reached"); fadeOut() }
            }
            return true
        }
        dlog("fade: cross-fade not available, using the veil")
        let windows = await showVeil()
        mode = windows.isEmpty ? .none : .veil(windows)
        return !windows.isEmpty
    }

    /// macOS says "done" before apps have repainted: wait until our own look has flipped,
    /// then a short settle so other apps have caught up underneath.
    static func waitForRepaint(dark: Bool) async {
        let flipped = { (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua) == dark }
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline, !flipped() {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
    }

    static func fadeOut() {
        switch mode {
        case .none:
            releaseOwnLook(); NoxLook.shared.mix = nil
        case .crossFade(let handle):
            mode = .none
            WindowServerFade.crossFade(handle, over: crossFadeLength)
            liftAllForTest = false
        case .veil(let windows):
            mode = .none
            fadeVeil(windows)
        }
    }

    // MARK: Veil

    private static func showVeil() async -> [NSWindow] {
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
        let tint = oldBackground()
        let windows = NSScreen.screens.map { veil(tint, on: $0, level: level) }
        dlog("fade: veil on \(windows.count) screen(s), level \(level.rawValue)")
        lifted = liftable.map { ($0, $0.level) }
        lifted.forEach { $0.0.level = NSWindow.Level(rawValue: level.rawValue + 1) }
        holdOwnLook(except: windows)
        await step(windows, to: peak, over: rampIn)
        return windows
    }

    /// The current (old) look's window background, so the veil reads as the old screen fading.
    private static func oldBackground() -> NSColor {
        var color = NSColor.windowBackgroundColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? color
        }
        return color
    }

    /// Soft ease in and out (no jump at the start or the end).
    private static func ease(_ p: Double) -> CGFloat { CGFloat(p * p * (3 - 2 * p)) }

    /// Moves the veil's transparency by hand each frame (system animations get cut short by the switch).
    private static func step(_ windows: [NSWindow], to b: CGFloat, over time: TimeInterval) async {
        let start = CACurrentMediaTime()
        while true {
            let p = min(1, (CACurrentMediaTime() - start) / time)
            windows.forEach { $0.alphaValue = b * ease(p) }
            if p >= 1 { return }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    private static func fadeVeil(_ windows: [NSWindow]) {
        // Nox's own windows move from the old look to the new one on this same clock.
        let from = NoxLook.shared.mix ?? 0
        let to: CGFloat = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 1 : 0
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { t in
            let p = min(1, (CACurrentMediaTime() - start) / veilOut)
            let e = ease(p)
            windows.forEach { $0.alphaValue = peak * (1 - e) }
            NoxLook.shared.mix = from + (to - from) * e
            if e >= 0.5, !pinned.isEmpty { releaseOwnLook() }
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

    /// Keeps DarkSwitch's own windows in the current look while the Mac switches underneath the
    /// veil; the veil's clock then moves them over.
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

    /// One whole-screen veil, menu bar included (no cut-out), click-through, never activates Nox.
    private static func veil(_ tint: NSColor, on screen: NSScreen, level: NSWindow.Level) -> NSWindow {
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
        w.contentView = view
        w.setFrame(screen.frame, display: false)
        w.orderFrontRegardless()
        return w
    }
}

/// macOS's own screen cross-fade, done entirely inside the window server (the same one macOS uses
/// for its own transitions). Nox never receives a picture of the screen, so no permission is
/// needed. These calls aren't public: they're looked up at run time, and if any is missing or
/// fails, Nox uses the veil instead.
enum WindowServerFade {
    /// Matches the window server's transition description: fade over the whole screen.
    private struct Spec { var unused: UInt32 = 0; var type: Int32 = 1; var option: Int32 = 0; var window: UInt32 = 0; var colour: UnsafeMutablePointer<Float>? = nil }
    private typealias ConnFn = @convention(c) () -> Int32
    private typealias NewFn = @convention(c) (Int32, UnsafeRawPointer, UnsafeMutablePointer<Int32>) -> Int32
    private typealias InvokeFn = @convention(c) (Int32, Int32, Float) -> Int32
    private typealias ReleaseFn = @convention(c) (Int32, Int32) -> Int32

    private struct Calls { let conn: ConnFn; let new: NewFn; let invoke: InvokeFn; let release: ReleaseFn }

    private static let calls: Calls? = {
        guard MemoryLayout<Spec>.size == 24,
              let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let c = dlsym(lib, "SLSMainConnectionID"), let n = dlsym(lib, "SLSNewTransition"),
              let i = dlsym(lib, "SLSInvokeTransition"), let r = dlsym(lib, "SLSReleaseTransition")
        else { return nil }
        return Calls(conn: unsafeBitCast(c, to: ConnFn.self), new: unsafeBitCast(n, to: NewFn.self),
                     invoke: unsafeBitCast(i, to: InvokeFn.self), release: unsafeBitCast(r, to: ReleaseFn.self))
    }()

    /// Holds the screen as it is right now. Returns a handle, or nil if not available.
    static func hold() -> Int32? {
        guard let calls else { return nil }
        var spec = Spec()
        var handle: Int32 = 0
        let err = withUnsafePointer(to: &spec) { calls.new(calls.conn(), UnsafeRawPointer($0), &handle) }
        guard err == 0, handle != 0 else { dlog("fade: cross-fade refused (\(err))"); return nil }
        return handle
    }

    /// Cross-fades from the held screen to the live one, then tidies up.
    static func crossFade(_ handle: Int32, over seconds: Float) {
        guard let calls else { return }
        let cid = calls.conn()
        let err = calls.invoke(cid, handle, seconds)
        if err != 0 { dlog("fade: cross-fade invoke failed (\(err))"); _ = calls.release(cid, handle); return }
        // The window server usually lets go by itself when the fade ends; release just in case.
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds) + 0.2) { _ = calls.release(cid, handle) }
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
