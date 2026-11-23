import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PatcherResourceTests(unittest.TestCase):
    def test_incremental_build_replaces_transcriber_sources_with_binary_and_resources(self):
        with tempfile.TemporaryDirectory(prefix="SpliceKit resources ") as temp:
            checkout = Path(temp) / "checkout"
            checkout.mkdir()
            for name in ("MCP", "Lua Scripts", "Documentation"):
                (checkout / name).symlink_to(ROOT / name, target_is_directory=True)
            project = checkout / "Patcher"
            project.mkdir()
            (project / "scripts").symlink_to(ROOT / "Patcher/scripts", target_is_directory=True)

            products = Path(temp) / "products"
            prebuilt = products / "SpliceKit_prebuilt"
            prebuilt.mkdir(parents=True)
            for name in ("SpliceKit", "beat-detector", "silence-detector", "structure-analyzer", "SpliceKitMixer"):
                (prebuilt / name).write_text(name)
            for name in ("parakeet-transcriber", "whisper-transcriber"):
                package = checkout / "Tools" / name
                package.mkdir(parents=True)
                (package / "Package.swift").write_text(name)

            def bundle():
                subprocess.run(
                    ["bash", ROOT / "Patcher/scripts/bundle_resources.sh"],
                    env={**os.environ, "PROJECT_DIR": str(project),
                         "BUILT_PRODUCTS_DIR": str(products), "PRODUCT_NAME": "SpliceKit"},
                    check=True, capture_output=True, text=True,
                )

            bundle()
            resources = products / "SpliceKit.app/Contents/Resources"
            tool = resources / "tools/whisper-transcriber"
            self.assertTrue((tool / "Package.swift").is_file())
            self.assertTrue((resources / "tools/beat-detector").is_file())
            self.assertEqual((resources / "mcp/requirements.txt").read_bytes(), (ROOT / "MCP/requirements.txt").read_bytes())
            self.assertTrue((resources / "Scripts/lua/lib/skutil.lua").is_file())

            release = checkout / "Tools/whisper-transcriber/.build/release"
            assets = release / "Tokenizer.bundle"
            assets.mkdir(parents=True)
            (assets / "tokens.json").write_text("[]")
            (release / tool.name).write_text("compiled helper")
            bundle()
            self.assertEqual(tool.read_text(), "compiled helper")
            self.assertEqual((resources / "tools/Tokenizer.bundle/tokens.json").read_text(), "[]")
