import Cocoa

/// Safari lists one "Nox" for every copy of the app macOS has ever seen (old builds, copies in
/// the Trash), and may pick a stale one. At launch, quietly tell macOS to forget every other copy
/// and use this one. It only unregisters: no file is ever moved or deleted.
enum RegistrationCleanup {
    static let appID = "com.solomon.DarkSwitch"
    static let extensionID = "com.solomon.DarkSwitch.Extension"
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    private static let pluginkit = "/usr/bin/pluginkit"

    static func runInBackground() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { run() }
    }

    static func run() {
        let me = Bundle.main.bundleURL.standardizedFileURL
        let myExtension = me.appendingPathComponent("Contents/PlugIns/DarkSwitchExtension.appex")
        // Every copy macOS has on record, including ones already deleted (those only show up in
        // the LaunchServices list; the normal lookups skip them, but Safari can still see them).
        let records = launchServicesRecords()
        let apps = Set(records.filter { $0.id == appID }.map(\.path)
                       + NSWorkspace.shared.urlsForApplications(withBundleIdentifier: appID).map(\.path))
            .filter { !same($0, me.path) }
            .sorted()
        var extensions = Set(records.filter { $0.id == extensionID }.map(\.path))
        extensions.formUnion(apps.map { $0 + "/Contents/PlugIns/DarkSwitchExtension.appex" })
        extensions.formUnion(registeredExtensionPaths())
        extensions = extensions.filter { !same($0, myExtension.path) }

        for path in extensions {
            _ = shell(pluginkit, ["-r", path])
            _ = shell(lsregister, ["-u", path])
        }
        for app in apps { _ = shell(lsregister, ["-u", app]) }

        // Make sure this copy's extension is the one Safari uses. Forgetting the other copies can
        // take this one's record with it (same id), so register this copy again and check it.
        for attempt in 1...3 {
            if attempt > 1 || !extensions.isEmpty || !apps.isEmpty
                || !registeredExtensionPaths().contains(where: { same($0, myExtension.path) }) {
                _ = shell(lsregister, ["-f", "-R", me.path])
                _ = shell(pluginkit, ["-a", myExtension.path])
                Thread.sleep(forTimeInterval: 2)
            }
            if registeredExtensionPaths().contains(where: { same($0, myExtension.path) }) { break }
            dlog("registration: own extension not registered yet (try \(attempt))")
        }
        _ = shell(pluginkit, ["-e", "use", "-i", extensionID])
        if !apps.isEmpty || !extensions.isEmpty {
            dlog("registration: forgot \(apps.count) other app copies and \(extensions.count) extension copies: "
                 + (apps + extensions.sorted()).joined(separator: ", "))
        }
    }

    /// /tmp and /private/tmp are the same folder.
    private static func same(_ a: String, _ b: String) -> Bool {
        func norm(_ p: String) -> String { p.hasPrefix("/private/") ? String(p.dropFirst(8)) : p }
        return norm(a) == norm(b)
    }

    /// (bundle id, path) for every bundle in the LaunchServices database.
    private static func launchServicesRecords() -> [(id: String, path: String)] {
        var out: [(id: String, path: String)] = []
        var path: String?
        for raw in shell(lsregister, ["-dump"]).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-----") { path = nil; continue }
            if line.hasPrefix("path:") {
                var p = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let r = p.range(of: " (0x", options: .backwards) { p = String(p[..<r.lowerBound]) }
                path = p
            } else if line.hasPrefix("identifier:"), let p = path {
                let id = line.dropFirst(11).trimmingCharacters(in: .whitespaces)
                if id == appID || id == extensionID { out.append((id, p)) }
                path = nil
            }
        }
        return out
    }

    /// Paths of every registered copy of the extension, duplicates included.
    private static func registeredExtensionPaths() -> Set<String> {
        let out = shell(pluginkit, ["-m", "-A", "-D", "-v", "-i", extensionID])
        var paths = Set<String>()
        for line in out.split(separator: "\n") {
            guard let r = line.range(of: "\t/", options: .backwards) else { continue }
            let path = String(line[line.index(after: r.lowerBound)...]).trimmingCharacters(in: .whitespaces)
            if path.hasSuffix(".appex") { paths.insert(URL(fileURLWithPath: path).standardizedFileURL.path) }
        }
        return paths
    }

    @discardableResult
    private static func shell(_ tool: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { dlog("registration: \(tool) failed: \(error)"); return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
