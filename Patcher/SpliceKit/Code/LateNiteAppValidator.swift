import AppKit
import Security

enum LateNiteAppValidator {
    static let eligibleApps: [(name: String, bundleID: String)] = [
        ("ATEM Exporter", "com.latenitefilms.ATEMExporter"),
        ("BRAW Toolbox", "com.latenitefilms.BRAWToolbox"),
        ("Capacitor", "com.latenitefilms.Capacitor"),
        ("Fast Collections", "com.latenitefilms.FastCollections"),
        ("Gyroflow Toolbox", "com.latenitefilms.GyroflowToolbox"),
        ("Keyframe Toolbox", "com.latenitefilms.KeyframeToolbox"),
        ("LUT Robot", "com.latenitefilms.LUTRobot"),
        ("Marker Toolbox", "com.latenitefilms.MarkerToolbox"),
        ("Metaburner", "com.latenitefilms.Metaburner"),
        ("News Import", "com.latenitefilms.NewsImport"),
        ("Notion Toolbox", "com.latenitefilms.NotionToolbox"),
        ("Recall Toolbox", "com.latenitefilms.RecallToolbox"),
        ("ScriptStar", "com.latenitefilms.ScriptStar"),
        ("Transfer Toolbox", "com.latenitefilms.TransferToolbox"),
        ("VFX Toolbox", "com.latenitefilms.VFXToolbox"),
    ]

    static func hasEligibleAppInstalled() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            for app in eligibleApps {
                let candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: app.bundleID)
                for url in candidates where hasValidSignature(at: url, bundleID: app.bundleID) {
                    return true
                }
            }
            return false
        }.value
    }

    private static func hasValidSignature(at url: URL, bundleID: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { return false }

        var signingInfo: CFDictionary?
        let signingFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, signingFlags, &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any],
              info[kSecCodeInfoTeamIdentifier as String] as? String == "A5HDJTY9X5" else { return false }

        // App Store copies carry Apple's signing certificate and the developer's team ID.
        let rule = """
            anchor apple generic and identifier "\(bundleID)"
            and certificate leaf[subject.CN] = "Apple Mac OS Application Signing"
            """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }

        let flags: SecCSFlags = [SecCSFlags(rawValue: kSecCSCheckAllArchitectures), .noNetworkAccess]
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
