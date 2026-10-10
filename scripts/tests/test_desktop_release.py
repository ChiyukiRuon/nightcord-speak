"""Exercise release selection and reject incomplete or inconsistent artifacts."""

import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location(
    "desktop_release", Path(__file__).resolve().parents[1] / "desktop-release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_default_matrix_and_preview_policy(self):
        result = release.plan("v0.2.0", {"platforms": ["windows", "macos"]})
        self.assertTrue(result["prerelease"])
        self.assertEqual([(t["platform"], t["arch"]) for t in result["matrix"]["include"]],
                         [("windows", "x64"), ("macos", "arm64"), ("macos", "x64")])
        self.assertFalse(release.plan("v1.0.0", {"platforms": ["windows"]})["prerelease"])

    def test_prerelease_keeps_numeric_native_version(self):
        result = release.plan("v1.0.0-beta.12", {"platforms": ["macos"]})
        self.assertEqual(result["version"], "1.0.0-beta.12")
        self.assertEqual(result["build_name"], "1.0.0")
        self.assertTrue(result["prerelease"])
        self.assertTrue(all(t["platform"] == "macos" for t in result["matrix"]["include"]))

    def test_rejects_malformed_or_unsafe_tags(self):
        for tag in ("v1", "1.0.0", "v01.0.0", "v1.0.0-beta1.1", "v1.0.0-beta.0",
                    "v1.0.0-beta.01", "v1.0.0+42", "v1.0.0;echo hacked", "v1.0.0\n"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                release.plan(tag, {"platforms": ["windows"]})

    def test_rejects_invalid_platform_selection(self):
        for platforms in (None, [], "windows", ["linux"], ["windows", "windows"], [{}]):
            with self.subTest(platforms=platforms), self.assertRaises(ValueError):
                release.plan("v0.1.0", {"platforms": platforms})

    def test_prepare_updates_both_user_visible_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            client = root / "apps/client"
            (client / "lib/models").mkdir(parents=True)
            pubspec = client / "pubspec.yaml"
            info = client / "lib/models/app_info.dart"
            pubspec.write_text("name: example\nversion: 1.0.0+1\ndependencies: {}\n")
            info.write_text("const appVersion = '1.0.0+1';\nconst other = 'preserved';\n")
            release.prepare(root, "0.2.0-beta.2", "17")
            self.assertIn("version: 0.2.0-beta.2+17", pubspec.read_text())
            self.assertIn("const appVersion = '0.2.0-beta.2+17';", info.read_text())
            self.assertIn("const other = 'preserved';", info.read_text())
            before = pubspec.read_text()
            info.write_text("const renamedVersion = '1.0.0';")
            with self.assertRaises(ValueError):
                release.prepare(root, "0.3.0", "18")
            self.assertEqual(pubspec.read_text(), before)

    def make_windows_bundle(self, root):
        bundle = root / "apps/client/build/windows/x64/runner/Release"
        (bundle / "data/flutter_assets").mkdir(parents=True)
        for name in ("Nightcord Speak.exe", "nightcord_ffi.dll", "flutter_windows.dll",
                     "libwebrtc.dll", "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll",
                     "data/flutter_assets/AssetManifest.bin", "Nightcord Speak.pdb"):
            (bundle / name).write_bytes(b"bundle-content")
        return bundle

    def test_windows_archive_retains_assets_and_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_windows_bundle(root)
            # A local incremental build may retain the old launcher; never ship it.
            (root / "apps/client/build/windows/x64/runner/Release/nightcord_client.exe").write_bytes(b"old")
            release.package(root, "0.2.1", "19", "windows", "x64", "commit")
            release.verify(root, release.plan("v0.2.1", {"platforms": ["windows"]}), "19", "commit")
            with zipfile.ZipFile(next((root / "dist").glob("*.zip"))) as archive:
                names = archive.namelist()
                self.assertTrue(any(n.endswith("/Nightcord Speak.exe") for n in names))
                self.assertFalse(any(n.endswith("/nightcord_client.exe") for n in names))
                self.assertTrue(any(n.endswith("data/flutter_assets/AssetManifest.bin") for n in names))
                self.assertTrue(any(n.endswith("vcruntime140_1.dll") for n in names))
                self.assertFalse(any(n.endswith(".pdb") for n in names))

    def test_missing_core_prevents_packaging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = self.make_windows_bundle(root)
            (bundle / "nightcord_ffi.dll").unlink()
            with self.assertRaisesRegex(ValueError, "nightcord_ffi.dll"):
                release.package(root, "0.2.1", "19", "windows", "x64", "commit")

    def test_tampered_or_wrong_commit_artifacts_cannot_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_windows_bundle(root)
            release.package(root, "0.2.1", "19", "windows", "x64", "commit")
            plan = release.plan("v0.2.1", {"platforms": ["windows"]})
            with self.assertRaises(ValueError):
                release.verify(root, plan, "19", "other-commit")
            archive = next((root / "dist").glob("*.zip"))
            archive.write_bytes(archive.read_bytes() + b"tampered")
            with self.assertRaises(ValueError):
                release.verify(root, plan, "19", "commit")

    def test_unexpected_and_missing_artifacts_cannot_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_windows_bundle(root)
            release.package(root, "0.2.1", "19", "windows", "x64", "commit")
            plan = release.plan("v0.2.1", {"platforms": ["windows"]})
            extra = root / "dist/unrelated.zip"
            extra.write_bytes(b"unexpected")
            with self.assertRaises(ValueError):
                release.verify(root, plan, "19", "commit")
            extra.unlink()
            next((root / "dist").glob("*.sha256")).unlink()
            with self.assertRaises(FileNotFoundError):
                release.verify(root, plan, "19", "commit")


if __name__ == "__main__":
    unittest.main()
