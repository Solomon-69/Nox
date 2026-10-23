import SafariServices
import os

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        // Pages are darkened only while "Dark websites" is on AND Nox itself turned dark mode on.
        // Dark mode from Control Centre or System Settings leaves Safari exactly as stock macOS.
        let app = "com.solomon.DarkSwitch" as CFString
        CFPreferencesAppSynchronize(app)
        let forceDark = CFPreferencesCopyAppValue("forceDark" as CFString, app) as? Bool ?? true
        let darkByNox = CFPreferencesCopyAppValue("darkByNox" as CFString, app) as? Bool ?? false
        let enabled = forceDark && darkByNox
        Logger(subsystem: "com.solomon.DarkSwitch", category: "extension").notice("asked, forceDark=\(forceDark, privacy: .public) darkByNox=\(darkByNox, privacy: .public)")
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["enabled": enabled]]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
