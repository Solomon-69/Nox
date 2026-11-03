import AppKit
import SwiftUI

// SettingsNav.swift. Keyboard control for the Settings window: Up and Down move a soft highlight through
// every row (wrapping), Left and Right or Space and Return change the highlighted row, Esc clears the
// highlight and then closes the window. The highlight is one pill that glides between rows with a spring.

enum NavID: Int, CaseIterable {
    case status, websites, night, times, fade, login, dock, ext, share, update
}

/// Where each row sits (in the "nav" coordinate space), so one highlight can glide between them.
struct NavRectKey: PreferenceKey {
    static var defaultValue: [NavID: CGRect] = [:]
    static func reduce(value: inout [NavID: CGRect], nextValue: () -> [NavID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func navRow(_ id: NavID) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: NavRectKey.self, value: [id: g.frame(in: .named("nav"))])
        })
    }
}

/// The soft pill behind the highlighted row. Draws nothing until a row is highlighted.
struct NavHighlight: View {
    @Environment(\.noxTheme) private var theme
    let rect: CGRect?
    var body: some View {
        let r = rect ?? .zero
        RoundedRectangle(cornerRadius: 17, style: .continuous)
            .fill(theme.violet.opacity(0.13))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(theme.violet.opacity(0.75), lineWidth: 1.5))
            .frame(width: r.width + 8, height: r.height + 8)
            .offset(x: r.minX - 4, y: r.minY - 4)
            .opacity(rect == nil ? 0 : 1)
            .allowsHitTesting(false)
    }
}

enum NavKey: Int {
    case up = 126, down = 125, left = 123, right = 124, space = 49, ret = 36, enter = 76, esc = 53
}

/// Listens for key presses in the window this view lives in and hands them to `handle`
/// (return true when used). Ignores presses while a text field is being edited.
struct NavKeyCatcher: NSViewRepresentable {
    let handle: (NavKey) -> Bool
    let window: (NSWindow?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let c = context.coordinator
        c.view = v
        c.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak c] event in
            guard let c, let v = c.view, let w = v.window, event.window === w else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if w.firstResponder is NSText { return event }
            guard let key = NavKey(rawValue: Int(event.keyCode)), c.handle(key) else { return event }
            return nil
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.handle = handle
        DispatchQueue.main.async { window(v.window) }
    }
    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }
    final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var handle: (NavKey) -> Bool = { _ in false }
    }
}
