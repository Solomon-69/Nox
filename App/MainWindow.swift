import SwiftUI
import AppKit

/// Shared state the window and the menu bar item both read and change.
final class DarkSwitchModel: ObservableObject {
    @Published var isDark = false
    @Published var forceDark = true
    @Published var extensionOn: Bool?
    @Published var openAtLogin = false
    @Published var showInDock = false
    @Published var openCount = 0   // bumped on every panel open, drives the entrance spring
    @Published var smoothFade = false
    @Published var nightSchedule = false
    @Published var darkAt = 20 * 60         // minutes after midnight
    @Published var lightAt = 7 * 60

    var toggleDark: () -> Void = {}
    var setForceDark: (Bool) -> Void = { _ in }
    var openExtensionSettings: () -> Void = {}
    var setOpenAtLogin: (Bool) -> Void = { _ in }
    var setShowInDock: (Bool) -> Void = { _ in }
    var setSmoothFade: (Bool) -> Void = { _ in }
    var setNightSchedule: (Bool) -> Void = { _ in }
    var setTimes: (Int, Int) -> Void = { _, _ in }
    var openSettings: () -> Void = {}

    var scheduleText: String { "\(clock(darkAt)) to \(clock(lightAt))" }

    func clock(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Nox colours. Dark: the night navy and violet. Light: lavender-white cards with purple accents.
/// Views read the right set from the environment, so the panel and window follow the Mac's look.
struct NoxTheme: Equatable {
    let bgTop: Color
    let bgBottom: Color
    let violet: Color
    let violetDeep: Color
    let card: Color
    let stroke: Color
    let text: Color
    let dim: Color
    let warn: Color
    let trackOff: Color

    static let dark = NoxTheme(
        bgTop: Color(red: 0.07, green: 0.09, blue: 0.20),
        bgBottom: Color(red: 0.02, green: 0.03, blue: 0.07),
        violet: Color(red: 0.55, green: 0.45, blue: 1.0),
        violetDeep: Color(red: 0.27, green: 0.18, blue: 0.80),
        card: Color.white.opacity(0.06),
        stroke: Color.white.opacity(0.09),
        text: .white,
        dim: Color.white.opacity(0.55),
        warn: Color(red: 1, green: 0.62, blue: 0.45),
        trackOff: Color.white.opacity(0.14))

    static let light = NoxTheme(
        bgTop: Color(red: 0.975, green: 0.965, blue: 1.0),
        bgBottom: Color(red: 0.925, green: 0.905, blue: 0.995),
        violet: Color(red: 0.45, green: 0.33, blue: 0.93),
        violetDeep: Color(red: 0.36, green: 0.24, blue: 0.86),
        card: Color.white.opacity(0.78),
        stroke: Color(red: 0.45, green: 0.33, blue: 0.93).opacity(0.14),
        text: Color(red: 0.13, green: 0.11, blue: 0.26),
        dim: Color(red: 0.13, green: 0.11, blue: 0.26).opacity(0.58),
        warn: Color(red: 0.82, green: 0.36, blue: 0.12),
        trackOff: Color(red: 0.45, green: 0.33, blue: 0.93).opacity(0.16))
}

private struct NoxThemeKey: EnvironmentKey { static let defaultValue = NoxTheme.dark }
extension EnvironmentValues {
    var noxTheme: NoxTheme {
        get { self[NoxThemeKey.self] }
        set { self[NoxThemeKey.self] = newValue }
    }
}

extension NoxTheme {
    /// The colour set part way between light (0) and dark (1), for the smooth fade.
    static func blend(_ t: CGFloat) -> NoxTheme {
        if t <= 0 { return .light }
        if t >= 1 { return .dark }
        func m(_ k: KeyPath<NoxTheme, Color>) -> Color { mixColor(light[keyPath: k], dark[keyPath: k], t) }
        return NoxTheme(bgTop: m(\.bgTop), bgBottom: m(\.bgBottom), violet: m(\.violet), violetDeep: m(\.violetDeep),
                        card: m(\.card), stroke: m(\.stroke), text: m(\.text), dim: m(\.dim), warn: m(\.warn),
                        trackOff: m(\.trackOff))
    }

    private static func mixColor(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
        let x = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let y = NSColor(b).usingColorSpace(.sRGB) ?? .black
        func l(_ p: CGFloat, _ q: CGFloat) -> Double { Double(p + (q - p) * t) }
        return Color(.sRGB, red: l(x.redComponent, y.redComponent), green: l(x.greenComponent, y.greenComponent),
                     blue: l(x.blueComponent, y.blueComponent), opacity: l(x.alphaComponent, y.alphaComponent))
    }
}

/// While the smooth fade runs, Nox's own windows take their colours from the fade's clock
/// (same start, length and easing as the veil fading over every other app), so the whole
/// screen changes as one. The rest of the time this is nil and Nox simply follows the Mac.
final class NoxLook: ObservableObject {
    static let shared = NoxLook()
    /// 0 = light, 1 = dark; nil = follow the Mac's look.
    @Published var mix: CGFloat?
}

/// Picks the colour set from the Mac's look. No animation of its own: without the smooth fade
/// it flips the instant the Mac does, and with it the fade's clock drives it (see NoxLook).
struct NoxThemed: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var look = NoxLook.shared
    func body(content: Content) -> some View {
        content
            .environment(\.noxTheme, look.mix.map { NoxTheme.blend($0) } ?? (scheme == .dark ? .dark : .light))
    }
}

struct MainView: View {
    @ObservedObject var model: DarkSwitchModel
    var body: some View { MainContent(model: model).modifier(NoxThemed()) }
}

private struct MainContent: View {
    @ObservedObject var model: DarkSwitchModel
    @Environment(\.noxTheme) private var theme

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                statusRow
                SettingRow(icon: "globe", title: "Websites follow your Mac",
                           detail: "Safari pages go dark with your Mac",
                           isOn: Binding(get: { model.forceDark }, set: { model.setForceDark($0) }))
                SettingRow(icon: "moon.stars", title: "Dark at night",
                           detail: "Switches by itself at the times below",
                           isOn: Binding(get: { model.nightSchedule }, set: { model.setNightSchedule($0) }))
                if model.nightSchedule { timesRow }
                SettingRow(icon: "wand.and.rays", title: "Smooth fade",
                           detail: "Softens the switch across every open app",
                           isOn: Binding(get: { model.smoothFade }, set: { model.setSmoothFade($0) }))
                SettingRow(icon: "power", title: "Open at login",
                           detail: "Start Nox when your Mac starts",
                           isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                SettingRow(icon: "dock.rectangle", title: "Show in Dock",
                           detail: "Off: Nox stays in the menu bar only",
                           isOn: Binding(get: { model.showInDock }, set: { model.setShowInDock($0) }))
                extensionRow
                NoxShareRow()
            }
            Text("Click the menu bar switch once to flip dark mode. Right-click it (or Option-click) for options.")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28).padding(.bottom, 24).padding(.top, 8)
        .frame(width: 420)
        .background(LinearGradient(colors: [theme.bgTop, theme.bgBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea())
        .noFocusRing()
    }

    /// The status row: what the Mac is now and when it changes next, with a compact switch.
    /// (The big animated switch lives only in the menu bar panel.)
    private var statusRow: some View {
        StatusHero(isDark: model.isDark, subtitle: statusSubtitle) { model.toggleDark() }
    }

    private var statusSubtitle: String {
        guard model.nightSchedule else { return "Flip the switch to change your whole Mac" }
        return model.isDark ? "Switches to light at \(model.clock(model.lightAt))"
                            : "Switches to dark at \(model.clock(model.darkAt))"
    }

    @State private var editingLight = false
    @Namespace private var timesNS

    /// One drum for both times: pick Dark or Light at the top, then a chip or the wheel below.
    private var timesRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                timeTab(light: false, icon: "moon.fill", name: "Dark from", minutes: model.darkAt)
                timeTab(light: true, icon: "sun.max.fill", name: "Light from", minutes: model.lightAt)
            }
            .padding(3)
            .background(Capsule().fill(theme.trackOff.opacity(0.6)))
            if editingLight {
                ChipDrumPicker(title: "Light from", value: model.lightAt,
                               presets: [6 * 60, 7 * 60, 7 * 60 + 30, 8 * 60], tint: theme.violet) {
                    model.setTimes(model.darkAt, $0)
                }
                .id("light")
            } else {
                ChipDrumPicker(title: "Dark from", value: model.darkAt,
                               presets: [19 * 60, 20 * 60, 21 * 60, 22 * 60], tint: theme.violet) {
                    model.setTimes($0, model.lightAt)
                }
                .id("dark")
            }
        }
        .modifier(CardStyle())
    }

    private func timeTab(light: Bool, icon: String, name: String, minutes: Int) -> some View {
        let selected = editingLight == light
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(name).font(.system(size: 12))
            Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(selected ? Color.white : theme.text.opacity(0.8))
        .frame(maxWidth: .infinity).frame(height: 26)
        .background {
            if selected { Capsule().fill(theme.violet).matchedGeometryEffect(id: "tab", in: timesNS) }
        }
        .contentShape(Capsule())
        .onTapGesture { selectTab(light) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selectTab(light) }
    }

    private func selectTab(_ light: Bool) {
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            editingLight = light
        }
    }

    private var extensionRow: some View {
        HStack(spacing: 12) {
            RowIcon(name: "puzzlepiece.extension")
            VStack(alignment: .leading, spacing: 2) {
                Text("Safari extension").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(extensionText).font(.system(size: 11)).foregroundStyle(extensionColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.extensionOn == nil {
                ProgressView().controlSize(.small)
            } else if model.extensionOn == false {
                Button("Turn on") { model.openExtensionSettings() }
                    .buttonStyle(PillButtonStyle())
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.violet).font(.system(size: 18))
            }
        }
        .modifier(CardStyle())
    }

    private var extensionText: String {
        switch model.extensionOn {
        case .some(true): return "On, working on every site"
        case .some(false): return "Off. " + SafariSetup.shortHint
        case .none: return "Checking…"
        }
    }

    private var extensionColor: Color {
        model.extensionOn == false ? theme.warn : theme.dim
    }
}

/// Status row at the top of Settings: the same card as the other rows, a little taller, with a
/// bigger copy of the menu bar panel's sun and moon switch (that switch carries the animation).
struct StatusHero: View {
    @Environment(\.noxTheme) private var theme
    let isDark: Bool
    let subtitle: String
    let onToggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(Color.orange)
                    .opacity(isDark ? 0 : 1).rotationEffect(.degrees(isDark ? 90 : 0)).scaleEffect(isDark ? 0.5 : 1)
                Image(systemName: "moon.fill")
                    .foregroundStyle(theme.violet)
                    .opacity(isDark ? 1 : 0).rotationEffect(.degrees(isDark ? 0 : -90)).scaleEffect(isDark ? 1 : 0.5)
            }
            .font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.violet.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                ZStack(alignment: .leading) {   // two titles cross-fade, so the row never jumps
                    Text("Light now").opacity(isDark ? 0 : 1)
                    Text("Dark now").opacity(isDark ? 1 : 0)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(theme.dim)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            BigToggle(isOn: isDark, width: 66, action: onToggle)
        }
        .padding(.vertical, 4)
        .modifier(CardStyle())
        .animation(spring, value: isDark)
    }
}

/// The large switch that mirrors the app icon. Flips the moment you click it and slides the
/// knob across with one spring (it never waits for macOS, so it can't jump or stutter).
struct BigToggle: View {
    @Environment(\.noxTheme) private var theme
    let isOn: Bool
    var width: CGFloat = 150
    let action: () -> Void
    @State private var shown: Bool?
    @State private var pressed = false
    @State private var lastTap: Date?
    @State private var pendingReset: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var on: Bool { shown ?? isOn }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8) }   // same as the menu bar switch

    var body: some View {
        let unit: CGFloat = width / 150
        let h: CGFloat = width * 0.533
        let pad: CGFloat = 7 * unit
        let knob: CGFloat = h - 2 * pad
        let travel: CGFloat = width - knob - 2 * pad
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(colors: [theme.violet, theme.violetDeep], startPoint: .top, endPoint: .bottom))
                .opacity(on ? 1 : 0)
                .background(Capsule().fill(theme.trackOff))
                .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0.25 : 0.12), lineWidth: 1))
                .shadow(color: theme.violet.opacity(on ? 0.45 : 0), radius: 18 * unit, y: 6 * unit)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(red: 0.84, green: 0.85, blue: 0.94)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: knob))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: knob * 0.36 as CGFloat, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .opacity(on ? 0 : 1).rotationEffect(.degrees(on ? 90 : 0)).scaleEffect(on ? 0.5 : 1)
                Image(systemName: "moon.fill")
                    .font(.system(size: knob * 0.36 as CGFloat, weight: .semibold))
                    .foregroundStyle(theme.violetDeep)
                    .opacity(on ? 1 : 0).rotationEffect(.degrees(on ? 0 : -90)).scaleEffect(on ? 1 : 0.5)
            }
            .frame(width: knob, height: knob)
            .scaleEffect(x: pressed ? 1.12 : 1, y: 1, anchor: on ? .trailing : .leading)
            .shadow(color: .black.opacity(0.35), radius: 6 * unit, y: 3 * unit)
            .offset(x: pad + (on ? travel : 0))
        }
        .frame(width: width, height: h)
        .compositingGroup()
        .animation(spring, value: on)
        .scaleEffect(pressed ? 0.97 : 1)
        .contentShape(Capsule())
        .onTapGesture {
            // Ignore taps while a switch is still in progress, so the knob never flips and jumps back.
            if let last = lastTap, Date().timeIntervalSince(last) < 1.0 { return }
            lastTap = Date()
            shown = !on
            action()
            // Falls back to the real state only if the switch was refused.
            pendingReset?.cancel()
            let reset = DispatchWorkItem { shown = nil }
            pendingReset = reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: reset)
        }
        .onLongPressGesture(minimumDuration: 0, pressing: { p in
            withAnimation(.easeOut(duration: 0.12)) { pressed = p }
        }, perform: {})
        // The real value caught up: hand back to it without a second animation.
        .onChange(of: isOn) { value in if shown == value { pendingReset?.cancel(); shown = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dark mode")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAction { action() }
        .accessibilityAddTraits(.isButton)
    }
}

struct SettingRow: View {
    @Environment(\.noxTheme) private var theme
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(name: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.dim)
            }
            Spacer()
            SmoothSwitch(isOn: isOn, title: title, tint: theme.violet) { isOn = $0 }
        }
        .modifier(CardStyle())
    }
}

/// One compact line in the panel: icon, name, optional note, switch.
struct PanelRow: View {
    @Environment(\.noxTheme) private var theme
    let icon: String
    let title: String
    var detail: String? = nil
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.violet)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13)).foregroundStyle(theme.text)
                if let detail { Text(detail).font(.system(size: 10.5)).foregroundStyle(theme.dim) }
            }
            Spacer(minLength: 8)
            SmoothSwitch(isOn: isOn, title: title, tint: theme.violet, width: 34, onChange: onChange)
        }
        .frame(minHeight: 40)
    }
}

struct RowIcon: View {
    @Environment(\.noxTheme) private var theme
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.violet)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(theme.violet.opacity(0.14)))
    }
}

struct CardStyle: ViewModifier {
    @Environment(\.noxTheme) private var theme
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.stroke, lineWidth: 1))
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.noxTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 30)
            .background(Capsule().fill(theme.violetDeep))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Small panel shown on right-click of the menu bar icon.
struct QuickPanel: View {
    @ObservedObject var model: DarkSwitchModel
    let openApp: () -> Void
    let quit: () -> Void
    var body: some View {
        QuickPanelContent(model: model, openApp: openApp, quit: quit).modifier(NoxThemed())
            .background(EscKeyCatcher())
    }
}

private struct QuickPanelContent: View {
    @Environment(\.noxTheme) private var theme
    @ObservedObject var model: DarkSwitchModel
    let openApp: () -> Void
    let quit: () -> Void
    @State private var appeared = false

    private func springIn() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { appeared = true; return }
        appeared = false
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.42, bounce: 0.18)) { appeared = true }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                BigToggle(isOn: model.isDark, width: 70) { model.toggleDark() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isDark ? "Dark mode" : "Light mode")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.text)
                        .contentTransition(.opacity)
                    Text("Click the menu bar switch to flip")
                        .font(.system(size: 11)).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                PanelRow(icon: "globe", title: "Websites follow Mac", isOn: model.forceDark) { model.setForceDark($0) }
                Divider().opacity(0.4)
                PanelRow(icon: "moon.stars", title: "Dark at night",
                         detail: model.nightSchedule ? model.scheduleText : nil,
                         isOn: model.nightSchedule) { model.setNightSchedule($0) }
                Divider().opacity(0.4)
                PanelRow(icon: "wand.and.rays", title: "Smooth fade",
                         isOn: model.smoothFade) { model.setSmoothFade($0) }
                Divider().opacity(0.4)
                PanelRow(icon: "power", title: "Open at login", isOn: model.openAtLogin) { model.setOpenAtLogin($0) }
                Divider().opacity(0.4)
                PanelRow(icon: "dock.rectangle", title: "Show in Dock", isOn: model.showInDock) { model.setShowInDock($0) }
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.stroke, lineWidth: 1))
            // Always shown, so the panel never jumps; it says plainly whether Safari is set up.
            HStack {
                if model.extensionOn == nil {
                    Text("Checking Safari\u{2026}").font(.system(size: 12)).foregroundStyle(theme.dim)
                    Spacer()
                } else if model.extensionOn == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.violet)
                    Text("Safari extension is on").font(.system(size: 12)).foregroundStyle(theme.dim)
                    Spacer()
                } else {
                    Text("Safari extension is off").font(.system(size: 12)).foregroundStyle(theme.warn)
                    Spacer()
                    Button("Turn on") { model.openExtensionSettings() }.buttonStyle(PillButtonStyle())
                }
            }
            .frame(minHeight: 30)
            .modifier(CardStyle())
            // Three equal columns: Share sits in the exact centre, under the arrow.
            HStack(spacing: 0) {
                Button(action: openApp) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.violet)
                .frame(maxWidth: .infinity)
                NoxShareLink()
                    .frame(maxWidth: .infinity)
                Button(action: quit) {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.dim)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        // Extend the gradient under the popover's arrow so the top sliver matches the panel.
        .background(LinearGradient(colors: [theme.bgTop, theme.bgBottom], startPoint: .top, endPoint: .bottom)
            .padding(-20).ignoresSafeArea())
                .noFocusRing()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.96, anchor: .top)
        .offset(y: appeared ? 0 : -8)
        .onAppear { springIn() }
        .onChange(of: model.openCount) { _ in springIn() }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75), value: model.isDark)
        .animation(.easeInOut(duration: 0.2), value: model.extensionOn)
    }
}


/// "Share with a friend" card in Settings: zips a clean copy of Nox and opens the share picker (AirDrop first).
struct NoxShareRow: View {
    @Environment(\.noxTheme) private var theme
    @State private var box = ShareAnchorBox()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Button {
            guard !busy else { return }
            busy = true; error = nil
            ShareFriend.share(from: box.view) { error = $0; busy = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { busy = false }
        } label: {
            HStack(spacing: 12) {
                RowIcon(name: "square.and.arrow.up")
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShareFriend.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                    Text(error ?? ShareFriend.hint).font(.system(size: 11))
                        .foregroundStyle(error == nil ? theme.dim : theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(CardStyle())
        .background(ShareAnchor(box: box))
        .accessibilityLabel(ShareFriend.title)
    }
}

/// Small "Share" link in the menu bar panel footer.
struct NoxShareLink: View {
    @Environment(\.noxTheme) private var theme
    @State private var box = ShareAnchorBox()
    var body: some View {
        Button { ShareFriend.share(from: box.view) { _ in } } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.violet)
        .background(ShareAnchor(box: box))
        .help(ShareFriend.title)
    }
}
