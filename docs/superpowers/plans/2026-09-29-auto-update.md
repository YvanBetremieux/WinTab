# Release continue + mises à jour automatiques — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** chaque push sur `main` publie une release GitHub signée « WinTab Dev », et les
apps installées se mettent à jour d'elles-mêmes via Sparkle, sans perdre les
autorisations.

**Architecture:** `UpdateInstallGate` (SwitcherCore, pur, testé) décide *quand*
installer. `SparkleUpdater` (WinTab) enveloppe `SPUStandardUpdaterController` et
transmet au gate le bloc d'installation immédiate de Sparkle. Le CI importe le certificat
auto-signé depuis un secret, construit, signe le zip en EdDSA et publie la release avec
son `appcast.xml`.

**Tech Stack:** Swift 6.4 / SwiftPM (tools 5.9), swift-testing, Sparkle 2 (≥ 2.6,
binaire xcframework), bash, GitHub Actions `macos-26`, `gh`.

**Spec:** `docs/superpowers/specs/2026-09-29-auto-update-design.md`

## Global Constraints

- macOS minimum : 14.0 (`LSMinimumSystemVersion`, `sparkle:minimumSystemVersion`).
- Bundle id `com.yvanb.wintab`, identité de signature `WinTab Dev`.
- Version : `CFBundleShortVersionString = <VERSION>.<run_number>`, `CFBundleVersion = <run_number>` ; builds locaux `<VERSION>.0` / `0`.
- Flux : `https://github.com/YvanBetremieux/WinTab/releases/latest/download/appcast.xml`, injecté **seulement** si `WINTAB_FEED_URL` est défini (CI).
- Clé Sparkle générée avec `--account wintab` (Onyx utilise déjà le compte par défaut `ed25519` : ne pas le réutiliser).
- `SwitcherCore` n'importe aucun framework système ; nouvelle logique = test swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), jamais XCTest.
- Libellés du menu en français, exactement : `WinTab <version>`, `Rechercher les mises à jour…`, `Mises à jour désactivées (build local)`, `Installer automatiquement les mises à jour`, `Redémarrer pour installer v<version>`.
- Commits avec l'identité locale `yvan.betremieux@gmail.com` (déjà configurée), terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Aucun `git push` sans accord explicite de Yvan** : après ce chantier, un push sur `main` publie chez tous les utilisateurs.
- Ne jamais committer `.build/` ni `WinTab.app/`, ni aucun `.p12` / clé privée.

## Review Focus

1. **Tous les chemins de fermeture du switcher** (commit clavier, Échap, clic sur une vignette, fermeture de la dernière fenêtre, ouverture avortée faute de fenêtres) doivent prévenir le gate ; sinon une mise à jour arrivée pendant l'ouverture ne s'installe jamais. → Task 5 centralise l'appel dans le `didSet` de `isOpen`.
2. **« Installer » demandé sans mise à jour en attente** ne doit pas armer une installation silencieuse future en mode manuel. → test `installNowWithoutPendingDoesNotArmLaterUpdate` (Task 1).
3. **Build local ou `swift run`** (pas de `SUFeedURL`) : l'app démarre sans updater et affiche `Mises à jour désactivées (build local)`, sans crash. → Task 3 step 6 (plist local sans `SUFeedURL`) + Task 5 step 5 (vérification humaine).
4. **Secret du certificat absent ou cassé en CI** : le build doit échouer, jamais publier une release ad-hoc (qui casserait les autorisations de tout le monde). → Task 3 step 5 (`WINTAB_REQUIRE_IDENTITY=1` avec une identité inexistante doit sortir en erreur) + contrôle d'autorité dans `check-bundle.sh`.
5. **`Sparkle.framework` introuvable au lancement** (rpath manquant) : crash au démarrage chez l'utilisateur. → `check-bundle.sh` vérifie le rpath (Task 3), et Task 5 step 5 lance le bundle construit.

---

## File Structure

| Fichier | Rôle |
|---|---|
| `Sources/SwitcherCore/UpdateInstallGate.swift` (nouveau) | Décide quand installer une mise à jour prête |
| `Tests/SwitcherCoreTests/UpdateInstallGateTests.swift` (nouveau) | Tests du gate |
| `Package.swift` (modifié) | Dépendance Sparkle pour la cible `WinTab` |
| `scripts/make-signing-cert.sh` (modifié) | Peut exporter le `.p12` destiné au secret CI |
| `scripts/sparkle-public-key.txt` (nouveau) | Clé publique EdDSA (non secrète) lue par `build-app.sh` |
| `VERSION` (nouveau) | `major.minor` |
| `scripts/build-app.sh` (modifié) | Version, framework, rpath, clés Sparkle conditionnelles, signature inside-out, identité obligatoire en CI |
| `scripts/check-bundle.sh` (nouveau) | Contrôle d'un bundle de release |
| `scripts/make-appcast.sh` (nouveau) | Appcast signé EdDSA à une entrée |
| `scripts/test-make-appcast.sh` (nouveau) | Test de `make-appcast.sh` |
| `Sources/WinTab/SparkleUpdater.swift` (nouveau) | Pont Sparkle → gate |
| `Sources/WinTab/Preferences.swift` (modifié) | `autoInstallUpdates` |
| `Sources/WinTab/AppDelegate.swift` (modifié) | Câblage gate/updater, `isOpen` observé |
| `Sources/WinTab/StatusItemController.swift` (modifié) | Items de menu de mise à jour |
| `.github/workflows/release.yml` (réécrit) | Release sur push `main` |
| `README.md`, `CLAUDE.md` (modifiés) | Documentation |

---

### Task 1: `UpdateInstallGate`

**Files:**
- Create: `Sources/SwitcherCore/UpdateInstallGate.swift`
- Test: `Tests/SwitcherCoreTests/UpdateInstallGateTests.swift`

**Interfaces:**
- Consumes: rien.
- Produces:
  ```swift
  public final class UpdateInstallGate {
      public init(autoInstall: Bool)
      public var autoInstall: Bool                     // didSet : peut déclencher l'installation
      public private(set) var pendingVersion: String?
      public var onPendingChange: ((String?) -> Void)?
      public func updateReady(version: String, install: @escaping () -> Void)
      public func switcherOpened()
      public func switcherClosed()
      public func installNow()
  }
  ```

- [ ] **Step 1: Write the failing tests**

`Tests/SwitcherCoreTests/UpdateInstallGateTests.swift` :

```swift
import Testing
@testable import SwitcherCore

@Suite struct UpdateInstallGateTests {
    /// Counts calls to the install closure handed to the gate.
    private final class Installer {
        var count = 0
        func action() -> () -> Void { { self.count += 1 } }
    }

    @Test func installsImmediatelyWhenReadyAndSwitcherClosed() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 1)
        #expect(gate.pendingVersion == nil)
    }

    @Test func waitsForSwitcherToClose() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.switcherOpened()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func manualModeKeepsUpdatePendingUntilInstallNow() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened(); gate.switcherClosed()
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
        gate.installNow()
        #expect(i.count == 1)
        #expect(gate.pendingVersion == nil)
    }

    @Test func manualInstallNowWhileOpenDefersToClose() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened()
        gate.installNow()
        #expect(i.count == 0)
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func reenablingAutoInstallInstallsPendingUpdate() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.autoInstall = true
        #expect(i.count == 1)
    }

    @Test func reenablingAutoInstallWhileOpenWaitsForClose() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened()
        gate.autoInstall = true
        #expect(i.count == 0)
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func installsAtMostOncePerReadyUpdate() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened(); gate.switcherClosed()
        gate.installNow()
        gate.autoInstall = false; gate.autoInstall = true
        #expect(i.count == 1)
    }

    @Test func laterUpdateReplacesPendingOne() {
        let gate = UpdateInstallGate(autoInstall: false)
        let first = Installer(); let second = Installer()
        gate.updateReady(version: "1.0.2", install: first.action())
        gate.updateReady(version: "1.0.3", install: second.action())
        #expect(gate.pendingVersion == "1.0.3")
        gate.installNow()
        #expect(first.count == 0)
        #expect(second.count == 1)
    }

    @Test func notifiesPendingChanges() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        var seen: [String?] = []
        gate.onPendingChange = { seen.append($0) }
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.installNow()
        #expect(seen == ["1.0.2", nil])
    }

    @Test func installNowWithoutPendingDoesNotArmLaterUpdate() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.installNow()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UpdateInstallGateTests`
Expected: échec de compilation, `cannot find 'UpdateInstallGate' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/SwitcherCore/UpdateInstallGate.swift` :

```swift
/// Decides *when* a downloaded update gets installed, independently of Sparkle.
///
/// An update is installed only while the switcher is closed — relaunching while the
/// user holds ⌘ would drop their switch. With `autoInstall` on it happens as soon as
/// possible; with it off, only after `installNow()`.
public final class UpdateInstallGate {
    private var pending: (version: String, install: () -> Void)?
    private var switcherOpen = false
    private var installRequested = false

    public var autoInstall: Bool {
        didSet { installIfAllowed() }
    }

    public var pendingVersion: String? { pending?.version }

    /// Called with the new pending version, or nil once it is installed.
    public var onPendingChange: ((String?) -> Void)?

    public init(autoInstall: Bool) {
        self.autoInstall = autoInstall
    }

    /// A newer update replaces one still waiting.
    public func updateReady(version: String, install: @escaping () -> Void) {
        pending = (version, install)
        onPendingChange?(version)
        installIfAllowed()
    }

    public func switcherOpened() { switcherOpen = true }

    public func switcherClosed() {
        switcherOpen = false
        installIfAllowed()
    }

    /// Menu action. Ignored when nothing is pending, so it cannot arm a later install.
    public func installNow() {
        guard pending != nil else { return }
        installRequested = true
        installIfAllowed()
    }

    private func installIfAllowed() {
        guard let update = pending, !switcherOpen, autoInstall || installRequested else { return }
        pending = nil
        installRequested = false
        onPendingChange?(nil)
        update.install()
    }
}
```

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: `Test run with 34 tests in 6 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwitcherCore/UpdateInstallGate.swift Tests/SwitcherCoreTests/UpdateInstallGateTests.swift
git commit -m "SwitcherCore : UpdateInstallGate décide quand installer une mise à jour

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Dépendance Sparkle, identité de signature, clés et secrets

Tâche **interactive** : le trousseau affiche des demandes d'autorisation que Yvan doit
valider. Prévenir avant chaque commande qui en déclenche une.

**Files:**
- Modify: `Package.swift`
- Modify: `scripts/make-signing-cert.sh`
- Create: `scripts/sparkle-public-key.txt`
- Commit aussi: `Package.resolved` (généré)

**Interfaces:**
- Produces: produit SwiftPM `Sparkle` lié à la cible `WinTab` ; outils
  `.build/artifacts/sparkle/Sparkle/bin/{generate_keys,sign_update}` ; identité
  `WinTab Dev` dans le trousseau de session ; `scripts/sparkle-public-key.txt` (une
  ligne, base64) ; secrets GitHub `CERT_P12_BASE64`, `CERT_P12_PASSWORD`,
  `SPARKLE_ED_PRIVATE_KEY`.

- [ ] **Step 1: Ajouter Sparkle à `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinTab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(
            name: "WinTab",
            dependencies: [
                "SwitcherCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
```

- [ ] **Step 2: Résoudre et vérifier**

Run: `swift package resolve && swift build && swift test && ls .build/artifacts/sparkle/Sparkle/bin`
Expected: build OK, `34 tests in 6 suites passed`, et `generate_keys` + `sign_update` listés.

- [ ] **Step 3: Permettre à `make-signing-cert.sh` d'exporter le `.p12`**

Dans `scripts/make-signing-cert.sh` :

1. Juste après `KEYCHAIN=…`, ajouter :
   ```bash
   # Optional: P12_OUT=<path> P12_PASS=<password> also writes the identity as a .p12,
   # for the CI secret CERT_P12_BASE64 (see README > Releasing). Never commit it.
   P12_OUT="${P12_OUT:-}"
   ```
2. Remplacer le bloc « already exists » par :
   ```bash
   if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
       if [ -n "$P12_OUT" ]; then
           echo "!! Identity '$CERT_NAME' already exists; it cannot be re-exported from here."
           echo "!! Export it from Keychain Access (My Certificates → Export) instead."
           exit 1
       fi
       echo "==> Identity '$CERT_NAME' already exists. Nothing to do."
       exit 0
   fi
   ```
3. Remplacer `P12PASS="wintab-transient"` par :
   ```bash
   P12PASS="${P12_PASS:-wintab-transient}"
   ```
4. Juste après la commande `openssl pkcs12 -export …`, ajouter :
   ```bash
   if [ -n "$P12_OUT" ]; then
       cp "$TMP/wintab.p12" "$P12_OUT"
       echo "==> Exported the identity to $P12_OUT (password: \$P12_PASS)"
   fi
   ```

- [ ] **Step 4: Créer l'identité et le `.p12` (demande trousseau)**

`S` = le répertoire scratchpad de la session (jamais le repo).

```bash
S=<scratchpad>
openssl rand -base64 24 | tr -d '\n' > "$S/p12pass"
P12_OUT="$S/wintab.p12" P12_PASS="$(cat "$S/p12pass")" ./scripts/make-signing-cert.sh
security find-identity -p codesigning | grep '"WinTab Dev"'
```
Expected: `Exported the identity to …`, puis une ligne `"WinTab Dev" (CSSMERR_TP_NOT_TRUSTED)`.

- [ ] **Step 5: Créer la clé EdDSA (demande trousseau)**

```bash
B=.build/artifacts/sparkle/Sparkle/bin
$B/generate_keys --account wintab
$B/generate_keys --account wintab -p | tr -d '\n' > scripts/sparkle-public-key.txt
$B/generate_keys --account wintab -x "$S/sparkle.key"
cat scripts/sparkle-public-key.txt
```
Expected: une clé base64 de 44 caractères, **différente** de celle d'Onyx
(`OeqxqASdmFQKzfPuS0FgyJ/Y/V4H+DK+HHGqFKr/mIY=`).

- [ ] **Step 6: Poser les secrets et effacer les fichiers**

```bash
base64 -i "$S/wintab.p12" | tr -d '\n' | gh secret set CERT_P12_BASE64
gh secret set CERT_P12_PASSWORD < "$S/p12pass"
gh secret set SPARKLE_ED_PRIVATE_KEY < "$S/sparkle.key"
rm -f "$S/wintab.p12" "$S/p12pass" "$S/sparkle.key"
gh secret list
```
Expected: les trois secrets listés.

- [ ] **Step 7: Commit**

```bash
git status --short   # aucun .p12 ni .key ne doit apparaître
git add Package.swift Package.resolved scripts/make-signing-cert.sh scripts/sparkle-public-key.txt
git commit -m "Sparkle en dépendance, clé publique EdDSA, export .p12 pour le CI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `build-app.sh`, `VERSION`, `check-bundle.sh`

**Files:**
- Create: `VERSION`
- Modify: `scripts/build-app.sh` (réécriture de la partie après la sélection du toolchain)
- Create: `scripts/check-bundle.sh`

**Interfaces:**
- Consumes: `scripts/sparkle-public-key.txt`, identité `WinTab Dev`, produit Sparkle (Task 2).
- Produces: variables d'environnement de `build-app.sh` : `WINTAB_VERSION`,
  `WINTAB_BUILD`, `WINTAB_FEED_URL`, `WINTAB_REQUIRE_IDENTITY`, `WINTAB_SIGN_IDENTITY`
  (défaut `WinTab Dev`) ; sortie `WinTab.app` dans le répertoire courant ;
  `scripts/check-bundle.sh <app> <version> <build>` (code 0 = OK).

- [ ] **Step 1: Créer `VERSION`**

```bash
printf '1.0\n' > VERSION
```

- [ ] **Step 2: Écrire `scripts/check-bundle.sh`**

```bash
#!/usr/bin/env bash
# Checks that a WinTab.app is releasable: version, Sparkle feed and framework,
# rpath, signature by "WinTab Dev". Usage: check-bundle.sh <app> <version> <build>
set -euo pipefail
APP="$1"; WANT_VERSION="$2"; WANT_BUILD="$3"
PLIST="$APP/Contents/Info.plist"
fail() { echo "check-bundle: $*" >&2; exit 1; }
key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || true; }

[ "$(key CFBundleShortVersionString)" = "$WANT_VERSION" ] || fail "version $(key CFBundleShortVersionString) ≠ $WANT_VERSION"
[ "$(key CFBundleVersion)" = "$WANT_BUILD" ] || fail "build $(key CFBundleVersion) ≠ $WANT_BUILD"
[ -n "$(key SUFeedURL)" ]     || fail "SUFeedURL missing"
[ -n "$(key SUPublicEDKey)" ] || fail "SUPublicEDKey missing"
[ -d "$APP/Contents/Frameworks/Sparkle.framework" ] || fail "Sparkle.framework missing"
otool -l "$APP/Contents/MacOS/WinTab" | grep '@loader_path/../Frameworks' >/dev/null \
    || fail "rpath @loader_path/../Frameworks missing: Sparkle would not load"
codesign --verify --strict --deep "$APP" || fail "invalid signature"
codesign -dvv "$APP" 2>&1 | grep '^Authority=WinTab Dev$' >/dev/null \
    || fail "not signed by 'WinTab Dev' — users would lose their permissions"
echo "check-bundle: OK ($WANT_VERSION / $WANT_BUILD)"
```

Puis `chmod +x scripts/check-bundle.sh`.

- [ ] **Step 3: Réécrire `scripts/build-app.sh` après la sélection du toolchain**

Garder tel quel l'en-tête jusqu'à `echo "==> Toolchain: …"` inclus. Remplacer tout le reste
par :

```bash
APP="WinTab"
BUNDLE_ID="com.yvanb.wintab"
APP_DIR="$APP.app"
INSTALL_DIR="/Applications"

# Version: major.minor from VERSION; the release workflow sets the full version
# (1.0.<run>) and the build number (<run>), which Sparkle requires to increase.
WINTAB_VERSION="${WINTAB_VERSION:-$(tr -d '[:space:]' < VERSION).0}"
WINTAB_BUILD="${WINTAB_BUILD:-0}"

# Stable signing identity so macOS keeps Accessibility / Screen-Recording
# permissions across rebuilds *and* across Sparkle updates. Locally it falls back
# to ad-hoc; the release workflow sets WINTAB_REQUIRE_IDENTITY=1 so a missing
# certificate fails the release instead of shipping an ad-hoc build.
SIGN_IDENTITY="${WINTAB_SIGN_IDENTITY:-WinTab Dev}"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    if [ "${WINTAB_REQUIRE_IDENTITY:-0}" = "1" ]; then
        echo "!! Signing identity '$SIGN_IDENTITY' not found and WINTAB_REQUIRE_IDENTITY=1."
        exit 1
    fi
    echo "!! Signing identity '$SIGN_IDENTITY' not found."
    echo "!! Run ./scripts/make-signing-cert.sh once to keep permissions across builds."
    echo "!! Falling back to ad-hoc signing (permissions WILL reset each build)."
    SIGN_IDENTITY="-"
fi

# Sparkle is only switched on when a feed is given (the release workflow).
# Local builds have no feed, so a release never overwrites a development build.
SPARKLE_KEYS=""
if [ -n "${WINTAB_FEED_URL:-}" ]; then
    SPARKLE_KEYS="    <key>SUFeedURL</key><string>$WINTAB_FEED_URL</string>
    <key>SUPublicEDKey</key><string>$(tr -d '[:space:]' < scripts/sparkle-public-key.txt)</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>"
fi

echo "==> swift build -c release"
"$SWIFT" build -c release
BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"

echo "==> Assembling $APP_DIR ($WINTAB_VERSION / $WINTAB_BUILD)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP" "$APP_DIR/Contents/MacOS/$APP"

# Sparkle.framework: SwiftPM copies it next to the binary; fall back to the
# macOS slice of the xcframework.
SPARKLE_FW="$BIN_DIR/Sparkle.framework"
if [ ! -d "$SPARKLE_FW" ]; then
    SPARKLE_FW="$(find .build/artifacts -path '*macos*' -name Sparkle.framework -type d | head -1)"
fi
if [ ! -d "$SPARKLE_FW" ]; then
    echo "!! Sparkle.framework not found in .build — the app would crash at launch."
    exit 1
fi
cp -R "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"

# dyld looks for @rpath/Sparkle.framework; point it at Contents/Frameworks.
if ! otool -l "$APP_DIR/Contents/MacOS/$APP" | grep '@loader_path/../Frameworks' >/dev/null; then
    install_name_tool -add_rpath '@loader_path/../Frameworks' "$APP_DIR/Contents/MacOS/$APP"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$WINTAB_VERSION</string>
    <key>CFBundleVersion</key><string>$WINTAB_BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>WinTab affiche un aperçu de vos fenêtres ouvertes.</string>
$SPARKLE_KEYS
</dict>
</plist>
PLIST

# Inside-out signing, in the order Sparkle documents: nested helpers, then the
# framework, then the app. --deep is not used (deprecated for signing).
echo "==> Signing with identity: $SIGN_IDENTITY"
sign() { codesign --force --sign "$SIGN_IDENTITY" --options runtime "$@"; }
FW="$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$FW/XPCServices/Installer.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
    if [ -e "$nested" ]; then sign "$nested"; fi
done
if [ -e "$FW/XPCServices/Downloader.xpc" ]; then
    sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
fi
sign "$APP_DIR/Contents/Frameworks/Sparkle.framework"
sign "$APP_DIR"
codesign --verify --strict --deep "$APP_DIR"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing to $INSTALL_DIR and relaunching"
    # Quit the running instance (ignore errors if not running).
    osascript -e 'quit app "WinTab"' >/dev/null 2>&1 || true
    pkill -x "$APP" >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$INSTALL_DIR/$APP_DIR"
    cp -R "$APP_DIR" "$INSTALL_DIR/"
    open "$INSTALL_DIR/$APP_DIR"
    echo "==> Installed and launched from $INSTALL_DIR/$APP_DIR"
else
    echo "==> Built $APP_DIR. Run with --install to copy to $INSTALL_DIR and relaunch."
fi
```

- [ ] **Step 4: Build de type release en local, contrôlé**

```bash
WINTAB_VERSION=1.0.999 WINTAB_BUILD=999 WINTAB_REQUIRE_IDENTITY=1 \
WINTAB_FEED_URL=https://github.com/YvanBetremieux/WinTab/releases/latest/download/appcast.xml \
  ./scripts/build-app.sh && ./scripts/check-bundle.sh WinTab.app 1.0.999 999
```
Expected: `check-bundle: OK (1.0.999 / 999)`. La première signature peut afficher la
fenêtre « codesign veut utiliser la clé… » : Yvan clique **Toujours autoriser**.

- [ ] **Step 5: Une identité absente doit faire échouer le build (Review Focus 4)**

```bash
if WINTAB_SIGN_IDENTITY="No Such Identity" WINTAB_REQUIRE_IDENTITY=1 ./scripts/build-app.sh; then
  echo "FAIL: build succeeded without identity"; else echo "OK: refused"; fi
```
Expected: `OK: refused`.

- [ ] **Step 6: Un build local n'a pas de flux (Review Focus 3)**

```bash
./scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" WinTab.app/Contents/Info.plist && echo FAIL || echo "OK: no feed"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" WinTab.app/Contents/Info.plist
```
Expected: `OK: no feed` puis `1.0.0`. `check-bundle.sh WinTab.app 1.0.0 0` doit
échouer sur `SUFeedURL missing` (c'est voulu).

- [ ] **Step 7: Commit**

```bash
git add VERSION scripts/build-app.sh scripts/check-bundle.sh
git commit -m "build-app : Sparkle embarqué, version injectable, identité obligatoire en CI ; check-bundle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `make-appcast.sh` et son test

**Files:**
- Create: `scripts/make-appcast.sh`
- Create: `scripts/test-make-appcast.sh`

**Interfaces:**
- Consumes: `.build/artifacts/sparkle/Sparkle/bin/sign_update` (Task 2).
- Produces: `make-appcast.sh <zip> <version> <build> <download-url> <notes-url> <out.xml>`, clé privée via `SPARKLE_ED_PRIVATE_KEY` ; `test-make-appcast.sh` (code 0 = OK).

- [ ] **Step 1: Écrire le test `scripts/test-make-appcast.sh`**

```bash
#!/usr/bin/env bash
# Tests make-appcast.sh with a throwaway ed25519 key (never the keychain one).
set -euo pipefail
cd "$(dirname "$0")/.."
BIN=.build/artifacts/sparkle/Sparkle/bin
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# A Sparkle ed25519 private key is 32 arbitrary bytes, base64-encoded.
KEY=$(openssl rand -base64 32)
mkdir "$T/dir with space"; echo hello > "$T/dir with space/f"
ZIP="$T/dir with space/WinTab-1.0.7.zip"
ditto -c -k --keepParent "$T/dir with space/f" "$ZIP"

SPARKLE_ED_PRIVATE_KEY="$KEY" scripts/make-appcast.sh "$ZIP" \
    1.0.7 7 "https://example.com/dl?a=1&b=2" "https://example.com/notes" "$T/appcast.xml"
xmllint --noout "$T/appcast.xml"
grep -q 'sparkle:version="7"' "$T/appcast.xml"
grep -q 'sparkle:shortVersionString="1.0.7"' "$T/appcast.xml"
grep -q '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' "$T/appcast.xml"
grep -q 'dl?a=1&amp;b=2' "$T/appcast.xml"
SIG=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$T/appcast.xml")
echo "$KEY" | "$BIN/sign_update" --ed-key-file - --verify "$ZIP" "$SIG"

# Invalid key → failure, and no file written.
if SPARKLE_ED_PRIVATE_KEY="nope" scripts/make-appcast.sh "$ZIP" \
    1.0.7 7 u n "$T/bad.xml" 2>/dev/null; then echo "FAIL: invalid key accepted"; exit 1; fi
[ ! -e "$T/bad.xml" ] || { echo "FAIL: partial appcast written"; exit 1; }
echo "test-make-appcast: OK"
```

Puis `chmod +x scripts/test-make-appcast.sh`.

- [ ] **Step 2: Lancer le test, il doit échouer**

Run: `scripts/test-make-appcast.sh`
Expected: échec, `scripts/make-appcast.sh: No such file or directory`.

- [ ] **Step 3: Écrire `scripts/make-appcast.sh`**

```bash
#!/usr/bin/env bash
# Writes a one-entry Sparkle appcast for <zip>, signed with EdDSA. Sparkle only
# looks at the newest item, so one entry is enough.
# The private key comes from $SPARKLE_ED_PRIVATE_KEY (never an argument).
# Usage: make-appcast.sh <zip> <version> <build> <download-url> <notes-url> <out.xml>
set -euo pipefail
ZIP="$1"; VERSION="$2"; BUILD="$3"; URL="$4"; NOTES="$5"; OUT="$6"
: "${SPARKLE_ED_PRIVATE_KEY:?SPARKLE_ED_PRIVATE_KEY missing}"
BIN="$(cd "$(dirname "$0")/.." && pwd)/.build/artifacts/sparkle/Sparkle/bin"

# sign_update prints: sparkle:edSignature="…" length="…"
ATTRS=$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$BIN/sign_update" --ed-key-file - "$ZIP") || true
[[ "$ATTRS" == *'sparkle:edSignature="'* ]] || { echo "make-appcast: signing failed" >&2; exit 1; }

xml() { local s="${1//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; printf '%s' "${s//\"/&quot;}"; }
TMP="$OUT.tmp.$$"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WinTab</title>
    <item>
      <title>WinTab $(xml "$VERSION")</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$(xml "$BUILD")</sparkle:version>
      <sparkle:shortVersionString>$(xml "$VERSION")</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$(xml "$NOTES")</sparkle:releaseNotesLink>
      <enclosure url="$(xml "$URL")" sparkle:version="$(xml "$BUILD")" sparkle:shortVersionString="$(xml "$VERSION")" type="application/octet-stream" $ATTRS />
    </item>
  </channel>
</rss>
XML
mv "$TMP" "$OUT"
```

Puis `chmod +x scripts/make-appcast.sh`.

- [ ] **Step 4: Lancer le test**

Run: `scripts/test-make-appcast.sh`
Expected: `test-make-appcast: OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-appcast.sh scripts/test-make-appcast.sh
git commit -m "make-appcast.sh : appcast Sparkle signé EdDSA, + test

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `SparkleUpdater`, préférence et menu

**Files:**
- Create: `Sources/WinTab/SparkleUpdater.swift`
- Modify: `Sources/WinTab/Preferences.swift`
- Modify: `Sources/WinTab/AppDelegate.swift`
- Modify: `Sources/WinTab/StatusItemController.swift`

**Interfaces:**
- Consumes: `UpdateInstallGate` (Task 1) ; délégué Sparkle vérifié dans les headers 2.9 :
  `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:) -> Bool`,
  `SUAppcastItem.displayVersionString`,
  `SPUStandardUpdaterController(startingUpdater:updaterDelegate:userDriverDelegate:)`,
  `checkForUpdates(_:)`.
- Produces: `SparkleUpdater(gate:)`, `.isEnabled: Bool`, `.checkForUpdates()` ;
  `Preferences.autoInstallUpdates: Bool` ; `StatusItemController.updater`,
  `.updateGate`, `.refresh()`.

- [ ] **Step 1: `Sources/WinTab/SparkleUpdater.swift`**

```swift
import Foundation
import Sparkle
import SwitcherCore

/// Bridges Sparkle to `UpdateInstallGate`. Sparkle downloads updates silently and
/// would normally install them on quit — which a menu-bar app almost never does —
/// so the immediate-install handler is handed to the gate instead.
///
/// Inactive in local builds: only the release workflow injects `SUFeedURL`
/// (see scripts/build-app.sh).
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    private let gate: UpdateInstallGate
    private var controller: SPUStandardUpdaterController?

    var isEnabled: Bool { controller != nil }

    init(gate: UpdateInstallGate) {
        self.gate = gate
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
        )
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        gate.updateReady(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("WinTab: update cycle aborted: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 2: `Preferences.autoInstallUpdates`**

Dans `Sources/WinTab/Preferences.swift`, ajouter la clé après `groupByAppKey` :

```swift
    private static let autoInstallUpdatesKey = "updates.autoInstall"
```

et la propriété après `groupByApp` :

```swift
    static var autoInstallUpdates: Bool {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: autoInstallUpdatesKey) != nil else { return true }  // default: on
            return d.bool(forKey: autoInstallUpdatesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoInstallUpdatesKey) }
    }
```

- [ ] **Step 3: Câbler `AppDelegate` (Review Focus 1)**

Dans `Sources/WinTab/AppDelegate.swift` :

1. Après `private lazy var controller = …`, ajouter :
   ```swift
       private let updateGate = UpdateInstallGate(autoInstall: Preferences.autoInstallUpdates)
       private lazy var updater = SparkleUpdater(gate: updateGate)
   ```
2. Remplacer `private var isOpen = false` par :
   ```swift
       /// Every open/close path goes through here, so the update gate never misses
       /// a close (commit, Esc, click, last window closed, aborted open).
       private var isOpen = false {
           didSet {
               guard isOpen != oldValue else { return }
               if isOpen { updateGate.switcherOpened() } else { updateGate.switcherClosed() }
           }
       }
   ```
3. Dans `applicationDidFinishLaunching`, remplacer `statusController.install()` par :
   ```swift
           statusController.updater = updater
           statusController.updateGate = updateGate
           updateGate.onPendingChange = { [weak self] _ in self?.statusController.refresh() }
           statusController.install()
   ```

- [ ] **Step 4: Items de menu**

Dans `Sources/WinTab/StatusItemController.swift` :

1. Après `var onShortcutChange: …`, ajouter :
   ```swift
       var updater: SparkleUpdater?
       var updateGate: UpdateInstallGate?

       func refresh() { rebuildMenu() }
   ```
2. Au début de `rebuildMenu()`, juste après `let mods = …`, ajouter :
   ```swift
           let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
               as? String ?? "dev"
           menu.addItem(NSMenuItem(title: "WinTab \(version)", action: nil, keyEquivalent: ""))

           if let pending = updateGate?.pendingVersion {
               let installItem = NSMenuItem(title: "Redémarrer pour installer v\(pending)",
                                            action: #selector(installUpdate), keyEquivalent: "")
               installItem.target = self
               menu.addItem(installItem)
           } else if updater?.isEnabled == true {
               let checkItem = NSMenuItem(title: "Rechercher les mises à jour…",
                                          action: #selector(checkForUpdates), keyEquivalent: "")
               checkItem.target = self
               menu.addItem(checkItem)
           } else {
               menu.addItem(NSMenuItem(title: "Mises à jour désactivées (build local)",
                                       action: nil, keyEquivalent: ""))
           }
           if updater?.isEnabled == true {
               let autoItem = NSMenuItem(title: "Installer automatiquement les mises à jour",
                                         action: #selector(toggleAutoInstall), keyEquivalent: "")
               autoItem.target = self
               autoItem.state = Preferences.autoInstallUpdates ? .on : .off
               menu.addItem(autoItem)
           }
           menu.addItem(.separator())
   ```
   (Les items sans action sont grisés automatiquement par `NSMenu`.)
3. Avant `@objc private func quit()`, ajouter :
   ```swift
       @objc private func checkForUpdates() { updater?.checkForUpdates() }

       @objc private func installUpdate() { updateGate?.installNow() }

       @objc private func toggleAutoInstall() {
           Preferences.autoInstallUpdates.toggle()
           updateGate?.autoInstall = Preferences.autoInstallUpdates
           rebuildMenu()
       }
   ```

- [ ] **Step 5: Build, tests, lancement local (Review Focus 3 et 5)**

```bash
swift test && ./scripts/build-app.sh --install
sleep 2 && pgrep -x WinTab && echo "running"
```
Expected: `34 tests in 6 suites passed`, `running` (l'app démarre, donc Sparkle se
charge). **Demander à Yvan** : ouvrir le menu → `WinTab 1.0.0` grisé et
`Mises à jour désactivées (build local)` ; ⌘Tab fonctionne toujours (autorisations à
accorder une fois à ce build signé « WinTab Dev »).

- [ ] **Step 6: Commit**

```bash
git add Sources/WinTab/SparkleUpdater.swift Sources/WinTab/Preferences.swift \
        Sources/WinTab/AppDelegate.swift Sources/WinTab/StatusItemController.swift
git commit -m "Mises à jour Sparkle : installation via UpdateInstallGate, items de menu

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Workflow de release sur push `main`

**Files:**
- Modify (réécriture complète): `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `VERSION`, `build-app.sh` (variables `WINTAB_*`), `check-bundle.sh`,
  `make-appcast.sh`, `test-make-appcast.sh`, les trois secrets (Tasks 2–4).
- Produces: release `v1.0.<run>` avec `WinTab-<version>.zip`, `.sha256`, `appcast.xml`.

- [ ] **Step 1: Écrire `.github/workflows/release.yml`**

```yaml
# Every push to main: tests, signed build, GitHub release + Sparkle appcast.
# See docs/superpowers/specs/2026-09-29-auto-update-design.md.
name: Release

on:
  push:
    branches: [main]
    paths-ignore:
      - "**/*.md"
      - "docs/**"
  workflow_dispatch:

# Releases are serialised: a push arriving mid-release waits instead of cancelling
# it (a half-published version number would be lost).
concurrency:
  group: release
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-26
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: .build
          key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Show environment
        run: |
          sw_vers
          swift --version

      - name: Tests
        run: |
          swift test
          scripts/test-make-appcast.sh

      - name: Import the "WinTab Dev" certificate
        env:
          CERT_P12_BASE64: ${{ secrets.CERT_P12_BASE64 }}
          CERT_P12_PASSWORD: ${{ secrets.CERT_P12_PASSWORD }}
        run: |
          KC="$RUNNER_TEMP/wintab.keychain-db"
          KP=$(openssl rand -base64 24)
          security create-keychain -p "$KP" "$KC"
          security set-keychain-settings -lut 21600 "$KC"
          security unlock-keychain -p "$KP" "$KC"
          printf '%s' "$CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/wintab.p12"
          security import "$RUNNER_TEMP/wintab.p12" -k "$KC" -P "$CERT_P12_PASSWORD" -T /usr/bin/codesign
          rm -f "$RUNNER_TEMP/wintab.p12"
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KP" "$KC" >/dev/null
          security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
          security find-identity -p codesigning "$KC" | grep -q '"WinTab Dev"'

      - name: Version
        run: |
          echo "WINTAB_VERSION=$(tr -d '[:space:]' < VERSION).$GITHUB_RUN_NUMBER" >> "$GITHUB_ENV"
          echo "WINTAB_BUILD=$GITHUB_RUN_NUMBER" >> "$GITHUB_ENV"

      - name: Build
        env:
          WINTAB_FEED_URL: https://github.com/${{ github.repository }}/releases/latest/download/appcast.xml
          WINTAB_REQUIRE_IDENTITY: "1"
        run: |
          scripts/build-app.sh
          scripts/check-bundle.sh WinTab.app "$WINTAB_VERSION" "$WINTAB_BUILD"
          # ditto (not zip) so the code signature survives the round-trip.
          ditto -c -k --keepParent WinTab.app "WinTab-$WINTAB_VERSION.zip"
          shasum -a 256 "WinTab-$WINTAB_VERSION.zip" | tee "WinTab-$WINTAB_VERSION.zip.sha256"

      - name: Appcast
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          BASE="https://github.com/$GITHUB_REPOSITORY/releases"
          scripts/make-appcast.sh "WinTab-$WINTAB_VERSION.zip" "$WINTAB_VERSION" "$WINTAB_BUILD" \
            "$BASE/download/v$WINTAB_VERSION/WinTab-$WINTAB_VERSION.zip" \
            "$BASE/tag/v$WINTAB_VERSION" \
            appcast.xml

      - name: Publish release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          cat > notes.md <<'NOTES'
          ## Install (first time only)

          1. Download the `WinTab-*.zip` below and unzip it into `/Applications`.
          2. Lift the download quarantine — the app is signed with a self-signed
             certificate, not notarized by Apple, so macOS blocks the first launch:

              ```bash
              xattr -dr com.apple.quarantine /Applications/WinTab.app
              open /Applications/WinTab.app
              ```

              Without a terminal: double-click, let it be blocked, then
              **System Settings → Privacy & Security → Open Anyway**.
          3. Grant **Accessibility** and **Screen Recording** in
             **System Settings → Privacy & Security**, then relaunch.

          After that, WinTab updates itself and keeps both permissions.
          Requires macOS 14 or later. Verify the download with the `.sha256` asset.
          NOTES
          gh release create "v$WINTAB_VERSION" \
            "WinTab-$WINTAB_VERSION.zip" "WinTab-$WINTAB_VERSION.zip.sha256" appcast.xml \
            --title "WinTab $WINTAB_VERSION" --target "$GITHUB_SHA" --latest \
            --notes-file notes.md

      - name: Delete the keychain
        if: always()
        run: security delete-keychain "$RUNNER_TEMP/wintab.keychain-db" 2>/dev/null || true
```

- [ ] **Step 2: Vérifier la syntaxe YAML**

Run: `ruby -ryaml -e 'y = YAML.load_file(".github/workflows/release.yml"); puts y["jobs"]["release"]["steps"].map { _1["name"] || _1["uses"] }'`
Expected: la liste des 10 étapes, sans erreur. Si `actionlint` est installé, `actionlint` ne doit rien signaler.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci : release sur push main, signée WinTab Dev, avec appcast Sparkle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: README — section *Install***

Remplacer, dans *Install*, la phrase d'introduction et les commandes par :

````markdown
Download the latest `WinTab-*.zip` from the
[**Releases**](https://github.com/YvanBetremieux/WinTab/releases/latest) page, then,
**the first time only**:

```bash
# 1. Unzip and install
unzip ~/Downloads/WinTab-*.zip -d /Applications

# 2. Lift the download quarantine (see "Why the scary warning?" below)
xattr -dr com.apple.quarantine /Applications/WinTab.app

# 3. Launch
open /Applications/WinTab.app
```
````

Garder le tableau des permissions. Juste après « Without them WinTab starts but shows an
empty switcher. », ajouter :

```markdown
### Updates

WinTab updates itself (Sparkle): it checks at launch and every 24 hours, downloads in
the background and relaunches as soon as the switcher is closed. Every release is
signed with the same certificate, so Accessibility and Screen Recording are kept.
Untick **Installer automatiquement les mises à jour** in the menu to install only
when you click **Redémarrer pour installer…**; **Rechercher les mises à jour…**
checks immediately.
```

- [ ] **Step 2: README — « Why the scary warning? »**

Remplacer les deux derniers paragraphes de cette sous-section par :

```markdown
Releases are signed with a self-signed certificate ("WinTab Dev"), not a paid Apple
Developer ID, so they cannot be notarized: macOS refuses the first launch of the
downloaded app, and the `xattr` command above removes the quarantine flag that
triggers this. Terminal-free alternative: double-click the app, let it be blocked,
then go to **System Settings → Privacy & Security** and click **Open Anyway**.

Because every release carries the same signature, macOS keeps your permissions across
updates, and Sparkle refuses an update signed by anything else.
```

(La première phrase de la sous-section qui parle d'*ad-hoc signed* disparaît.)

- [ ] **Step 3: README — *Build from source* et *Releasing***

Dans *Build from source*, remplacer « No third-party dependencies. » par
« The only dependency, [Sparkle](https://sparkle-project.org), is fetched by SwiftPM. »,
`swift test                        # 24 tests across 5 suites` par
`swift test                        # 34 tests across 6 suites`, et la phrase
« `VERSION=1.2.3 ./scripts/build-app.sh` stamps the bundle version. » par :

```markdown
Local builds are stamped `<VERSION>.0` and have **no updater** (no Sparkle feed), so a
release never overwrites the build you are working on.
```

Remplacer tout le contenu de la section *Releasing* par :

````markdown
Every push to `main` that touches more than docs (`**/*.md`, `docs/**`) publishes a
release, built by GitHub Actions on a macOS runner
([`.github/workflows/release.yml`](.github/workflows/release.yml)) — never from a local
machine. **Pushing to `main` ships to every installed copy within a day.**

The version is `<VERSION>.<run number>` (e.g. `1.0.42`); edit [`VERSION`](VERSION) to
move to `1.1`. The workflow runs the tests, imports the "WinTab Dev" certificate,
builds and checks the bundle (`scripts/check-bundle.sh`), zips it with `ditto`,
writes an EdDSA-signed `appcast.xml` (`scripts/make-appcast.sh`) and publishes the
zip, its SHA-256 and the appcast. Apps read
`releases/latest/download/appcast.xml`. `workflow_dispatch` re-runs it by hand.

Secrets (set once with `gh secret set`):

| Secret | Content |
|---|---|
| `CERT_P12_BASE64` | the "WinTab Dev" identity as a `.p12`, base64 (`P12_OUT=… P12_PASS=… scripts/make-signing-cert.sh`) |
| `CERT_P12_PASSWORD` | that `.p12`'s password |
| `SPARKLE_ED_PRIVATE_KEY` | `generate_keys --account wintab -x <file>`; the public half is `scripts/sparkle-public-key.txt` |
````

- [ ] **Step 4: README — *Project layout***

Dans le bloc, ajouter `UpdateInstallGate     When to install a downloaded update` après
`ShortcutConfig`, `SparkleUpdater        Sparkle → UpdateInstallGate bridge` après
`Permissions`, et remplacer la ligne `scripts/` par
`scripts/                   Build, signing, bundle check and appcast scripts`, puis
ajouter la ligne `VERSION                    major.minor of the next releases`.

- [ ] **Step 5: CLAUDE.md**

1. `swift test                        # 24 tests, 5 suites — …` → `# 34 tests, 6 suites — …`.
2. Remplacer `There are no dependencies to fetch and no generated files to refresh.` par :
   `The only dependency, Sparkle, is fetched by SwiftPM on the first build. Local builds have no Sparkle feed, so they never self-update.`
3. Dans *Git*, remplacer le paragraphe « Pushing a `v*` tag triggers… on your own initiative. » par :
   ```markdown
   **Every push to `main` (beyond docs) publishes a release that installed copies pick
   up automatically.** Never push without Yvan's explicit go-ahead for that push, and
   never create release tags by hand — the workflow does it.
   ```

- [ ] **Step 6: Relire et committer**

Run: `grep -n "ad-hoc\|v\*\|24 tests\|no dependencies" README.md CLAUDE.md`
Expected: plus aucune mention obsolète (hors la mention du repli ad-hoc local de
`make-signing-cert.sh`).

```bash
git add README.md CLAUDE.md
git commit -m "docs : release continue et mises à jour automatiques

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Première release et vérification de bout en bout (humaine)

- [ ] **Step 1: Demander l'accord explicite pour pousser**

Montrer `git log --oneline origin/main..main` à Yvan et attendre un « oui » pour ce push.

- [ ] **Step 2: Pousser et suivre le run**

```bash
git push origin main
gh run watch "$(gh run list -w Release -L 1 --json databaseId -q '.[0].databaseId')" --exit-status
gh release view --json tagName,assets -q '.tagName, .assets[].name'
```
Expected: run vert ; `v1.0.<N>` avec `WinTab-1.0.<N>.zip`, `.sha256`, `appcast.xml`.
Si le run échoue : lire `gh run view --log-failed`, corriger, et redemander l'accord
avant tout nouveau push.

- [ ] **Step 3: Installation manuelle par Yvan**

Yvan télécharge le zip, suit les étapes *Install* du README, accorde les deux
autorisations, vérifie ⌘Tab et que le menu affiche `WinTab 1.0.<N>` et
`Rechercher les mises à jour…`.

- [ ] **Step 4: Publier une deuxième release sans changement de code**

Avec l'accord de Yvan : `gh workflow run release.yml --ref main`, puis `gh run watch` comme
au step 2. Expected : `v1.0.<N+1>` publiée.

- [ ] **Step 5: Mise à jour de bout en bout**

Yvan clique **Rechercher les mises à jour…** et accepte. Critères de réussite, confirmés
par Yvan : l'app se relance, le menu affiche `WinTab 1.0.<N+1>`, et ⌘Tab montre les
vignettes **sans redemander les autorisations**.
