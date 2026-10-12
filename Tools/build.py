#!/usr/bin/env python3
"""Build a self-contained, locally signed Apple Silicon application."""
import os
from pathlib import Path
import shutil
import subprocess
import plistlib

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
APP = BUILD / "EZSnapshot.app"
VERSION = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["CFBundleShortVersionString"]
TOOLS = Path(os.environ.get("EZSNAPSHOT_TOOLCHAIN", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"))
SDK = Path(os.environ.get("EZSNAPSHOT_SDK", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"))
if not (TOOLS / "swiftc").exists() or not SDK.exists():
    TOOLS = Path("/Library/Developer/CommandLineTools/usr/bin")
    SDK = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
if not (TOOLS / "swiftc").exists() or not SDK.exists():
    raise SystemExit("Install Xcode or the Apple Command Line Tools before building.")

def run(arguments):
    subprocess.run([str(argument) for argument in arguments], cwd=ROOT, check=True)

for folder in [APP / "Contents/MacOS", APP / "Contents/Resources", BUILD / "AppIcon.iconset"]:
    folder.mkdir(parents=True, exist_ok=True)

common = [TOOLS / "swiftc", "-target", "arm64-apple-macosx14.0", "-sdk", SDK,
          "-module-cache-path", ROOT / ".build/module-cache", "-swift-version", "5"]
print("Compiling EZSnapshot for Apple Silicon…", flush=True)
run(common + ["-O", "-parse-as-library"] + sorted((ROOT / "Sources/EZSnapshot").glob("*.swift"))
    + ["-o", APP / "Contents/MacOS/EZSnapshot"])
print("Creating the application icon…", flush=True)
run(common + [ROOT / "Tools/GenerateIcon.swift", "-o", BUILD / "GenerateIcon"])
run([BUILD / "GenerateIcon", BUILD / "AppIcon.iconset"])
run(["/usr/bin/iconutil", "-c", "icns", BUILD / "AppIcon.iconset",
     "-o", APP / "Contents/Resources/AppIcon.icns"])
print("Creating the installer artwork…", flush=True)
run(common + [ROOT / "Tools/GenerateDMGArtwork.swift", "-o", BUILD / "GenerateDMGArtwork"])
run([BUILD / "GenerateDMGArtwork", BUILD / "dmg-artwork"])
shutil.copy2(ROOT / "Resources/Info.plist", APP / "Contents/Info.plist")
for resource in (ROOT / "Resources").glob("*.lproj"):
    shutil.copytree(resource, APP / "Contents/Resources" / resource.name, dirs_exist_ok=True)
run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", APP])
run(["/usr/bin/codesign", "--verify", "--strict", APP])
run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP,
     BUILD / f"EZSnapshot-{VERSION}-Apple-Silicon.zip"])
print(f"Built {APP}", flush=True)
