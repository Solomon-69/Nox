import Cocoa
import SwiftUI

/// What the setup screen can ask the app to do.
struct SetupActions {
    let automationGranted: () -> Bool?
    let requestAutomation: () async -> Bool
    let screenGranted: () -> Bool
    let requestScreen: () -> Void
    let openSafari: () -> Void
    let setLogin: (Bool) -> Void
}

/// Apple's own permission prompts, asked for on purpose (not by surprise mid-use).
enum Permissions {
    private static let systemEvents = "com.apple.systemevents"

    /// true = allowed, false = refused, nil = not asked yet.
    static func automationState() -> Bool? {
        switch status(ask: false) {
        case noErr: return true
        case OSStatus(errAEEventNotPermitted): return false
        default: return nil
        }
    }

    /// Shows macOS's "Nox wants to control System Events" dialog if it hasn't been answered.
    static func requestAutomation() async -> Bool {
        await launchSystemEvents()
        return await withCheckedContinuation { done in
            DispatchQueue.global(qos: .userInitiated).async {
                done.resume(returning: status(ask: true) == noErr)
            }
        }
    }

    private static func status(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEvents)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAESetData), ask)
    }

    private static func launchSystemEvents() async {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: systemEvents).isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: systemEvents) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}

/// Each part of the welcome window rises in a moment after the one above it.
struct Rise: ViewModifier {
    let index: Int
    let shown: Bool
    private var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 14)
            .blur(radius: shown || reduce ? 0 : 4)
            .animation(reduce ? .easeOut(duration: 0.2)
                       : .spring(response: 0.55, dampingFraction: 0.84).delay(0.08 + Double(index) * 0.07), value: shown)
    }
}

extension View {
    func rise(_ index: Int, _ shown: Bool) -> some View { modifier(Rise(index: index, shown: shown)) }
}

/// First-launch welcome: three pages (what Nox does, the permissions, how to use it). Frosted glass
/// panel on a plain soft backdrop. Each page rises in once, like the iPhone unlock, and never replays.
/// Follows the Mac's light or dark look like the rest of Nox.
struct OnboardingView: View {
    @ObservedObject var model: DarkSwitchModel
    let setup: SetupActions
    let finish: () -> Void
    var page: Int = 0
    var body: some View { OnboardingContent(model: model, setup: setup, finish: finish, page: page).modifier(NoxThemed()) }
}

private struct OnboardingContent: View {
    @Environment(\.noxTheme) private var theme
    @ObservedObject var model: DarkSwitchModel
    let setup: SetupActions
    let finish: () -> Void

    @State var page: Int
    @State private var seen: Set<Int> = []        // pages whose rise-in already played; it never replays
    @State private var forward = true
    @State private var automation: Bool?
    @State private var screen = false
    @State private var asking = false
    @State private var shown = false
    private static let pages = 3
    private var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(model: DarkSwitchModel, setup: SetupActions, finish: @escaping () -> Void, page: Int) {
        self.model = model; self.setup = setup; self.finish = finish
        _page = State(initialValue: page)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome.transition(slide)
                case 1: permissions.transition(slide)
                default: ready.transition(slide)
                }
            }
            .padding(.vertical, 10)
            .frame(height: 396, alignment: .top)
            .clipped()
            footer
        }
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 16)
        .background(glass)
        .padding(16)
        .frame(width: 456)
        .background(backdrop)
        .noFocusRing()
        .onAppear {
            automation = setup.automationGranted()
            screen = setup.screenGranted()
            seen.insert(page)
            shown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            automation = setup.automationGranted()
            screen = setup.screenGranted()
        }
    }

    private var slide: AnyTransition {
        reduce ? .opacity
            : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                          removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    /// Plain soft wash, fully opaque: nothing behind the window shows through.
    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [theme.bgTop, theme.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [theme.violet.opacity(0.30), theme.violet.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.blue.opacity(0.16), Color.blue.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    /// The frosted panel itself.
    private var glass: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(theme.card.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 12) {
            BigToggle(isOn: model.isDark, width: 96) { model.toggleDark() }
                .scaleEffect(shown || reduce ? 1 : 0.55)
                .animation(reduce ? nil : .spring(response: 0.7, dampingFraction: 0.6).delay(0.05), value: shown)
                .rise(0, shown)
                .padding(.top, 6)
            Text("Welcome to Nox")
                .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(theme.text).rise(1, shown)
            Text("Dark mode, whenever you want it.")
                .font(.system(size: 13)).foregroundStyle(theme.dim).rise(2, shown)
            VStack(spacing: 8) {
                tip("switch.2", "One click", "Click the switch in the menu bar to flip light and dark.").rise(3, shown)
                tip("safari", "Websites follow", "Safari pages turn dark with your Mac.").rise(4, shown)
                tip("moon.stars.fill", "On a schedule", "Switch to dark at night by itself.").rise(5, shown)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var permissions: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text("Three quick steps")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(theme.text).rise(0, shown)
                Text("Each button shows Apple's own Allow window.")
                    .font(.system(size: 12)).foregroundStyle(theme.dim).rise(1, shown)
            }
            .padding(.bottom, 6)
            step(1, "Switch dark mode", "Lets Nox flip your Mac between light and dark.",
                 done: automation == true, button: automation == false ? "Open Settings" : "Allow") {
                if automation == false {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    return
                }
                asking = true
                Task { @MainActor in
                    _ = await setup.requestAutomation()
                    automation = setup.automationGranted()
                    asking = false
                }
            }
            .rise(2, shown)
            step(2, "Dark websites in Safari", "Turn on the Nox extension in Safari. " + SafariSetup.shortHint + ".",
                 done: model.extensionOn == true, button: "Turn on") { setup.openSafari() }
                .rise(3, shown)
            step(3, "Smooth fade (optional)", "Fades every app like the wallpaper. Needs Screen Recording.",
                 done: screen, button: "Allow") {
                setup.requestScreen()
                screen = setup.screenGranted()
            }
            .rise(4, shown)
            HStack(spacing: 12) {
                Image(systemName: "power").foregroundStyle(theme.violet).frame(width: 28)
                Text("Open at login").font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Spacer()
                SmoothSwitch(isOn: model.openAtLogin, title: "Open at login", tint: theme.violet) { setup.setLogin($0) }
            }
            .modifier(CardStyle())
            .rise(5, shown)
        }
        .frame(maxWidth: .infinity)
    }

    private var ready: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 19, style: .continuous).fill(theme.violetDeep.gradient)
                Image(systemName: "checkmark").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: theme.violet.opacity(0.35), radius: 10, y: 5)
            .scaleEffect(shown || reduce ? 1 : 0.5)
            .animation(reduce ? nil : .spring(response: 0.55, dampingFraction: 0.55), value: shown)
            .rise(0, shown)
            .padding(.top, 6)
            Text("You're all set")
                .font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(theme.text).rise(1, shown)
            Text("Three things worth knowing.")
                .font(.system(size: 13)).foregroundStyle(theme.dim).rise(2, shown)
            VStack(spacing: 8) {
                tip("cursorarrow.click", "Click the switch", "In the menu bar, it flips light and dark right away.").rise(3, shown)
                tip("contextualmenu.and.cursorarrow", "Right-click for more", "Or Option-click: Settings, Safari extension and Quit.").rise(4, shown)
                tip("gearshape.fill", "Make it yours", "Night schedule, smooth fade and login are in Settings.").rise(5, shown)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.violetDeep.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.stroke, lineWidth: 1))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if page == 0 {
                Button("Skip") { finish() }.buttonStyle(QuietPill())
            } else {
                Button("Back") { go(page - 1) }.buttonStyle(QuietPill())
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.pages, id: \.self) { i in
                    Capsule().fill(i == page ? theme.violet : theme.trackOff)
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: page)
            Spacer()
            Button { page < Self.pages - 1 ? go(page + 1) : finish() } label: {
                Text(page < Self.pages - 1 ? "Continue" : "Done")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 34)
                    .background(Capsule().fill(theme.violetDeep))
            }
            .buttonStyle(PressStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ p: Int) {
        guard (0..<Self.pages).contains(p) else { return }
        forward = p > page
        let first = !seen.contains(p)
        seen.insert(p)
        if first { shown = false }                  // only a page seen for the first time rises in
        withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) { page = p }
        if first { DispatchQueue.main.async { shown = true } }
    }

    private func step(_ n: Int, _ title: String, _ detail: String, done: Bool, button: String,
                      action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? theme.violet : theme.trackOff)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.dim)
                        .transition(.opacity)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text(detail).font(.system(size: 11)).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done {
                Button(button, action: action)
                    .buttonStyle(PillButtonStyle())
                    .disabled(asking && n == 1)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .modifier(CardStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.68), value: done)
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The steps to turn Nox on in Safari, drawn as numbered cards that rise in one after another.
struct SafariStepsView: View {
    let openSafari: () -> Void
    let close: () -> Void
    var body: some View { SafariStepsContent(openSafari: openSafari, close: close).modifier(NoxThemed()) }
}

private struct SafariStepsContent: View {
    @Environment(\.noxTheme) private var theme
    let openSafari: () -> Void
    let close: () -> Void
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "safari.fill").font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.violetDeep.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(SafariSetup.title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(theme.text)
                    Text("\(SafariSetup.steps.count) steps in Safari's settings").font(.system(size: 12)).foregroundStyle(theme.dim)
                }
            }
            .rise(0, shown)
            ForEach(Array(SafariSetup.steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(i + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(theme.violet))
                    Text(text).font(.system(size: 12.5)).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .modifier(CardStyle())
                .rise(1 + i, shown)
            }
            if let note = SafariSetup.note {
                Text(note).font(.system(size: 11)).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .rise(1 + SafariSetup.steps.count, shown)
            }
            HStack(spacing: 10) {
                Button("Done", action: close).buttonStyle(QuietPill())
                Button(action: openSafari) {
                    Text("Open Safari Extensions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(theme.violetDeep))
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.defaultAction)
            }
            .rise(2 + SafariSetup.steps.count, shown)
        }
        .padding(24)
        .frame(width: 420)
        .background(LinearGradient(colors: [theme.bgTop, theme.bgBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .noFocusRing()
        .onAppear { shown = true }
    }
}

private struct QuietPill: ButtonStyle {
    @Environment(\.noxTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
            .padding(.horizontal, 18).frame(height: 36)
            .background(Capsule().fill(theme.card))
            .overlay(Capsule().strokeBorder(theme.stroke))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
