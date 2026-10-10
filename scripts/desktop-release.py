"""Plan tag releases and package desktop bundles without third-party dependencies."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    "windows": [{"os": "windows-2022", "platform": "windows", "arch": "x64"}],
    "macos": [
        {"os": "macos-15", "platform": "macos", "arch": "arm64"},
        {"os": "macos-15-intel", "platform": "macos", "arch": "x64"},
    ],
}
TAG_PATTERN = re.compile(
    r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(alpha|beta|rc)\.([1-9][0-9]*))?"
)


def plan(tag, config):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError("Expected vX.Y.Z or vX.Y.Z-alpha.N / beta.N / rc.N")
    platforms = config.get("platforms")
    if (not isinstance(platforms, list) or not platforms
            or any(not isinstance(p, str) or p not in TARGETS for p in platforms)
            or len(set(platforms)) != len(platforms)):
        raise ValueError("platforms must be a nonempty, unique list of windows / macos")
    return {
        "version": tag[1:],
        "build_name": ".".join(match.group(1, 2, 3)),
        "prerelease": match.group(1) == "0" or match.group(4) is not None,
        "matrix": {"include": [target for p in platforms for target in TARGETS[p]]},
    }


def prepare(root, version, build_number):
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise ValueError("Build number must be a positive integer")
    full_version = f"{version}+{build_number}"
    pubspec = root / "apps/client/pubspec.yaml"
    updated, count = re.subn(r"^version:.*$", f"version: {full_version}",
                             pubspec.read_text(encoding="utf-8"), flags=re.M)
    if count != 1:
        raise ValueError("Expected exactly one pubspec version")
    app_info = root / "apps/client/lib/models/app_info.dart"
    info, count = re.subn(r"const appVersion = '[^']*';",
                         f"const appVersion = '{full_version}';",
                         app_info.read_text(encoding="utf-8"))
    if count != 1:
        raise ValueError("Expected exactly one appVersion")
    pubspec.write_text(updated, encoding="utf-8")
    app_info.write_text(info, encoding="utf-8")


def build_installer(root, version, bundle, destination):
    compiler = os.environ.get("INNO_SETUP_COMPILER") or shutil.which("ISCC.exe")
    if not compiler:
        compiler = r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    subprocess.run([
        compiler, f"/DProductVersion={version}",
        f"/DNumericVersion={version.split('-')[0]}",
        f"/DBundleDir={bundle}", f"/DOutputDir={destination}",
        str(root / "scripts/windows-installer.iss"),
    ], check=True)
    installer = destination / f"Nightcord-Speak-{version}-windows-x64-setup.exe"
    if not installer.is_file():
        raise ValueError("Installer compiler did not produce the expected setup executable")
    return installer


def write_manifest(artifact, version, build_number, platform, arch, revision):
    with artifact.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    artifact.with_suffix(".sha256").write_text(
        f"{digest}  {artifact.name}\n", encoding="utf-8")
    artifact.with_suffix(".json").write_text(json.dumps({
        "version": version, "build_number": build_number, "platform": platform,
        "arch": arch, "revision": revision, "archive": artifact.name, "sha256": digest,
    }, indent=2) + "\n", encoding="utf-8")


def package(root, version, build_number, platform, arch, revision):
    destination = root / "dist"
    destination.mkdir(exist_ok=True)
    stem = f"Nightcord-Speak-{version}-{platform}-{arch}"
    archive = destination / f"{stem}.zip"
    if platform == "windows":
        bundle = root / "apps/client/build/windows/x64/runner/Release"
        for name in ("Nightcord Speak.exe", "nightcord_ffi.dll", "flutter_windows.dll",
                     "libwebrtc.dll", "msvcp140.dll", "vcruntime140.dll",
                     "vcruntime140_1.dll", "data/flutter_assets"):
            if not (bundle / name).exists():
                raise ValueError(f"Missing Windows bundle component: {name}")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
            for file in sorted(bundle.rglob("*")):
                if (file.is_file() and file.suffix.lower() != ".pdb"
                        and file.relative_to(bundle).parts[0] != "sounds"
                        and file.name != "nightcord_client.exe"):
                    output.write(file, Path(stem) / file.relative_to(bundle))
    else:
        bundle = root / "apps/client/build/macos/Build/Products/Release/Nightcord Speak.app"
        native_arch = "arm64" if arch == "arm64" else "x86_64"
        for relative in ("Contents/MacOS/Nightcord Speak",
                         "Contents/Frameworks/libnightcord_ffi.dylib"):
            subprocess.run(["lipo", str(bundle / relative), "-verify_arch", native_arch],
                           check=True)
        # Rust is copied by an Xcode script phase; sign the complete final bundle.
        subprocess.run(["codesign", "--force", "--deep", "--sign", "-", "--entitlements",
                        str(root / "apps/client/macos/Runner/Release.entitlements"),
                        str(bundle)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
        # ditto preserves framework symlinks, executable modes and bundle metadata.
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
                        str(bundle), str(archive)], check=True)
    write_manifest(archive, version, build_number, platform, arch, revision)
    if platform == "windows":
        installer = build_installer(root, version, bundle, destination)
        write_manifest(installer, version, build_number, platform, arch, revision)


def verify(root, release, build_number, revision):
    expected = set()
    artifacts = []
    for target in release["matrix"]["include"]:
        stem = f"Nightcord-Speak-{release['version']}-{target['platform']}-{target['arch']}"
        artifacts.append((target, stem, "zip"))
        if target["platform"] == "windows":
            artifacts.append((target, stem + "-setup", "exe"))
    for target, stem, extension in artifacts:
        expected.update(f"{stem}.{suffix}" for suffix in (extension, "sha256", "json"))
        manifest = json.loads((root / "dist" / f"{stem}.json").read_text(encoding="utf-8"))
        with (root / "dist" / f"{stem}.{extension}").open("rb") as archive:
            digest = hashlib.file_digest(archive, "sha256").hexdigest()
        if (manifest["revision"] != revision
                or manifest["version"] != release["version"]
                or manifest["build_number"] != build_number
                or manifest["platform"] != target["platform"]
                or manifest["arch"] != target["arch"]
                or manifest["archive"] != f"{stem}.{extension}"
                or manifest["sha256"] != digest
                or (root / "dist" / f"{stem}.sha256").read_text(encoding="utf-8")
                != f"{digest}  {stem}.{extension}\n"):
            raise ValueError(f"Release artifact mismatch: {stem}")
    if {f.name for f in (root / "dist").iterdir()} != expected:
        raise ValueError("Release artifact set does not match the selected platforms")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("plan", "prepare", "package", "verify"))
    parser.add_argument("--tag", default=os.environ.get("GITHUB_REF_NAME", ""))
    parser.add_argument("--build-number", default=os.environ.get("GITHUB_RUN_NUMBER", ""))
    parser.add_argument("--platform", choices=TARGETS)
    parser.add_argument("--arch", choices=("x64", "arm64"))
    args = parser.parse_args()
    release = plan(args.tag, json.loads(
        (ROOT / ".github/release-platforms.json").read_text(encoding="utf-8")))
    if args.command == "plan":
        values = {**release, "matrix": json.dumps(release["matrix"], separators=(",", ":"))}
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n")
    elif args.command == "prepare":
        prepare(ROOT, release["version"], args.build_number)
    elif args.command == "package":
        if not any(t["platform"] == args.platform and t["arch"] == args.arch
                   for t in release["matrix"]["include"]):
            raise ValueError("Target is not selected by release-platforms.json")
        package(ROOT, release["version"], args.build_number, args.platform, args.arch,
                os.environ["GITHUB_SHA"])
    else:
        verify(ROOT, release, args.build_number, os.environ["GITHUB_SHA"])


if __name__ == "__main__":
    main()
