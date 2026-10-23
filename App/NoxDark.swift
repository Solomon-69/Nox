// NoxDark.swift: remembers whether the Mac is dark because Nox made it dark.
// The Safari and Chrome extensions only darken web pages while this is on. If dark mode came
// from anywhere else (Control Centre, System Settings, Apple's own Auto), browsers behave
// exactly like stock macOS and Nox injects nothing.
import Foundation

enum NoxDark {
    /// Read by the Safari extension (shared preference) and the Chrome bridge below.
    static let key = "darkByNox"
    static let forceDarkKey = "forceDark"

    /// What the extensions should do: darken pages only when the user wants it AND Nox made it dark.
    static func pagesShouldDarken(forceDark: Bool, darkByNox: Bool) -> Bool { forceDark && darkByNox }

    /// The new flag after something happens.
    enum Event {
        case launched                         // Nox started: it did not cause whatever look the Mac has
        case noxSwitching(toDark: Bool)       // Nox is about to switch (set before, so pages darken in step)
        case noxSwitchFailed                  // the switch did not happen
        case appearanceChanged(byNox: Bool, nowDark: Bool)
        case quitting                         // nobody watches the Mac while Nox is closed
    }

    static func next(_ flag: Bool, after event: Event) -> Bool {
        switch event {
        case .launched, .noxSwitchFailed, .quitting: return false
        case .noxSwitching(let toDark): return toDark
        case .appearanceChanged(let byNox, let nowDark): return nowDark && byNox && flag
        }
    }

    static var flag: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            UserDefaults.standard.synchronize()   // the extensions read it from another process
        }
    }

    static func apply(_ event: Event) { flag = next(flag, after: event) }

    static var pagesShouldDarkenNow: Bool {
        let d = UserDefaults.standard
        let force = d.object(forKey: forceDarkKey) as? Bool ?? true
        return pagesShouldDarken(forceDark: force, darkByNox: d.bool(forKey: key))
    }
}

/// Chrome, Edge, Brave and Arc ask Nox through "native messaging": the browser starts this same
/// app with its extension address as the argument, sends one small JSON question on stdin and
/// reads the answer on stdout. Nox writes the small registration file each browser looks for.
enum ChromeBridge {
    static let hostName = "com.solomon.nox"
    /// Fixed by the "key" in ChromeExtension/manifest.json.
    static let extensionID = "dllbkfilglippjdnndjgaefbjadfemfo"

    static func isBrowserLaunch(_ args: [String]) -> Bool {
        args.dropFirst().contains { $0.hasPrefix("chrome-extension://") }
    }

    /// Answers one question and returns. Message format: 4-byte little-endian length, then JSON.
    static func answer(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        let header = input.readData(ofLength: 4)
        if header.count == 4 {
            let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
            if length > 0, length < 4096 { _ = input.readData(ofLength: length) }
        }
        output.write(frame(enabled: NoxDark.pagesShouldDarkenNow))
    }

    static func frame(enabled: Bool) -> Data {
        let body = Data(#"{"enabled":\#(enabled)}"#.utf8)
        var length = UInt32(body.count).littleEndian
        return Data(bytes: &length, count: 4) + body
    }

    /// Browser folders under ~/Library/Application Support that take a NativeMessagingHosts file.
    static let browserFolders = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
        "Microsoft Edge", "BraveSoftware/Brave-Browser", "Arc/User Data",
    ]

    /// Writes the registration file for every installed Chromium browser, pointing at this copy of Nox.
    static func register() {
        guard let exe = Bundle.main.executablePath,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Nox: tells the extension whether Nox turned dark mode on",
            "path": exe,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        else { return }
        for folder in browserFolders {
            let browser = support.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: browser.path) else { continue }
            let hosts = browser.appendingPathComponent("NativeMessagingHosts")
            try? FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
            try? data.write(to: hosts.appendingPathComponent("\(hostName).json"), options: .atomic)
        }
    }
}
