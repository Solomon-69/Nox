import Cocoa

// Started by Chrome, Edge, Brave or Arc to ask one question (see ChromeBridge): answer and leave.
if ChromeBridge.isBrowserLaunch(CommandLine.arguments) {
    ChromeBridge.answer()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
