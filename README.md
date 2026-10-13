# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · Initial release**  
© 2026 ultRareku

A quiet, native screenshot and screen recording app for Apple Silicon Macs. Built with SwiftUI, AppKit, ScreenCaptureKit, and AVFoundation, with no third-party dependencies.

## Run

Requires an Apple Silicon Mac running macOS 14 or later.

To install from `build/EZSnapshot-1.0-Apple-Silicon.dmg`, open the disk image and drag **EZSnapshot** to **Applications**. Alternatively, extract `build/EZSnapshot-1.0-Apple-Silicon.zip` and move `EZSnapshot.app` to **Applications**. For a local build, you can open `build/EZSnapshot.app` directly.

On first capture, allow EZSnapshot in **System Settings → Privacy & Security → Screen & System Audio Recording** (called **Screen Recording** on older macOS releases). Return to EZSnapshot; macOS may ask you to reopen the app.

## Capture

- **Region:** drag to select an area.
- **Window:** select a window using the native macOS picker.
- **Full screen:** capture the primary display.
- **Escape:** cancel an interactive capture.
- Global shortcuts, while EZSnapshot is running: **Control + Option + 1** (region), **Control + Option + 2** (window), **Control + Option + 3** (full screen).
- Capture from the window, the menu bar, or the global shortcuts.

Screenshots are saved to `~/Pictures/EZSnapshot` by default. The native capture utility writes into a private temporary directory; EZSnapshot validates the image and exports it to your chosen folder. Change the folder, PNG/JPEG format, capture delay, and full-screen pointer inclusion in Settings.

The local library supports search, favorites, copy, share, export, rename, Finder reveal, and moving screenshots to the Trash. The annotation editor includes pen, rectangle, ellipse, arrow, colors, line widths, and undo. Saving an edit creates a separate image at the original pixel resolution.

## Screen recording

Open **Record** in the sidebar. Choose a display or window; for a region, choose the display and select the area to record. Set 30 or 60 frames per second, optional system audio, and pointer visibility, then press **Start recording**.

The main window hides during recording. The menu bar shows elapsed time, updated once per second, and a **Stop recording** action. Encoder preparation and saving recordings run in the background so the interface remains responsive. **Control + Option + 4** starts or stops recording globally. Reopen the main window to use its stop button. Quitting during a recording offers to stop and save first.

Recordings are saved as H.264 MP4 videos, with AAC audio when enabled, in the same chosen folder as screenshots. System audio follows the selected content; microphone audio is not captured. The library provides native video playback, thumbnails, durations, favorites, sharing, copying, rename, export, and Trash deletion. Video export copies files in the background without loading whole videos into memory.

Retina video retains source detail up to 4096 pixels on the longest side, with even dimensions for H.264. Interrupted streams finalize any usable captured frames. Empty or failed recordings are not added to the library, and existing screenshots remain compatible.

Recording and playback use frameworks shipped with macOS. **FFmpeg, Homebrew, downloaded codecs, and additional runtime installations are not required.** All application code is contained in the app bundle.

## Languages and appearance

Settings provides flag-marked choices for English (US), Simplified Chinese (China), Traditional Chinese (Taiwan), Japanese (Japan), Korean (South Korea), French (France), German (Germany), and Spanish (Spain). The default follows your Mac's preferred supported language, falling back to English. Changes apply immediately and persist across launches.

Light, dark, and system appearances are available. Screenshots and library metadata stay on your Mac; the app makes no network requests.

## Build

Install Xcode or Apple's Command Line Tools, then run:

```sh
python3 Tools/build.py
```

This creates `build/EZSnapshot.app`, adds its icon and localized resources, signs it locally, and prepares the installer artwork. The source also includes a Swift Package for IDE use. Running `swift build` produces an executable; the build script produces the full app bundle needed for normal macOS launch and privacy permissions.

To package the styled drag-and-drop installer, install the build-only packaging tools once, then create the DMG:

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

The result is `build/EZSnapshot-1.0-Apple-Silicon.dmg`. Its application signature and disk-image checksums are verified before publication. The packaging tools are not included in the app and are not needed to run it.

For a different toolchain, set `EZSNAPSHOT_TOOLCHAIN` to its `usr/bin` directory and `EZSNAPSHOT_SDK` to the Mac SDK directory.

Run the localization, Retina export, screenshot saving, native H.264/AAC encoding, library compatibility, media export, and resource checks with:

```sh
python3 Tools/check.py
```

Encoding checks use synthetic frames and audio, so they do not require Screen Recording permission. Automated sandbox environments must allow access to Apple's video and audio encoding services. Live screen capture still requires macOS permission.

The included app uses a local ad-hoc signature. Public distribution requires signing with an Apple Developer ID and notarization.
