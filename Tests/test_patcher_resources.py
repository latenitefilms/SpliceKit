import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PatcherResourceTests(unittest.TestCase):
    def test_incremental_build_replaces_transcriber_sources_and_signs_the_bundled_binaries(self):
        with tempfile.TemporaryDirectory(prefix="SpliceKit resources ") as temp:
            checkout = Path(temp) / "checkout"
            checkout.mkdir()
            (checkout / "Lua Scripts").symlink_to(ROOT / "Lua Scripts", target_is_directory=True)
            project = checkout / "Patcher"
            project.mkdir()
            (project / "SpliceKit").symlink_to(ROOT / "Patcher/SpliceKit", target_is_directory=True)
            project_file = ROOT / "Patcher/SpliceKit.xcodeproj/project.pbxproj"
            plist = subprocess.check_output(["plutil", "-convert", "xml1", "-o", "-", project_file])
            phases = plistlib.loads(plist)["objects"].values()
            bundle_phase = next(phase["shellScript"] for phase in phases
                                if phase.get("name") == "Bundle SpliceKit Resources")

            products = Path(temp) / "products"
            prebuilt = products / "SpliceKit_prebuilt"
            prebuilt.mkdir(parents=True)
            mcp = prebuilt / "mcp"
            mcp.mkdir()
            executable = Path(temp) / "fixture"
            source = Path(temp) / "fixture.c"
            source.write_text("int main(void) { return 0; }\n")
            subprocess.run(["xcrun", "clang", "-arch", "arm64", "-arch", "x86_64",
                            source, "-o", executable], check=True)
            (mcp / "Catalog.json").write_text("{}")
            shutil.copy2(executable, mcp / "splicekit-mcp")
            tools = ("beat-detector", "silence-detector", "structure-analyzer", "SpliceKitMixer")
            for name in ("SpliceKit", *tools):
                shutil.copy2(executable, prebuilt / name)
            lua_license = prebuilt / "Lua-LICENSE.txt"
            lua_license.write_text("License supplied by the Lua source archive.\n")
            transcribers = ("parakeet-transcriber", "whisper-transcriber")
            for name in transcribers:
                package = checkout / "Tools" / name
                package.mkdir(parents=True)
                (package / "Package.swift").write_text(name)

            def bundle(signing_allowed):
                subprocess.run(
                    ["bash", "-c", bundle_phase],
                    env={**os.environ, "PROJECT_DIR": str(project),
                         "BUILT_PRODUCTS_DIR": str(products), "PRODUCT_NAME": "SpliceKit",
                         "CONFIGURATION": "Debug", "CODE_SIGNING_ALLOWED": signing_allowed,
                         "EXPANDED_CODE_SIGN_IDENTITY": "-"},
                    check=True, capture_output=True, text=True,
                )

            resources = products / "SpliceKit.app/Contents/Resources"
            legacy_mcp = resources / "mcp"
            (legacy_mcp / "__pycache__").mkdir(parents=True)
            for stale in ("server.py", "otio_adapter.py", "requirements.txt", "__pycache__/server.pyc"):
                (legacy_mcp / stale).write_text("old build")
            bundle("NO")
            tool = resources / "tools/whisper-transcriber"
            self.assertTrue((tool / "Package.swift").is_file())
            self.assertTrue((resources / "tools/beat-detector").is_file())
            self.assertEqual({item.name for item in legacy_mcp.iterdir()}, {"splicekit-mcp", "Catalog.json"})
            for name in ("splicekit-mcp", "Catalog.json"):
                self.assertEqual((resources / "mcp" / name).read_bytes(), (mcp / name).read_bytes())
            self.assertTrue((resources / "Scripts/lua/lib/skutil.lua").is_file())
            self.assertEqual((resources / lua_license.name).read_bytes(), lua_license.read_bytes())
            self.assertEqual((resources / "entitlements.plist").read_bytes(),
                             (project / "SpliceKit/Resources/entitlements.plist").read_bytes())

            for name in transcribers:
                release = checkout / "Tools" / name / ".build/release"
                release.mkdir(parents=True)
                shutil.copy2(executable, release / name)
            assets = checkout / "Tools/whisper-transcriber/.build/release/Tokenizer.bundle"
            assets.mkdir()
            (assets / "tokens.json").write_text("[]")
            bundle("YES")
            self.assertEqual((resources / "tools/Tokenizer.bundle/tokens.json").read_text(), "[]")
            binaries = [resources / "SpliceKit", resources / "mcp/splicekit-mcp"]
            binaries.extend(resources / "tools" / name for name in (*tools, *transcribers))
            for binary in binaries:
                for arch in ("arm64", "x86_64"):
                    with self.subTest(binary=binary.name, arch=arch):
                        signature = subprocess.run(
                            ["codesign", "--display", "--verbose=4", "--arch", arch, binary],
                            check=True, capture_output=True, text=True,
                        )
                        self.assertRegex(signature.stderr, r"flags=[^\n]*\bruntime\b")
