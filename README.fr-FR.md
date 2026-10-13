# EZSnapshot

[English (US)](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja-JP.md) · [한국어](README.ko-KR.md) · [Français](README.fr-FR.md) · [Deutsch](README.de-DE.md) · [Español](README.es-ES.md)

**v1.0 · Première version**  
© 2026 ultRareku

Une application native et discrète de capture d’écran et d’enregistrement vidéo pour les Mac avec puce Apple. Développée avec SwiftUI, AppKit, ScreenCaptureKit et AVFoundation, sans dépendances tierces.

## Lancer l’application

Nécessite un Mac avec puce Apple sous macOS 14 ou version ultérieure.

Pour installer l’application à partir de `build/EZSnapshot-1.0-Apple-Silicon.dmg`, ouvrez l’image disque et faites glisser **EZSnapshot** dans **Applications**. Vous pouvez aussi décompresser `build/EZSnapshot-1.0-Apple-Silicon.zip` et déplacer `EZSnapshot.app` dans **Applications**. Après une compilation locale, vous pouvez ouvrir directement `build/EZSnapshot.app`.

Lors de la première capture, autorisez EZSnapshot dans **Réglages Système → Confidentialité et sécurité → Enregistrement de l’écran et de l’audio du système** (appelé **Enregistrement de l’écran** dans les anciennes versions de macOS). Revenez ensuite dans EZSnapshot ; macOS peut vous demander de rouvrir l’application.

## Captures d’écran

- **Zone :** faites glisser pour sélectionner une zone.
- **Fenêtre :** sélectionnez une fenêtre avec le sélecteur natif de macOS.
- **Tout l’écran :** capturez l’écran principal.
- **Escape :** annulez une capture en cours de sélection.
- Raccourcis globaux, tant qu’EZSnapshot est en cours d’exécution : **Control + Option + 1** (zone), **Control + Option + 2** (fenêtre), **Control + Option + 3** (tout l’écran).
- Lancez une capture depuis la fenêtre de l’application, la barre des menus ou les raccourcis globaux.

Les captures d’écran sont enregistrées par défaut dans `~/Pictures/EZSnapshot`. L’utilitaire natif de capture écrit dans un répertoire temporaire privé ; EZSnapshot vérifie l’image et l’exporte dans le dossier choisi. Dans Réglages, vous pouvez modifier le dossier, le format PNG/JPEG, le délai avant capture et l’inclusion du pointeur lors des captures de tout l’écran.

La bibliothèque locale permet de rechercher, d’ajouter aux favoris, de copier, de partager, d’exporter, de renommer, d’afficher dans le Finder et de déplacer les captures d’écran dans la corbeille. L’éditeur d’annotations propose un stylo, des rectangles, des ellipses, des flèches, des couleurs, des épaisseurs de trait et une fonction d’annulation. L’enregistrement d’une modification crée une image distincte, à la résolution en pixels de l’original.

## Enregistrement vidéo de l’écran

Ouvrez **Filmer** dans la barre latérale. Choisissez un écran ou une fenêtre ; pour une zone, choisissez l’écran puis sélectionnez la partie à filmer. Réglez la fréquence sur 30 ou 60 images par seconde, choisissez si vous souhaitez inclure l’audio du système et afficher le pointeur, puis appuyez sur **Démarrer l’enregistrement**.

La fenêtre principale se masque pendant l’enregistrement. La barre des menus affiche le temps écoulé, actualisé chaque seconde, ainsi que l’action **Arrêter l’enregistrement**. La préparation de l’encodeur et la finalisation des fichiers multimédias s’effectuent en arrière-plan pour que l’interface reste réactive. **Control + Option + 4** permet de démarrer ou d’arrêter l’enregistrement depuis n’importe quelle application. Rouvrez la fenêtre principale pour utiliser son bouton d’arrêt. Si vous quittez pendant un enregistrement, l’application vous propose d’abord de l’arrêter et de le sauvegarder.

Les enregistrements sont sauvegardés sous forme de vidéos MP4 en H.264, avec une piste audio AAC lorsque l’audio est activé, dans le même dossier choisi que les captures d’écran. L’audio du système correspond au contenu sélectionné ; le son du microphone n’est pas capturé. La bibliothèque propose la lecture vidéo native, des miniatures, les durées, les favoris, le partage, la copie, le renommage, l’exportation et la suppression par déplacement dans la corbeille. L’exportation vidéo copie les fichiers en arrière-plan sans charger les vidéos entières en mémoire.

Les vidéos Retina conservent les détails de la source jusqu’à 4096 pixels sur le côté le plus long, avec des dimensions paires pour le H.264. Si le flux de capture est interrompu, les images exploitables déjà capturées sont finalisées dans un fichier vidéo. Les enregistrements vides ou ayant échoué ne sont pas ajoutés à la bibliothèque, et les captures d’écran existantes restent compatibles.

L’enregistrement et la lecture utilisent les frameworks fournis avec macOS. **FFmpeg, Homebrew, des codecs téléchargés et l’installation d’environnements d’exécution supplémentaires ne sont pas nécessaires.** Tout le code de l’application est contenu dans le paquet de l’application.

## Langues et apparence

Réglages propose des langues accompagnées de drapeaux : anglais (États-Unis), chinois simplifié (Chine), chinois traditionnel (Taïwan), japonais (Japon), coréen (Corée du Sud), français (France), allemand (Allemagne) et espagnol (Espagne). Par défaut, l’application utilise la première langue prise en charge parmi les langues préférées de votre Mac, ou l’anglais si aucune ne l’est. Les changements s’appliquent immédiatement et sont conservés entre les lancements.

Les apparences claire, sombre et système sont disponibles. Les captures d’écran et les métadonnées de la bibliothèque restent sur votre Mac ; l’application n’effectue aucune requête réseau.

## Compiler

Installez Xcode ou les outils en ligne de commande d’Apple, puis exécutez :

```sh
python3 Tools/build.py
```

Cette commande crée `build/EZSnapshot.app`, ajoute son icône et ses ressources localisées, applique une signature locale et prépare les éléments graphiques de l’installateur. Le code source comprend également un Swift Package pour une utilisation dans un IDE. La commande `swift build` produit un exécutable ; le script de compilation produit le paquet complet de l’application, nécessaire au lancement habituel sous macOS et à la gestion des autorisations de confidentialité.

Pour créer l’installateur graphique par glisser-déposer, installez une fois les outils de création de paquet réservés à la compilation, puis créez le DMG :

```sh
python3 -m pip install --target .build/dmg-python -r Tools/requirements-dmg.txt
python3 Tools/make_dmg.py
```

Le résultat est `build/EZSnapshot-1.0-Apple-Silicon.dmg`. La signature de l’application et les sommes de contrôle de l’image disque sont vérifiées avant publication. Les outils de création de paquet ne sont pas inclus dans l’application et ne sont pas nécessaires à son exécution.

Pour utiliser une autre chaîne d’outils, définissez `EZSNAPSHOT_TOOLCHAIN` sur son répertoire `usr/bin` et `EZSNAPSHOT_SDK` sur le répertoire du SDK Mac.

Exécutez les vérifications de la localisation, de l’exportation Retina, de l’enregistrement des captures d’écran, de l’encodage natif H.264/AAC, de la compatibilité de la bibliothèque, de l’exportation multimédia et des ressources avec :

```sh
python3 Tools/check.py
```

Les vérifications d’encodage utilisent des images et de l’audio synthétiques et ne nécessitent donc pas l’autorisation d’enregistrement de l’écran. Les environnements automatisés isolés doivent autoriser l’accès aux services d’encodage vidéo et audio d’Apple. La capture réelle de l’écran nécessite toujours l’autorisation de macOS.

L’application fournie utilise une signature locale ad hoc. La distribution publique nécessite une signature avec un identifiant Apple Developer ID et une notarisation.
