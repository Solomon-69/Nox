import Foundation
import Security

/// What someone has to do in Safari to turn Nox on. That depends on how this copy is signed:
/// the GitHub release is signed with a Developer ID, so Safari treats its extension like any other;
/// a copy built on this Mac (development or ad hoc signing) only shows up in Safari after
/// "Allow unsigned extensions" is ticked in the Developer settings.
enum SafariSetup {
    /// True when this copy is signed with a Developer ID (the release download).
    static var isDeveloperIDSigned: Bool { forcedForTest ?? detectedDeveloperID }
    /// Tests only: show the text for the other kind of copy.
    nonisolated(unsafe) static var forcedForTest: Bool?

    private static let detectedDeveloperID: Bool = {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let chain = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = chain.first else { return false }
        var name: CFString?
        SecCertificateCopyCommonName(leaf, &name)
        return (name as String?)?.hasPrefix("Developer ID Application") == true
    }()

    static let title = "Turn on Nox in Safari"

    /// The steps, one per line.
    static var steps: [String] {
        let allow = "Tick Nox. Then click Edit Websites and set \u{201C}When visiting other websites\u{201D} to Allow, so it works on every site."
        if isDeveloperIDSigned {
            return ["In Safari, choose Safari > Settings, then click Extensions.", allow]
        }
        return [
            "In Safari, choose Safari > Settings, click Advanced and tick \u{201C}Show features for web developers\u{201D}.",
            "A Developer tab appears. Click it and tick \u{201C}Allow unsigned extensions\u{201D} (Safari asks for your Mac password).",
            "Click Extensions. " + allow,
        ]
    }

    /// Extra note under the steps (only for copies built on this Mac).
    static var note: String? {
        isDeveloperIDSigned ? nil
            : "This copy of Nox was built on this Mac, so Safari treats it as unsigned and clears step 2 each time Safari quits. The release download from GitHub doesn\u{2019}t need steps 1 and 2."
    }

    /// One short line for the Settings row and the welcome window.
    static var shortHint: String {
        isDeveloperIDSigned ? "Tick Nox in Safari > Settings > Extensions"
                            : "Safari needs \u{201C}Allow unsigned extensions\u{201D} first"
    }

    /// The steps as one block of text, numbered.
    static var text: String {
        let numbered = steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return note.map { numbered + "\n\n" + $0 } ?? numbered
    }
}
