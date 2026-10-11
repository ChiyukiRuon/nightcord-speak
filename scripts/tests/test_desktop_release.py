"""Exercise release selection and reject incomplete or inconsistent artifacts."""

import importlib.util
import plistlib
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location(
    "desktop_release", Path(__file__).resolve().parents[1] / "desktop-release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_macos_package_requires_updater(self):
        # Publishing a bundle without its helper makes install-and-restart fail.
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "Missing macOS updater"):
                release.package(Path(directory), "0.2.1", "1", "macos", "arm64", "commit")

    def test_macos_signing_preserves_unsandboxed_helper_and_normalizes_xml(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "apps/client/build/macos/Build/Products/Release/Nightcord Speak.app/Contents/Helpers/NightcordUpdater.app/Contents"
            (helper / "MacOS").mkdir(parents=True)
            (helper / "MacOS/NightcordUpdater").write_bytes(b"fixture")
            (helper / "Info.plist").write_bytes(b"fixture")
            source = root / "apps/client/macos/Runner/Release.entitlements"
            source.parent.mkdir(parents=True)
            source.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}).replace(b"\n", b"\r\n"))
            def invoke(arguments, **kwargs):
                if arguments[:2] == ["codesign", "--force"]:
                    self.assertNotIn("--deep", arguments)
                    normalized = Path(arguments[arguments.index("--entitlements") + 1]).read_bytes()
                    self.assertNotIn(b"\r", normalized)
                    self.assertEqual(plistlib.loads(normalized), {"com.apple.security.app-sandbox": True})
                if arguments[0] == "ditto":
                    Path(arguments[-1]).write_bytes(b"fixture-archive")
            with patch.object(release.subprocess, "run", side_effect=invoke) as command:
                release.package(root, "0.2.1", "1", "macos", "arm64", "commit")
            self.assertTrue(any(call.args[0][:4] == ["codesign", "--verify", "--deep", "--strict"] for call in command.call_args_list))

    def test_macos_release_allows_udp_send_and_receive(self):
        # Release builds failed at UDP bind despite the user granting local network access.
        for name in ("Release", "DebugProfile"):
            with self.subTest(configuration=name):
                with (release.ROOT / f"apps/client/macos/Runner/{name}.entitlements").open("rb") as stream:
                    entitlements = plistlib.load(stream)
                for key in ("com.apple.security.network.client", "com.apple.security.network.server"):
                    self.assertIs(entitlements.get(key), True)

    def test_installer_excludes_only_root_user_sound_packs(self):
        # Unanchored sounds\* also removed assets/sounds and broke first-run extraction.
        script = (release.ROOT / "scripts/windows-installer.iss").read_text(encoding="utf-8")
        excludes = re.search(r'Excludes: "([^"]+)"', script).group(1).split(',')
        self.assertIn(r"\sounds\*", excludes)
        self.assertNotIn(r"sounds\*", excludes)

    def test_installer_detects_display_language_instead_of_previous_english(self):
        # Older installers only had English; upgrades must detect the system again.
        script = (release.ROOT / "scripts/windows-installer.iss").read_text(encoding="utf-8")
        self.assertIn("LanguageDetectionMethod=uilanguage", script)
        self.assertIn("UsePreviousLanguage=no", script)
        self.assertIn("ShowLanguageDialog=yes", script)
        languages = re.findall(r"^Name: (\w+); MessagesFile:", script, flags=re.M)
        self.assertEqual(languages, ["english", "chinesesimplified", "chinesetraditional", "japanese", "korean"])
        for name, lang_id in (("ChineseSimplified", "$0804"), ("ChineseTraditional", "$0404")):
            messages = (release.ROOT / f"scripts/installer-languages/{name}.isl").read_text(encoding="utf-8-sig")
            self.assertIn(f"LanguageID={lang_id}", messages)
            self.assertIn("[Messages]", messages)
            self.assertIn("LaunchProgram=", messages)

    def setUp(self):
        # Unit tests validate artifact handling without executing an installer compiler.
        def fake_installer(root, version, bundle, destination):
            path = destination / f"Nightcord-Speak-{version}-windows-x64-setup.exe"
            path.write_bytes(b"installer-content")
            return path
        compiler = patch.object(release, "build_installer", side_effect=fake_installer)
        compiler.start()
        self.addCleanup(compiler.stop)

    def test_installer_tampering_prevents_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_windows_bundle(root)
            release.package(root, "0.2.1", "19", "windows", "x64", "commit")
            next((root / "dist").glob("*.exe")).write_bytes(b"tampered")
            with self.assertRaises(ValueError):
                release.verify(root, release.plan("v0.2.1", {"platforms": ["windows"]}), "19", "commit")

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
        sounds = bundle / "data/flutter_assets/assets/sounds/nightcord"
        sounds.mkdir(parents=True)
        for name in ("config.json", "connected.wav", "disconnected.wav", "new_message.wav"):
            (sounds / name).write_bytes(b"bundled-sound")
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
            sounds = root / "apps/client/build/windows/x64/runner/Release/sounds/private"
            sounds.mkdir(parents=True)
            (sounds / "config.json").write_bytes(b"user-config")
            release.package(root, "0.2.1", "19", "windows", "x64", "commit")
            release.verify(root, release.plan("v0.2.1", {"platforms": ["windows"]}), "19", "commit")
            with zipfile.ZipFile(next((root / "dist").glob("*.zip"))) as archive:
                names = archive.namelist()
                self.assertTrue(any(n.endswith("/Nightcord Speak.exe") for n in names))
                self.assertFalse(any(n.endswith("/nightcord_client.exe") for n in names))
                self.assertTrue(any(n.endswith("data/flutter_assets/AssetManifest.bin") for n in names))
                self.assertTrue(any(n.endswith("vcruntime140_1.dll") for n in names))
                self.assertFalse(any(n.endswith(".pdb") for n in names))
                self.assertFalse(any(n.startswith("Nightcord-Speak-0.2.1-windows-x64/sounds/") for n in names))
                for name in ("config.json", "connected.wav", "disconnected.wav", "new_message.wav"):
                    self.assertTrue(any(n.endswith(f"/data/flutter_assets/assets/sounds/nightcord/{name}") for n in names))

    def test_missing_bundled_sound_prevents_packaging(self):
        # The manifest alone is insufficient: extraction loads every shipped default.
        for name in ("config.json", "connected.wav", "disconnected.wav", "new_message.wav"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                bundle = self.make_windows_bundle(root)
                (bundle / "data/flutter_assets/assets/sounds/nightcord" / name).unlink()
                with self.assertRaisesRegex(ValueError, re.escape(name)):
                    release.package(root, "0.2.1", "19", "windows", "x64", "commit")

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
