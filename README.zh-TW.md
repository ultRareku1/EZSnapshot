# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · 首次發行**  
© 2026 ultRareku

適用於 Apple Silicon Mac 的原生截圖與螢幕錄影 App，簡潔、安靜，不打擾工作。使用 SwiftUI、AppKit、ScreenCaptureKit 與 AVFoundation 開發，無第三方相依套件。

## 執行

需要執行 macOS 14 或更新版本的 Apple Silicon Mac。

若要從 `build/EZSnapshot-1.0-Apple-Silicon.dmg` 安裝，請開啟磁碟映像檔，將 **EZSnapshot** 拖曳至「**應用程式**」。也可以解壓縮 `build/EZSnapshot-1.0-Apple-Silicon.zip`，再將 `EZSnapshot.app` 移至「**應用程式**」。若是在本機建置，可直接開啟 `build/EZSnapshot.app`。

首次擷取時，請在「**系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製**」中允許 EZSnapshot（舊版 macOS 中稱為「**螢幕錄製**」）。接著返回 EZSnapshot；macOS 可能會要求重新開啟 App。

## 截圖

- **範圍：**拖曳以選取範圍。
- **視窗：**使用 macOS 原生選取器選取視窗。
- **全螢幕：**擷取主要顯示器的畫面。
- **Escape：**取消正在進行的互動式截圖。
- EZSnapshot 執行期間可使用全域快速鍵：**Control + Option + 1**（範圍）、**Control + Option + 2**（視窗）、**Control + Option + 3**（全螢幕）。
- 可從 App 視窗、選單列或全域快速鍵擷取截圖。

截圖預設儲存在 `~/Pictures/EZSnapshot`。原生截圖工具會先將影像寫入私有的暫存目錄；EZSnapshot 驗證影像後，再將其輸出至你選擇的檔案夾。你可以在「設定」中變更儲存檔案夾、PNG/JPEG 格式、截圖延遲，以及全螢幕截圖是否包含滑鼠指標。

本機圖庫支援搜尋、收藏、複製、分享、輸出、重新命名、在 Finder 中顯示，以及將截圖移至垃圾桶。註記編輯器提供畫筆、矩形、橢圓、箭頭、顏色、線條寬度與復原功能。儲存編輯結果時，會以原始像素解析度建立另一張影像。

## 螢幕錄影

在側邊欄開啟「**錄影**」，選擇顯示器或視窗；若要錄製部分範圍，請先選擇顯示器，再選取要錄製的範圍。設定每秒 30 或 60 影格、是否包含系統音訊，以及是否顯示滑鼠指標，然後按下「**開始錄影**」。

錄影期間主視窗會隱藏。選單列會顯示錄影時間，每秒更新一次，並提供「**停止錄影**」操作。編碼器準備與影音檔案的最終儲存作業會在背景執行，讓介面保持流暢。**Control + Option + 4** 可全域開始或停止錄影。你也可以重新開啟主視窗，使用其中的停止按鈕。若在錄影期間結束 App，會提供先停止並儲存錄影的選項。

錄影以 H.264 MP4 影片儲存在與截圖相同的自選檔案夾；啟用音訊時，使用 AAC 編碼。系統音訊會依所選的錄製內容擷取；不會錄製麥克風音訊。圖庫提供原生影片播放、縮圖、影片長度、收藏、分享、複製、重新命名、輸出與移至垃圾桶等功能。影片輸出會在背景複製檔案，不會將整部影片載入記憶體。

Retina 影片保留來源細節，最長邊最高可達 4096 像素，並使用符合 H.264 要求的偶數尺寸。錄製串流意外中斷時，會使用已擷取且可用的影格完成影片儲存。沒有內容或失敗的錄影不會加入圖庫，既有截圖也仍可正常使用。

錄影與播放使用 macOS 內建框架。**不需要 FFmpeg、Homebrew、下載的編解碼器或額外的執行環境安裝。**所有應用程式程式碼都包含在 App 套件內。

## 語言與外觀

「設定」提供附國旗標示的語言選項：英文（美國）、簡體中文（中國）、繁體中文（台灣）、日文（日本）、韓文（南韓）、法文（法國）、德文（德國）與西班牙文（西班牙）。預設會採用 Mac 偏好語言中受支援的語言，若沒有符合的語言則使用英文。變更會立即生效，並在重新啟動後保留。

提供淺色、深色與跟隨系統的外觀。截圖與圖庫中繼資料都保留在你的 Mac 上；App 不會發出任何網路請求。

## 建置

安裝 Xcode 或 Apple 的 Command Line Tools，然後執行：

```sh
python3 Tools/build.py
```

這會建立 `build/EZSnapshot.app`、加入圖示與本地化資源、以本機簽章簽署，並準備安裝程式的視覺素材。原始碼也包含供 IDE 使用的 Swift Package。執行 `swift build` 會產生可執行檔；建置腳本則會產生完整的 App 套件，供一般 macOS 啟動與隱私權授權使用。

若要製作含自訂外觀的拖曳安裝程式，請先安裝一次僅供建置使用的封裝工具，再建立 DMG：

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

產生的檔案為 `build/EZSnapshot-1.0-Apple-Silicon.dmg`。發布前會驗證應用程式簽章與磁碟映像檔檢查碼。封裝工具不會包含在 App 內，執行 App 時也不需要這些工具。

若要使用其他工具鏈，請將 `EZSNAPSHOT_TOOLCHAIN` 設為該工具鏈的 `usr/bin` 目錄，並將 `EZSNAPSHOT_SDK` 設為 Mac SDK 目錄。

執行以下指令，以檢查本地化、Retina 輸出、截圖儲存、原生 H.264/AAC 編碼、圖庫相容性、影音輸出與資源：

```sh
python3 Tools/check.py
```

編碼檢查使用合成影格與音訊，因此不需要螢幕錄製權限。自動化沙盒環境必須允許存取 Apple 的影片與音訊編碼服務。實際擷取螢幕仍需要 macOS 授權。

隨附的 App 使用本機的 ad-hoc 簽章。公開散布時，需要使用 Apple Developer ID 簽署並完成公證。
