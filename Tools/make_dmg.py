#!/usr/bin/env python3
"""Create EZSnapshot's styled, compressed Apple Silicon disk image.

Prepare the packaging tools once:
    python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt

Then run:
    python3 Tools/make_dmg.py

This script writes Finder metadata directly. It does not control Finder, require
automation permission, or add Python libraries to the application. All temporary
images and mount points live in a unique folder under .build/dmg-work.
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
DEPENDENCIES = ROOT / ".build/dmg-python"
WINDOW_BOUNDS = "{{180, 140}, {760, 500}}"
ICON_POSITIONS = {"EZSnapshot.app": (205, 265), "Applications": (555, 265)}
DEVICE_PATTERN = re.compile(r"/dev/disk\d+(?:s\d+)*\Z")


def run(arguments: list[str | Path], *, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(argument) for argument in arguments],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def image_devices(image: Path) -> list[str]:
    """Return only devices belonging to this run's exact image path."""
    info = plistlib.loads(run(["/usr/bin/hdiutil", "info", "-plist"], capture=True).stdout)
    for attached_image in info.get("images", []):
        image_path = attached_image.get("image-path")
        if not image_path or Path(image_path).resolve() != image.resolve():
            continue
        devices = [
            entity["dev-entry"]
            for entity in attached_image.get("system-entities", [])
            if DEVICE_PATTERN.fullmatch(entity.get("dev-entry", ""))
        ]
        # Prefer the whole disk when the image has a partition map.
        whole_disks = [device for device in devices if re.fullmatch(r"/dev/disk\d+", device)]
        return whole_disks or devices[:1]
    return []


def detach_image(image: Path) -> None:
    """Detach this run's image, without touching other mounted volumes."""
    for delay in (0, 1, 2, 3):
        devices = image_devices(image)
        if not devices:
            return
        if delay:
            time.sleep(delay)
        result = subprocess.run(
            ["/usr/bin/hdiutil", "detach", devices[0]],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode == 0:
            return
    # A forced detach is restricted to the exact temporary image we created.
    devices = image_devices(image)
    if devices:
        run(["/usr/bin/hdiutil", "detach", "-force", devices[0]])
    if image_devices(image):
        raise RuntimeError(f"Could not detach temporary image: {image}")


def attach_image(image: Path, mount: Path, *, readonly: bool = False) -> None:
    arguments: list[str | Path] = [
        "/usr/bin/hdiutil", "attach", "-nobrowse", "-noautoopen", "-owners", "off",
        "-mountpoint", mount, "-plist",
    ]
    if readonly:
        arguments.append("-readonly")
    arguments.append(image)
    attached = plistlib.loads(run(arguments, capture=True).stdout)
    entities = attached.get("system-entities", [])
    if not any(
        entity.get("mount-point") and Path(entity["mount-point"]).resolve() == mount.resolve()
        for entity in entities
    ):
        raise RuntimeError(f"The temporary image did not mount at {mount}")


def folder_size(folder: Path) -> int:
    return sum(
        file.lstat().st_size
        for directory, _, names in os.walk(folder, followlinks=False)
        for name in names
        if (file := Path(directory) / name).is_file() and not file.is_symlink()
    )


def write_finder_metadata(mount: Path, DSStore, Alias) -> None:
    background_alias = Alias.for_file(str(mount / ".background/installer.tiff"))
    # The relative target path and volume/CNID identity let Finder resolve the
    # background after the image is mounted on a different Mac.
    bwsp = {
        "WindowBounds": WINDOW_BOUNDS,
        "ShowStatusBar": False,
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
    }
    icvp = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "backgroundImageAlias": background_alias.to_bytes(),
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": False,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 14.0,
        "iconSize": 128.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
        store["."]["vSrn"] = ("long", 1)
        store["."]["bwsp"] = bwsp
        store["."]["icvp"] = icvp
        store["."]["icvl"] = ("type", b"icnv")
        for name, position in ICON_POSITIONS.items():
            store[name]["Iloc"] = position


def verify_contents(mount: Path, source_info: dict, DSStore, Alias) -> None:
    installed_app = mount / "EZSnapshot.app"
    info = plistlib.loads((installed_app / "Contents/Info.plist").read_bytes())
    if info != source_info:
        raise RuntimeError("The packaged application's metadata differs from the source application.")
    if not (mount / "Applications").is_symlink() or os.readlink(mount / "Applications") != "/Applications":
        raise RuntimeError("The installer is missing its Applications shortcut.")
    run(["/usr/bin/codesign", "--verify", "--strict", installed_app])
    with DSStore.open(str(mount / ".DS_Store"), "r") as store:
        if store["."]["bwsp"]["WindowBounds"] != WINDOW_BOUNDS:
            raise RuntimeError("The installer window bounds were not saved.")
        for name, position in ICON_POSITIONS.items():
            if tuple(store[name]["Iloc"]) != position:
                raise RuntimeError(f"The installer position was not saved for {name}.")
        alias = Alias.from_bytes(store["."]["icvp"]["backgroundImageAlias"])
        if str(alias.target.posix_path).lstrip("/") != ".background/installer.tiff":
            raise RuntimeError("The installer background does not point inside the disk image.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, default=ROOT / "build/EZSnapshot.app")
    parser.add_argument("--background", type=Path, default=ROOT / "build/dmg-artwork/background.tiff")
    parser.add_argument("--output", type=Path, help="Defaults to build/EZSnapshot-VERSION-Apple-Silicon.dmg")
    parser.add_argument("--volume-name", default="EZSnapshot")
    arguments = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("DMG packaging requires macOS.")

    sys.path.insert(0, str(DEPENDENCIES))
    try:
        from ds_store import DSStore
        from mac_alias import Alias
    except ImportError as error:
        raise SystemExit(
            "Install the packaging-only dependencies first:\n"
            "python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt"
        ) from error

    app = arguments.app.resolve()
    background = arguments.background.resolve()
    if not (app / "Contents/Info.plist").is_file() or not background.is_file():
        parser.error("Build EZSnapshot.app and its DMG background before packaging.")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    version = str(info["CFBundleShortVersionString"])
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
        parser.error("The application version must contain only numbers and periods.")
    icon_name = info.get("CFBundleIconFile", "AppIcon.icns")
    if not icon_name.endswith(".icns"):
        icon_name += ".icns"
    icon = app / "Contents/Resources" / icon_name
    if not icon.is_file():
        parser.error(f"The application icon is missing: {icon}")
    run(["/usr/bin/codesign", "--verify", "--strict", app])
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    run(["/usr/bin/lipo", "-verify_arch", "arm64", executable])

    output = (arguments.output or ROOT / f"build/EZSnapshot-{version}-Apple-Silicon.dmg").resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    work_base = ROOT / ".build/dmg-work"
    work_base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="package-", dir=work_base))
    mount = work / "mount"
    mount.mkdir()
    writable = work / "installer-writable.dmg"
    compressed = work / "installer-final.dmg"
    images = (writable, compressed)

    try:
        payload_size = folder_size(app) + background.stat().st_size
        size_megabytes = math.ceil(payload_size / (1024 * 1024)) + 128
        print(f"Creating EZSnapshot {version} installer…", flush=True)
        run([
            "/usr/bin/hdiutil", "create", "-size", f"{size_megabytes}m", "-fs", "HFS+",
            "-volname", arguments.volume_name, "-layout", "NONE", "-type", "UDIF",
            "-nospotlight", writable,
        ])
        attach_image(writable, mount)
        run(["/usr/bin/ditto", app, mount / "EZSnapshot.app"])
        (mount / "Applications").symlink_to("/Applications", target_is_directory=True)
        (mount / ".background").mkdir()
        shutil.copy2(background, mount / ".background/installer.tiff")
        shutil.copy2(icon, mount / ".VolumeIcon.icns")
        run(["/usr/bin/SetFile", "-a", "C", mount])
        run(["/usr/bin/SetFile", "-a", "E", mount / "EZSnapshot.app"])
        run(["/usr/bin/SetFile", "-a", "V", mount / ".background"])
        write_finder_metadata(mount, DSStore, Alias)
        verify_contents(mount, info, DSStore, Alias)
        run(["/bin/sync"])
        detach_image(writable)

        print("Compressing the installer…", flush=True)
        run(["/usr/bin/hdiutil", "resize", "-sectors", "min", writable])
        run([
            "/usr/bin/hdiutil", "convert", writable, "-format", "UDZO", "-imagekey",
            "zlib-level=9", "-o", compressed,
        ])
        run(["/usr/bin/hdiutil", "verify", compressed])
        attach_image(compressed, mount, readonly=True)
        verify_contents(mount, info, DSStore, Alias)
        detach_image(compressed)
        os.replace(compressed, output)
        print(f"Built and verified {output}", flush=True)
    finally:
        # Always attempt cleanup, including an attach that failed after creating
        # a device. Resolve ownership through the exact image path every time.
        cleanup_error = None
        for image in images:
            try:
                detach_image(image)
            except Exception as error:
                cleanup_error = error
                print(f"Temporary image cleanup failed: {error}", file=sys.stderr)
        if cleanup_error is None:
            shutil.rmtree(work)
        else:
            print(f"Temporary files retained at {work}", file=sys.stderr)
            raise cleanup_error
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        if error.stderr:
            print(error.stderr.decode(errors="replace").strip(), file=sys.stderr)
        raise SystemExit(f"DMG packaging failed: {error}") from error
