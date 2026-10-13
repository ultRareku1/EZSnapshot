# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · Erstveröffentlichung**  
© 2026 ultRareku

Eine unaufdringliche, native App für Screenshots und Bildschirmvideos auf Macs mit Apple Silicon. Entwickelt mit SwiftUI, AppKit, ScreenCaptureKit und AVFoundation, ohne Abhängigkeiten von Drittanbietern.

## Starten

Erfordert einen Mac mit Apple Silicon und macOS 14 oder neuer.

Zur Installation über `build/EZSnapshot-1.0-Apple-Silicon.dmg` öffne das Disk-Image und ziehe **EZSnapshot** in den Ordner **Programme**. Alternativ entpacke `build/EZSnapshot-1.0-Apple-Silicon.zip` und verschiebe `EZSnapshot.app` in **Programme**. Nach einem lokalen Build kannst du `build/EZSnapshot.app` direkt öffnen.

Erlaube EZSnapshot bei der ersten Aufnahme unter **Systemeinstellungen → Datenschutz & Sicherheit → Aufnahme von Bildschirm & Systemaudio** (in älteren macOS-Versionen **Bildschirmaufnahme**). Kehre anschließend zu EZSnapshot zurück; macOS fordert dich möglicherweise auf, die App erneut zu öffnen.

## Screenshots

- **Bereich:** Ziehe, um einen Bereich auszuwählen.
- **Fenster:** Wähle ein Fenster mit der nativen macOS-Auswahl aus.
- **Ganzer Bildschirm:** Nimm den primären Bildschirm auf.
- **Escape:** Brich eine interaktive Aufnahme ab.
- Globale Tastenkürzel bei laufendem EZSnapshot: **Control + Option + 1** (Bereich), **Control + Option + 2** (Fenster), **Control + Option + 3** (ganzer Bildschirm).
- Starte Aufnahmen im App-Fenster, in der Menüleiste oder mit den globalen Tastenkürzeln.

Screenshots werden standardmäßig in `~/Pictures/EZSnapshot` gespeichert. Das native Aufnahmeprogramm schreibt zunächst in ein privates temporäres Verzeichnis; EZSnapshot prüft das Bild und exportiert es in den gewählten Ordner. In den Einstellungen kannst du den Ordner, das PNG-/JPEG-Format, die Aufnahmeverzögerung und die Einbeziehung des Mauszeigers bei Aufnahmen des ganzen Bildschirms ändern.

Die lokale Mediathek bietet Suche, Favoriten, Kopieren, Teilen, Exportieren, Umbenennen, Anzeigen im Finder und das Verschieben von Screenshots in den Papierkorb. Der Anmerkungseditor umfasst Stift, Rechteck, Ellipse, Pfeil, Farben, Linienstärken und Rückgängig. Beim Speichern einer Bearbeitung entsteht ein separates Bild in der ursprünglichen Pixelauflösung.

## Bildschirmvideos

Öffne **Video** in der Seitenleiste. Wähle einen Bildschirm oder ein Fenster aus. Für einen Bereich wähle zunächst den Bildschirm und anschließend die aufzunehmende Fläche. Stelle 30 oder 60 Bilder pro Sekunde, optionales Systemaudio und die Sichtbarkeit des Mauszeigers ein und drücke **Aufnahme starten**.

Während der Aufnahme wird das Hauptfenster ausgeblendet. Die Menüleiste zeigt die verstrichene Zeit, die einmal pro Sekunde aktualisiert wird, sowie die Aktion **Aufnahme stoppen**. Die Vorbereitung des Encoders und das Speichern der Aufnahmen erfolgen im Hintergrund, damit die Oberfläche bedienbar bleibt. **Control + Option + 4** startet oder stoppt eine Aufnahme global. Öffne das Hauptfenster erneut, um dessen Stopptaste zu verwenden. Beim Beenden während einer Aufnahme bietet die App an, diese zuerst zu stoppen und zu speichern.

Aufnahmen werden als H.264-Videos im MP4-Format gespeichert, bei aktiviertem Ton mit AAC-Audio, im selben gewählten Ordner wie die Screenshots. Das Systemaudio richtet sich nach den ausgewählten Inhalten; Mikrofonton wird nicht aufgenommen. Die Mediathek bietet native Videowiedergabe, Vorschaubilder, Laufzeiten, Favoriten, Teilen, Kopieren, Umbenennen, Exportieren und das Verschieben in den Papierkorb. Beim Videoexport werden Dateien im Hintergrund kopiert, ohne vollständige Videos in den Arbeitsspeicher zu laden.

Retina-Videos erhalten die Details der Quelle bis zu 4096 Pixeln an der längsten Seite; für H.264 werden gerade Pixelabmessungen verwendet. Bei unterbrochenen Aufnahmeströmen werden alle bereits erfassten, verwendbaren Bilder zu einer fertigen Datei zusammengeführt. Leere oder fehlgeschlagene Aufnahmen werden nicht zur Mediathek hinzugefügt, und vorhandene Screenshots bleiben kompatibel.

Aufnahme und Wiedergabe verwenden die mit macOS gelieferten Frameworks. **FFmpeg, Homebrew, heruntergeladene Codecs und zusätzliche Laufzeitinstallationen sind nicht erforderlich.** Der gesamte Anwendungscode befindet sich im App-Bundle.

## Sprachen und Erscheinungsbild

In den Einstellungen stehen mit Flaggen gekennzeichnete Optionen für Englisch (USA), vereinfachtes Chinesisch (China), traditionelles Chinesisch (Taiwan), Japanisch (Japan), Koreanisch (Südkorea), Französisch (Frankreich), Deutsch (Deutschland) und Spanisch (Spanien) zur Verfügung. Standardmäßig folgt die App der bevorzugten unterstützten Sprache deines Mac und verwendet andernfalls Englisch. Änderungen gelten sofort und bleiben nach einem Neustart der App erhalten.

Ein helles, ein dunkles und das systemweite Erscheinungsbild stehen zur Verfügung. Screenshots und Metadaten der Mediathek bleiben auf deinem Mac; die App sendet keine Netzwerkanfragen.

## Erstellen

Installiere Xcode oder Apples Command Line Tools und führe anschließend Folgendes aus:

```sh
python3 Tools/build.py
```

Dies erstellt `build/EZSnapshot.app`, fügt das Symbol und die lokalisierten Ressourcen hinzu, signiert die App lokal und bereitet die Gestaltung des Installationsprogramms vor. Der Quellcode enthält außerdem ein Swift Package für die Verwendung in einer IDE. `swift build` erstellt eine ausführbare Datei; das Build-Skript erstellt das vollständige App-Bundle, das für den normalen Start unter macOS und die Datenschutzberechtigungen benötigt wird.

Um das gestaltete Installationsprogramm mit Drag-and-drop zu erstellen, installiere einmalig die nur zum Verpacken benötigten Werkzeuge und erstelle anschließend das DMG:

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

Das Ergebnis ist `build/EZSnapshot-1.0-Apple-Silicon.dmg`. Die Signatur der Anwendung und die Prüfsummen des Disk-Images werden vor der Veröffentlichung geprüft. Die Verpackungswerkzeuge sind nicht in der App enthalten und werden für deren Betrieb nicht benötigt.

Für eine andere Toolchain setze `EZSNAPSHOT_TOOLCHAIN` auf deren Verzeichnis `usr/bin` und `EZSNAPSHOT_SDK` auf das Verzeichnis des Mac-SDK.

Führe die Prüfungen für Lokalisierung, Retina-Export, Speichern von Screenshots, native H.264-/AAC-Kodierung, Kompatibilität der Mediathek, Medienexport und Ressourcen mit folgendem Befehl aus:

```sh
python3 Tools/check.py
```

Die Kodierungsprüfungen verwenden synthetische Bilder und Audiodaten und benötigen deshalb keine Berechtigung zur Bildschirmaufnahme. Automatisierte Sandbox-Umgebungen müssen den Zugriff auf Apples Dienste zur Video- und Audiokodierung erlauben. Die Aufnahme des tatsächlichen Bildschirms erfordert weiterhin die macOS-Berechtigung.

Die mitgelieferte App verwendet eine lokale Ad-hoc-Signatur. Für die öffentliche Verteilung sind die Signierung mit einer Apple Developer ID und die Notarisierung erforderlich.
