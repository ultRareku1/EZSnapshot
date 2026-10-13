# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · Primera versión**  
© 2026 ultRareku

Una app discreta y nativa para hacer capturas y grabar la pantalla en Macs con Apple Silicon. Desarrollada con SwiftUI, AppKit, ScreenCaptureKit y AVFoundation, sin dependencias de terceros.

## Ejecutar

Requiere un Mac con Apple Silicon y macOS 14 o posterior.

Para instalar desde `build/EZSnapshot-1.0-Apple-Silicon.dmg`, abre la imagen de disco y arrastra **EZSnapshot** a **Aplicaciones**. También puedes descomprimir `build/EZSnapshot-1.0-Apple-Silicon.zip` y mover `EZSnapshot.app` a **Aplicaciones**. Si has compilado la app localmente, puedes abrir `build/EZSnapshot.app` directamente.

Al realizar la primera captura, permite EZSnapshot en **Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema** (denominado **Grabación de pantalla** en versiones anteriores de macOS). Vuelve a EZSnapshot; macOS puede pedirte que abras la app de nuevo.

## Capturas de pantalla

- **Área:** arrastra para seleccionar una zona.
- **Ventana:** selecciona una ventana con el selector nativo de macOS.
- **Pantalla completa:** captura la pantalla principal.
- **Escape:** cancela una captura interactiva.
- Atajos globales mientras EZSnapshot está en ejecución: **Control + Option + 1** (área), **Control + Option + 2** (ventana), **Control + Option + 3** (pantalla completa).
- Realiza capturas desde la ventana, la barra de menús o los atajos globales.

Las capturas se guardan de forma predeterminada en `~/Pictures/EZSnapshot`. La utilidad nativa de captura escribe en un directorio temporal privado; EZSnapshot comprueba la imagen y la exporta a la carpeta que hayas elegido. En Ajustes puedes cambiar la carpeta, el formato PNG/JPEG, el retardo de captura y la inclusión del puntero en las capturas de pantalla completa.

La biblioteca local permite buscar, añadir a favoritos, copiar, compartir, exportar, cambiar el nombre, mostrar en el Finder y mover capturas a la Papelera. El editor de anotaciones incluye lápiz, rectángulo, elipse, flecha, colores, grosores de línea y la función de deshacer. Al guardar una edición se crea una imagen independiente con la resolución en píxeles del original.

## Grabación de pantalla

Abre **Grabar** en la barra lateral. Elige una pantalla o una ventana; para grabar un área, elige la pantalla y selecciona la zona que quieres grabar. Configura 30 o 60 fotogramas por segundo, el audio del sistema opcional y la visibilidad del puntero, y pulsa **Iniciar grabación**.

La ventana principal se oculta durante la grabación. La barra de menús muestra el tiempo transcurrido, que se actualiza una vez por segundo, y la acción **Detener grabación**. La preparación del codificador y el guardado de las grabaciones se realizan en segundo plano para que la interfaz siga respondiendo. **Control + Option + 4** inicia o detiene la grabación de forma global. Vuelve a abrir la ventana principal para usar su botón de detener. Si sales durante una grabación, la app ofrece detenerla y guardarla primero.

Las grabaciones se guardan como vídeos MP4 con H.264 y audio AAC cuando está activado, en la misma carpeta elegida para las capturas. El audio del sistema corresponde al contenido seleccionado; no se captura audio del micrófono. La biblioteca ofrece reproducción de vídeo nativa, miniaturas, duraciones, favoritos, opciones para compartir y copiar, cambio de nombre, exportación y eliminación mediante la Papelera. La exportación de vídeos copia los archivos en segundo plano sin cargar los vídeos completos en memoria.

Los vídeos Retina conservan el detalle de la fuente hasta un máximo de 4096 píxeles en el lado más largo, con dimensiones pares para H.264. Si se interrumpe el flujo de captura, se finaliza la grabación con los fotogramas capturados que sean utilizables. Las grabaciones vacías o fallidas no se añaden a la biblioteca, y las capturas existentes siguen siendo compatibles.

La grabación y la reproducción utilizan los frameworks incluidos en macOS. **No se necesitan FFmpeg, Homebrew, códecs descargados ni instalaciones adicionales de entornos de ejecución.** Todo el código de la aplicación está contenido en el paquete de la app.

## Idiomas y apariencia

En Ajustes hay opciones identificadas con banderas para inglés (Estados Unidos), chino simplificado (China), chino tradicional (Taiwán), japonés (Japón), coreano (Corea del Sur), francés (Francia), alemán (Alemania) y español (España). De forma predeterminada, la app utiliza el idioma compatible preferido del Mac y recurre al inglés si no hay ninguno. Los cambios se aplican inmediatamente y se conservan al volver a abrir la app.

Puedes elegir la apariencia clara, oscura o del sistema. Las capturas y los metadatos de la biblioteca permanecen en tu Mac; la app no realiza solicitudes de red.

## Compilar

Instala Xcode o las Command Line Tools de Apple y ejecuta:

```sh
python3 Tools/build.py
```

Esto crea `build/EZSnapshot.app`, añade su icono y los recursos localizados, la firma localmente y prepara el diseño del instalador. El código fuente también incluye un paquete Swift para usarlo en un IDE. `swift build` genera un ejecutable; el script de compilación genera el paquete completo de la app, necesario para abrirla normalmente en macOS y gestionar los permisos de privacidad.

Para crear el instalador con diseño propio y función de arrastrar y soltar, instala una sola vez las herramientas de empaquetado que se utilizan únicamente durante la compilación y después genera el DMG:

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

El resultado es `build/EZSnapshot-1.0-Apple-Silicon.dmg`. Antes de publicarlo se verifican la firma de la aplicación y las sumas de comprobación de la imagen de disco. Las herramientas de empaquetado no están incluidas en la app y no son necesarias para ejecutarla.

Para utilizar otra cadena de herramientas, establece `EZSNAPSHOT_TOOLCHAIN` en su directorio `usr/bin` y `EZSNAPSHOT_SDK` en el directorio del SDK de Mac.

Ejecuta las comprobaciones de localización, exportación Retina, guardado de capturas, codificación nativa H.264/AAC, compatibilidad de la biblioteca, exportación multimedia y recursos con:

```sh
python3 Tools/check.py
```

Las comprobaciones de codificación utilizan fotogramas y audio sintéticos, por lo que no requieren permiso de grabación de pantalla. Los entornos automatizados con restricciones de acceso deben permitir el acceso a los servicios de codificación de vídeo y audio de Apple. La captura de la pantalla real sigue requiriendo el permiso de macOS.

La app incluida utiliza una firma ad hoc local. La distribución pública requiere firmarla con un Apple Developer ID y realizar la notarización.
