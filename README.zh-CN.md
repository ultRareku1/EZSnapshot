# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · 首次发布**  
© 2026 ultRareku

EZSnapshot 是一款适用于 Apple Silicon Mac 的简洁原生截图与录屏应用。它使用 SwiftUI、AppKit、ScreenCaptureKit 和 AVFoundation 开发，无第三方运行依赖。

## 安装与运行

需要搭载 Apple Silicon 芯片、运行 macOS 14 或更高版本的 Mac。

使用 `build/EZSnapshot-1.0-Apple-Silicon.dmg` 安装时，打开磁盘映像，将 **EZSnapshot** 拖入**应用程序**文件夹。也可以解压 `build/EZSnapshot-1.0-Apple-Silicon.zip`，将 `EZSnapshot.app` 移入**应用程序**文件夹。本地构建后，可以直接打开 `build/EZSnapshot.app`。

首次截图时，请前往**系统设置 → 隐私与安全性 → 屏幕与系统音频录制**，允许 EZSnapshot 访问屏幕。较早的 macOS 版本将这一项称为**屏幕录制**。授权后返回 EZSnapshot；macOS 可能会要求重新打开应用。

## 截图

- **区域：**拖动框选要截取的范围。
- **窗口：**通过 macOS 原生选择器选择一个窗口。
- **全屏：**截取主显示器的完整画面。
- **Escape：**取消交互式截图。
- 应用运行时可使用全局快捷键：**Control + Option + 1**（区域）、**Control + Option + 2**（窗口）、**Control + Option + 3**（全屏）。
- 可从主窗口、菜单栏或全局快捷键发起截图。

截图默认保存到 `~/Pictures/EZSnapshot`。系统截图工具先将图片写入应用专用的临时文件夹，EZSnapshot 检查图片有效性后，再导出到所选文件夹。可以在“设置”中更改保存位置、PNG/JPEG 格式、截图延迟，以及全屏截图是否包含鼠标指针。

本地图库支持搜索、收藏、复制、分享、导出、重命名、在访达中显示，以及将截图移到废纸篓。标注编辑器提供画笔、矩形、椭圆、箭头、颜色、线宽和撤销功能。保存编辑后会生成一张新图片，保留原始像素分辨率。

## 录屏

在侧栏打开**录屏**，选择显示器或窗口。若要录制指定区域，先选择显示器，再框选录制范围。设置 30 或 60 帧/秒，按需开启系统音频和鼠标指针显示，然后点击**开始录制**。

录制时主窗口会隐藏。菜单栏每秒更新一次录制时长，并提供**停止录制**操作。编码器准备和录屏文件保存均在后台进行，保持界面响应。全局快捷键 **Control + Option + 4** 可开始或停止录制，也可重新打开主窗口使用停止按钮。录制过程中退出应用时，会提示先停止录制并保存。

录屏以 H.264 编码的 MP4 视频保存；开启系统音频时，音频采用 AAC 编码。视频与截图保存在同一个所选文件夹。系统音频根据所选录制内容采集，不录制麦克风声音。图库支持原生视频播放、缩略图、时长显示、收藏、分享、复制、重命名、导出，以及移到废纸篓。视频导出在后台复制文件，不会将整个视频载入内存。

Retina 录屏保留源画面的细节，最长边最高为 4096 像素，宽高使用符合 H.264 要求的偶数像素尺寸。录制流中断时，会尝试保存已捕获的可用画面。空录屏或失败的录屏不会加入图库，已有截图仍保持兼容。

录制和播放使用 macOS 自带框架。**无需 FFmpeg、Homebrew、下载额外编解码器或安装其他运行环境。** 所有应用代码均包含在应用包内。

## 语言与外观

“设置”提供带国旗标识的 8 种语言：英语（美国）、简体中文（中国）、繁体中文（台湾）、日语（日本）、韩语（韩国）、法语（法国）、德语（德国）和西班牙语（西班牙）。默认跟随 Mac 偏好语言中首个受支持的语言；若没有匹配项，则使用英语。语言切换立即生效，并在下次启动时保留。

支持浅色、深色和跟随系统外观。截图和图库元数据保存在你的 Mac 上，应用不会发起网络请求。

## 构建

安装 Xcode 或 Apple 命令行工具后，在项目根目录运行：

```sh
python3 Tools/build.py
```

此命令生成 `build/EZSnapshot.app`，添加应用图标和本地化资源，进行本地签名，并准备安装器背景素材。项目也提供 Swift Package，方便在 IDE 中使用。`swift build` 生成可执行文件；构建脚本则生成完整应用包，用于正常启动 macOS 应用并获取隐私权限。

若要制作带背景样式、支持拖拽安装的磁盘映像，先安装仅用于打包的工具，再生成 DMG：

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

生成文件为 `build/EZSnapshot-1.0-Apple-Silicon.dmg`。打包流程会在发布前验证应用签名和磁盘映像校验和。打包工具不会包含在应用内，运行应用也不需要这些工具。

如需使用其他工具链，将 `EZSNAPSHOT_TOOLCHAIN` 设置为该工具链的 `usr/bin` 目录，将 `EZSNAPSHOT_SDK` 设置为 Mac SDK 目录。

运行以下命令，检查本地化、Retina 导出、截图保存、原生 H.264/AAC 编码、图库兼容性、媒体导出和资源：

```sh
python3 Tools/check.py
```

编码检查使用合成画面和音频，无需屏幕录制权限。自动化沙盒环境需要允许访问 Apple 的视频和音频编码服务。实际屏幕捕获仍需 macOS 授权。

随附应用使用本地临时签名（ad-hoc）。公开分发需要使用 Apple Developer ID 签名并完成公证。
