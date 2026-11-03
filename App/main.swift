import Cocoa

// Started by Chrome, Edge, Brave or Arc to ask one question (see ChromeBridge): answer and leave.
if ChromeBridge.isBrowserLaunch(CommandLine.arguments) {
    ChromeBridge.answer()
    exit(0)
}

#if UPDATER_TEST
// Test aid: `Nox --selftest-update=RESULT.json` checks (and downloads) against APP_UPDATE_API, writes JSON, exits.
if let a = CommandLine.arguments.first(where: { $0.hasPrefix("--selftest-update=") }) {
    let out = String(a.dropFirst("--selftest-update=".count))
    Task { @MainActor in
        let ok = await AppUpdater.selfTest(UpdateConfig(repo: "Solomon-69/Nox", appName: "Nox", bundleName: "Nox.app", zipName: "Nox-mac.zip"), result: out)
        exit(ok ? 0 : 1)
    }
    RunLoop.main.run()
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
