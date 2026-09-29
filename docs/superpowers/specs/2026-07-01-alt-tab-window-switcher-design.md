# WinTab — Remplaçant d'Alt-Tab par fenêtre pour macOS

**Date :** 2026-07-01
**Statut :** Design validé
**Cible :** macOS 26+ (Apple Silicon), usage personnel, installation hors App Store

## Problème

Le ⌘+Tab natif de macOS regroupe par **application** : il affiche une seule tuile « Chrome » ou « Cursor » même quand plusieurs fenêtres sont ouvertes. On veut un sélecteur qui affiche **chaque fenêtre séparément** (chaque fenêtre Chrome, chaque projet Cursor) avec le confort d'un Alt-Tab façon Windows : navigation clavier/souris, fermeture depuis le sélecteur, présélection de la fenêtre précédente.

## Objectifs

- Afficher **une tuile par fenêtre** normale et visible, toutes apps confondues.
- Remplacer/dupliquer le comportement ⌘+Tab avec un **raccourci configurable** (défaut ⌘+Tab, blocage du switcher natif).
- Navigation : ⌘+Tab / ⌘+⇧+Tab, flèches ← →, survol + clic souris, Échap pour annuler.
- **Présélection de la 2ᵉ fenêtre** (fenêtre précédente, tri MRU) → un appui rapide bascule vers la fenêtre précédente.
- **Fermer la fenêtre sélectionnée** avec la touche **W** (équivalent ⌘W).
- **Vignettes live** de chaque fenêtre + icône d'app + titre.
- Installation locale : `.app` signé ad-hoc, glissé dans `/Applications`, option « lancer au démarrage ».

## Hors périmètre (v1)

- Fenêtres minimisées, fenêtres sur d'autres Spaces / plein écran d'autres bureaux, apps cachées (⌘H).
- Notarisation Apple / distribution à d'autres machines.
- Quitter l'app entière (touche Q) — seul W (fermer la fenêtre) est requis.

Ces éléments sont des améliorations possibles ultérieures.

## Pile technique (Approche hybride retenue)

- **Interception du raccourci** : `CGEventTap` global (`kCGHIDEventTap`) qui capture et **avale** ⌘+Tab avant le WindowServer, empêchant le switcher natif. Suit ⌘ maintenu via `flagsChanged` et Tab/⇧Tab via keyDown. Nécessite la permission **Accessibilité**. Réactivation auto si le système désactive le tap (`CGEvent.tapEnable`).
- **Énumération + vignettes** : `ScreenCaptureKit`. `SCShareableContent` pour lister chaque fenêtre (app propriétaire, titre, windowID, frame, on-screen, layer) ; filtre = fenêtres normales, on-screen, layer 0. `SCScreenshotManager.captureImage` pour capturer une vignette **à la demande** à l'ouverture (async, non bloquant). Nécessite la permission **Enregistrement d'écran**.
- **Actions sur fenêtres** : API Accessibilité (`AXUIElement`). `AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`, appariement avec les `SCWindow` par titre + frame. Activation via `NSRunningApplication.activate` + `kAXMainAttribute`/`kAXRaiseAction`. Fermeture (W) via `kAXCloseButtonAttribute` + `kAXPressAction`.
- **UI** : AppKit. `NSPanel` borderless *non-activating* (`.nonactivatingPanel`), `level` élevé, `collectionBehavior` = `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` pour s'afficher par-dessus le plein écran sans voler le focus. Rangée horizontale de tuiles via `NSCollectionView` (scroll horizontal si débordement).
- **Coquille app** : app sans icône Dock (`LSUIElement`), `NSStatusItem` en menu bar (préférences, raccourci, lancer au démarrage, quitter).

### Alternatives écartées

- **CGWindowList + AX** : `CGWindowListCreateImage` déprécié sur macOS récent, vignettes de moindre qualité → incompatible avec l'exigence « vignettes live ».
- **Tout ScreenCaptureKit** : SCK ne peut pas *agir* sur les fenêtres (focus/fermer) → AX indispensable de toute façon.

## Architecture (modules)

Séparation entre logique pure testable et coques système derrière des protocoles.

### `SwitcherCore` (pur, testé par XCTest — aucune dépendance AppKit/SCK)

- `WindowInfo` — `id`, `pid`, `appName`, `bundleId`, `title`, `frame`, `icon`.
- `MRUList` — ordonnancement des fenêtres par usage récent ; API `touch(windowID)`, `ordered(from:)`.
- `SelectionState` — index sélectionné ; logique flèches / Tab / ⇧Tab avec wrap-around ; présélection de la 2ᵉ tuile ; retrait d'une fenêtre fermée avec réajustement de l'index.
- `ShortcutMatcher` — détermine si un `(keyCode, modifiers)` correspond au raccourci configuré (`ShortcutConfig`).

### Coques derrière protocoles (impl réelle + fakes de test)

- `WindowSource` → `ScreenCaptureWindowSource` (énumération + capture vignettes via SCK).
- `WindowActions` → `AXWindowActions` (raise, activer, fermer via AX).
- `HotkeyTap` → `CGEventTapHotkey` (interception globale du raccourci).
- `MRUTracker` → observe `NSWorkspace.didActivateApplicationNotification` + `kAXFocusedWindowChangedNotification` par app pour alimenter `MRUList`.

### `AppShell`

`NSApplicationDelegate`, `NSStatusItem`, orchestration du flux, préférences (persistées via `UserDefaults`), onboarding permissions.

### `SwitcherUI`

`NSPanel` non-activating + `NSCollectionView` horizontal de tuiles (icône + titre + vignette + bouton ✕ au survol).

## Flux d'une invocation

1. `CGEventTapHotkey` détecte ⌘ maintenu + Tab → avale l'événement (natif bloqué) → notifie `AppShell`.
2. `AppShell` récupère les fenêtres via `WindowSource`, les ordonne via `MRUList`, initialise `SelectionState` avec présélection de la 2ᵉ tuile.
3. `SwitcherUI` affiche le panneau immédiatement (icône + titre), puis met à jour chaque tuile avec sa vignette dès que `SCScreenshotManager` la renvoie (async).
4. Tant que ⌘ est maintenu : Tab/⇧Tab et flèches déplacent la sélection ; survol souris surbrille ; **W** ferme la fenêtre sélectionnée (`WindowActions` → tuile retirée via `SelectionState`) ; **Échap** annule et ferme.
5. Au relâchement de ⌘ (ou clic sur une tuile) : `WindowActions` active l'app cible et raise la fenêtre ; le panneau se ferme ; `MRUTracker` enregistre le nouveau focus.

## Suivi MRU

`MRUList` en mémoire, alimenté par `NSWorkspace.didActivateApplicationNotification` (changement d'app) et un observateur AX `kAXFocusedWindowChangedNotification` par app (changement de fenêtre au sein d'une app). Au premier lancement, ordre initial = ordre d'empilement fourni par SCK.

## Gestion des erreurs & permissions

- **Onboarding 1ᵉ lancement** : vérifie Accessibilité (`AXIsProcessTrustedWithOptions` avec prompt) et Enregistrement d'écran (`CGPreflightScreenCaptureAccess`). Si absent → fenêtre d'explication + boutons ouvrant les réglages système correspondants.
- **Mode dégradé** : sans Enregistrement d'écran, l'app fonctionne en icône + titre (pas de vignettes).
- **Event tap désactivé par le système** (timeout de latence) → réactivation auto (`CGEvent.tapEnable(tap:enable:)`).
- **Fenêtre disparue** entre énumération et action → échec silencieux + rafraîchissement de la liste.
- Échecs AX loggés sans crash.

## Tests

- **Unitaires (SwiftPM/XCTest) sur `SwitcherCore`** : ordonnancement MRU ; math de sélection (wrap-around, présélection 2ᵉ, ⇧Tab arrière) ; `ShortcutMatcher` (correspondance keyCode+modifiers) ; retrait d'une fenêtre fermée et réajustement d'index.
- Impls système testées via **fakes** conformes aux protocoles (`FakeWindowSource`, `FakeWindowActions`).
- **Vérification manuelle documentée** pour l'intégration réelle : plusieurs fenêtres Chrome, plusieurs projets Cursor, comportement en plein écran, multi-écran, fermeture avec W, annulation Échap.

## Packaging & installation

- Cible exécutable SwiftPM (pas de Xcode requis, Command Line Tools + Swift 6.3 suffisent).
- Script `build-app.sh` :
  1. `swift build -c release`
  2. Assemble `WinTab.app/Contents/{MacOS,Resources}` avec `Info.plist` (`LSUIElement=true`, `CFBundleIdentifier` stable, `CFBundleName`, `CFBundleIconFile`).
  3. Copie le binaire dans `Contents/MacOS`.
  4. `codesign --force --sign - --options runtime WinTab.app` (ad-hoc **stable** pour préserver l'octroi TCC entre builds).
- Installation : glisser `WinTab.app` dans `/Applications`.
- « Lancer au démarrage » via `SMAppService` (réglage menu bar).

## Nom & identité

`AltTab` étant déjà pris par l'app open-source existante (risque de collision TCC), le nom par défaut est **WinTab**, bundle id `com.yvanb.wintab`. Renommable si souhaité.
