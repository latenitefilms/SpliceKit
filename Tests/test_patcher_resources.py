import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PatcherResourceTests(unittest.TestCase):
    def test_incremental_build_replaces_transcriber_sources_with_binary_and_resources(self):
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
            for name in ("splicekit-mcp", "Catalog.json"):
                (mcp / name).write_text(name)
            for name in ("SpliceKit", "beat-detector", "silence-detector", "structure-analyzer", "SpliceKitMixer"):
                (prebuilt / name).write_text(name)
            lua_license = prebuilt / "Lua-LICENSE.txt"
            lua_license.write_text("License supplied by the Lua source archive.\n")
            for name in ("parakeet-transcriber", "whisper-transcriber"):
                package = checkout / "Tools" / name
                package.mkdir(parents=True)
                (package / "Package.swift").write_text(name)

            def bundle():
                subprocess.run(
                    ["bash", "-c", bundle_phase],
                    env={**os.environ, "PROJECT_DIR": str(project),
                         "BUILT_PRODUCTS_DIR": str(products), "PRODUCT_NAME": "SpliceKit"},
                    check=True, capture_output=True, text=True,
                )

            resources = products / "SpliceKit.app/Contents/Resources"
            legacy_mcp = resources / "mcp"
            (legacy_mcp / "__pycache__").mkdir(parents=True)
            for stale in ("server.py", "otio_adapter.py", "requirements.txt", "__pycache__/server.pyc"):
                (legacy_mcp / stale).write_text("old build")
            bundle()
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

            release = checkout / "Tools/whisper-transcriber/.build/release"
            assets = release / "Tokenizer.bundle"
            assets.mkdir(parents=True)
            (assets / "tokens.json").write_text("[]")
            (release / tool.name).write_text("compiled helper")
            bundle()
            self.assertEqual(tool.read_text(), "compiled helper")
            self.assertEqual((resources / "tools/Tokenizer.bundle/tokens.json").read_text(), "[]")
