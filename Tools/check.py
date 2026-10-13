#!/usr/bin/env python3
"""Verify localization, image export, library compatibility, and native video encoding."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
TOOLS = Path(os.environ.get("EZSNAPSHOT_TOOLCHAIN", "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"))
SDK = Path(os.environ.get("EZSNAPSHOT_SDK", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"))
if not (TOOLS / "swiftc").exists() or not SDK.exists():
    TOOLS = Path("/Library/Developer/CommandLineTools/usr/bin")
    SDK = Path("/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
OUTPUT = ROOT / ".build/checks"
OUTPUT.mkdir(parents=True, exist_ok=True)
common = [str(TOOLS / "swiftc"), "-parse-as-library", "-target", "arm64-apple-macosx14.0",
          "-sdk", str(SDK), "-module-cache-path", str(ROOT / ".build/module-cache")]
sources = ROOT / "Sources/EZSnapshot"
for name, dependencies in [
    ("LocalizationChecks", [sources / "Localization.swift"]),
    ("ImageChecks", [sources / "Models.swift", sources / "Localization.swift"]),
    ("CaptureChecks", [sources / "Models.swift", sources / "Localization.swift", sources / "CaptureService.swift"]),
    ("MediaModelChecks", [sources / "Models.swift", sources / "Localization.swift", sources / "FileExport.swift"]),
    ("RecordingChecks", [sources / name for name in
                        ["Models.swift", "Localization.swift", "CaptureService.swift", "RecordingService.swift", "RecordingWriter.swift"]])
]:
    binary = OUTPUT / name
    subprocess.run(common + [str(source) for source in dependencies]
                   + [str(ROOT / "Tests" / f"{name}.swift"), "-o", str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True)
for resource in sorted((ROOT / "Resources").glob("*.lproj/InfoPlist.strings")):
    subprocess.run(["/usr/bin/plutil", "-lint", str(resource)], check=True)
print("All checks passed.")
