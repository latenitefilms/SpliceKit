"""Exercise the Swift patcher's signed-entitlement and MCP configuration checks."""

import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PHOTOS = "com.apple.security.personal-information.photos-library"
VALIDATION = "com.apple.security.cs.disable-library-validation"


class PatcherConfigurationTests(unittest.TestCase):
    def test_configured_entitlements_and_both_signing_paths(self):
        resource = ROOT / "Patcher/SpliceKit/Resources/entitlements.plist"
        values = plistlib.loads(resource.read_bytes())
        for key in (PHOTOS, VALIDATION):
            self.assertIs(values.get(key), True)
        model = (ROOT / "Patcher/SpliceKit/Models/PatcherModel.swift").read_text()
        self.assertEqual(model.count('shellQuote(repoDir + "/entitlements.plist")'), 2)
        self.assertEqual(model.count("try await verifySignedEntitlements(of: moddedApp)"), 2)


@unittest.skipUnless(sys.platform == "darwin", "Patcher tests use macOS Security and Foundation")
class SwiftPatcherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        directory = tempfile.TemporaryDirectory(prefix="SpliceKit Swift tests ")
        cls.addClassCleanup(directory.cleanup)
        root = Path(directory.name)
        main = root / "main.swift"
        main.write_text("""
import Foundation

let args = CommandLine.arguments
if args[1] == "mcp" {
    do {
        try writeMCPConfiguration(in: URL(fileURLWithPath: args[2]), server: URL(fileURLWithPath: args[3]))
    } catch {
        print(error.localizedDescription)
        exit(1)
    }
} else {
    let report: PatcherEntitlements?
    if args[1] == "signed" {
        report = PatcherEntitlements.read(from: URL(fileURLWithPath: args[2]))
    } else {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        report = values.map { PatcherEntitlements(values: $0) }
    }
    guard let report else { print("Unreadable entitlements"); exit(1) }
    report.diagnosticLines.forEach { print($0) }
    if let missing = report.missingRequiredKey { print(missing); exit(1) }
}
""")
        cls.binary = root / "verification"
        subprocess.run([
            "xcrun", "swiftc", "-module-cache-path", str(root / "modules"),
            str(ROOT / "Patcher/SpliceKit/Models/ShellHelpers.swift"), str(main), "-o", str(cls.binary),
        ], check=True)

    def verify(self, *args, payload=b""):
        return subprocess.run([self.binary, *args], input=payload, capture_output=True)

    def test_entitlements_must_be_boolean_true(self):
        expected = {PHOTOS: True, VALIDATION: True, "com.apple.security.app-sandbox": False}
        result = self.verify("plist", payload=plistlib.dumps(expected))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(b"Entitlement photos-library: present", result.stdout)
        self.assertIn(b"Entitlement app-sandbox: present", result.stdout)
        for key in (PHOTOS, VALIDATION):
            for value in (None, False, "true", 1):
                with self.subTest(key=key, value=value):
                    fields = expected.copy()
                    if value is None:
                        del fields[key]
                    else:
                        fields[key] = value
                    result = self.verify("plist", payload=plistlib.dumps(fields))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(key.encode(), result.stdout)
                    self.assertIn(b"MISSING", result.stdout)

    def test_unreadable_entitlements_fail(self):
        for data in (b"", b"not a plist"):
            self.assertNotEqual(self.verify("plist", payload=data).returncode, 0)
        self.assertNotEqual(self.verify("signed", "/does/not/exist").returncode, 0)

    def test_read_entitlements_from_a_signed_binary(self):
        with tempfile.TemporaryDirectory(prefix="SpliceKit signature ") as temp:
            root = Path(temp)
            binary = root / "signature probe"
            shutil.copyfile("/usr/bin/true", binary)
            entitlements = root / "entitlements.plist"
            entitlements.write_bytes(plistlib.dumps({PHOTOS: True, VALIDATION: True}))
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--entitlements",
                            entitlements, binary], check=True, capture_output=True)
            result = self.verify("signed", binary)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_project_configuration_never_overwrites_an_existing_file(self):
        with tempfile.TemporaryDirectory(prefix="SpliceKit project ") as temp:
            root = Path(temp)
            server = root / 'My "Patcher".app/Contents/Resources/mcp/splicekit-mcp'
            self.assertEqual(self.verify("mcp", root, server).returncode, 0)
            config = root / ".mcp.json"
            self.assertEqual(json.loads(config.read_bytes()), {"mcpServers": {"splicekit": {"command": str(server)}}})
            config.write_text('{"mcpServers":{"another":{}}}')
            self.assertNotEqual(self.verify("mcp", root, server).returncode, 0)
            self.assertEqual(config.read_text(), '{"mcpServers":{"another":{}}}')


if __name__ == "__main__":
    unittest.main()
