# Release continue + mises à jour automatiques (Sparkle) — design

## Objectif

Chaque push sur `main` publie une nouvelle version de WinTab sous forme de release
GitHub, et les apps déjà installées se mettent à jour **d'elles-mêmes** : téléchargement,
remplacement du bundle et relance, sans ouvrir la page de la release. Après une mise à
jour, le switcher fonctionne toujours **sans redonner les autorisations** Accessibilité
et Enregistrement de l'écran.

L'approche reprend celle d'Onyx (`../Onyx`, spec `2026-09-29-release-ci-design.md`) :
Sparkle 2, appcast publié comme asset de release, certificat auto-signé partagé avec
le CI.

## Décisions prises

| Sujet | Décision |
|---|---|
| Mécanisme de mise à jour | Sparkle 2 (dépendance SwiftPM), zip signé EdDSA |
| Signature | Certificat auto-signé « WinTab Dev », identique en local et en CI (plus d'ad-hoc en release) |
| Déclencheur de release | Chaque push sur `main` (hors doc), plus `workflow_dispatch` |
| Moment de l'installation | Automatique dès que le switcher est fermé, avec un réglage pour la désactiver (installation alors sur clic dans le menu) |
| Builds locaux | Aucun updater actif : seul le CI injecte le flux Sparkle |

## Contraintes acceptées

- **Gatekeeper** : pas de Developer ID ni de notarisation. La *première* installation
  demande toujours `xattr -dr com.apple.quarantine` (ou « Ouvrir quand même »). Les
  mises à jour suivantes passent par Sparkle.
- **Le repo est public** : l'appcast et les assets sont téléchargeables sans
  authentification, et les minutes macOS sont gratuites.
- **Chaque push sur `main` part chez tous les utilisateurs.** Personne (Claude compris)
  ne pousse sur `main` sans accord explicite.

## Partie 1 — Pipeline de release

### `VERSION` (nouveau)

Fichier à la racine qui contient le `major.minor` (`1.0`). Pour passer en 1.1, on
modifie ce fichier. Il remplace la valeur codée en dur `VERSION="${VERSION:-1.0}"` de
`build-app.sh`.

### `scripts/build-app.sh` (modifié)

- Version :
  - `WINTAB_VERSION` remplace `CFBundleShortVersionString` si elle est définie ;
  - `WINTAB_BUILD` remplace `CFBundleVersion` si elle est définie ;
  - sinon on prend `<VERSION>.0` et le build `0`.
- Embarque `Sparkle.framework` (produit par SwiftPM, cherché dans `.build/` puis
  `.build/artifacts`) dans `Contents/Frameworks`. Le binaire doit avoir un rpath
  `@executable_path/../Frameworks`. On l'ajoute via `linkerSettings` dans
  `Package.swift`, ou avec `install_name_tool` si ça ne suffit pas.
- Ajoute `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks=true` et
  `SUAutomaticallyUpdate=true` à l'`Info.plist` **uniquement si `WINTAB_FEED_URL` est
  définie**, c'est-à-dire en CI. La clé publique EdDSA est une constante du script
  (elle n'a rien de secret).
- Signature : on signe le framework d'abord, puis le bundle, avec
  `--options runtime`. L'identité est « WinTab Dev ». Si `WINTAB_REQUIRE_IDENTITY=1`
  (en CI) et que l'identité est absente, le script **échoue** au lieu de se rabattre
  sur l'ad-hoc. En local, le repli ad-hoc existant est conservé.

### `scripts/check-bundle.sh` (nouveau)

Arguments : `<app> <version> <build>`. Il vérifie :
- `CFBundleShortVersionString` et `CFBundleVersion` ;
- la présence de `Contents/Frameworks/Sparkle.framework` ;
- la présence de `SUFeedURL` et `SUPublicEDKey` ;
- `codesign --verify --strict --deep` ;
- que l'autorité de signature est « WinTab Dev ».

Il sort en erreur au premier écart.

### `scripts/make-appcast.sh` (nouveau, adapté d'Onyx)

Entrées : zip, version, build, URL de téléchargement, URL des notes, chemin de sortie.
La clé privée est lue dans `SPARKLE_ED_PRIVATE_KEY`. Le script lance `sign_update`
(depuis `.build/artifacts/sparkle/Sparkle/bin`) et écrit un appcast à une seule entrée,
avec :
- `sparkle:version` = build ;
- `sparkle:shortVersionString` = version ;
- `sparkle:minimumSystemVersion` = 14.0 ;
- `sparkle:edSignature` et `length` ;
- un lien vers la page de la release.

### `.github/workflows/release.yml` (réécrit)

- **Déclencheur** : `push` sur `main` avec `paths-ignore: ["**/*.md", "docs/**"]`, plus
  `workflow_dispatch`. Le déclencheur sur tag `v*` est supprimé : c'est le workflow qui
  crée les tags.
- **Concurrence** : groupe `release`, `cancel-in-progress: false`.
- **Runner** : `macos-26`. **Permissions** : `contents: write`.
- **Étapes** :
  1. checkout, cache SwiftPM (clé = `Package.resolved`) ;
  2. `swift test`, puis `scripts/test-make-appcast.sh`. Si un test échoue, rien n'est
     publié ;
  3. import du certificat : `CERT_P12_BASE64` et `CERT_P12_PASSWORD` dans un trousseau
     temporaire (même bloc qu'Onyx), puis vérification que l'identité
     `"WinTab Dev"` est présente ;
  4. version : `WINTAB_VERSION=$(cat VERSION).$GITHUB_RUN_NUMBER`,
     `WINTAB_BUILD=$GITHUB_RUN_NUMBER` ;
  5. `WINTAB_FEED_URL=https://github.com/$GITHUB_REPOSITORY/releases/latest/download/appcast.xml`
     et `WINTAB_REQUIRE_IDENTITY=1`, puis `build-app.sh` et `check-bundle.sh` ;
  6. `ditto -c -k --keepParent WinTab.app WinTab-<version>.zip` et son `.sha256` ;
  7. `make-appcast.sh` avec `SPARKLE_ED_PRIVATE_KEY` ;
  8. `gh release create v<version>` avec le zip, `appcast.xml` et le `.sha256`,
     `--target $GITHUB_SHA --latest`, et des notes d'installation (reprises du workflow
     actuel et corrigées : `xattr` seulement pour la première installation) ;
  9. suppression du trousseau (`if: always()`).

`github.run_number` croît strictement, ce qui donne à Sparkle un `CFBundleVersion`
croissant.

### Secrets GitHub

| Secret | Source |
|---|---|
| `CERT_P12_BASE64` | identité « WinTab Dev » exportée du trousseau de session en `.p12` (format legacy SHA1/3DES), en base64 |
| `CERT_P12_PASSWORD` | mot de passe aléatoire choisi à l'export |
| `SPARKLE_ED_PRIVATE_KEY` | `generate_keys -x` (la clé reste aussi dans le trousseau de session) |

Claude les pose avec `gh secret set`. Les fichiers exportés ne passent que par le
scratchpad de la session et sont supprimés juste après leur envoi. L'export du `.p12`
demande le mot de passe de la session macOS.

## Partie 2 — Updater dans l'app

### `SwitcherCore/UpdateInstallGate.swift` (nouveau, testé)

Logique pure qui décide **quand** installer, sans dépendre de Sparkle.

```swift
public final class UpdateInstallGate {
    public init(autoInstall: Bool)
    public var autoInstall: Bool { get set }      // réactiver peut déclencher l'installation
    public private(set) var pendingVersion: String?  // mise à jour prête, pas encore installée
    public func updateReady(version: String, install: @escaping () -> Void)
    public func switcherOpened()
    public func switcherClosed()
    public func installNow()                      // action du menu « Redémarrer pour installer »
}
```

Règles :
- l'installation n'a lieu que si une mise à jour est prête **et** que le switcher est
  fermé ;
- elle se déclenche toute seule si `autoInstall` est vrai, au moment de
  `updateReady`, de `switcherClosed` ou quand `autoInstall` repasse à vrai ;
- si `autoInstall` est faux, seul `installNow()` la déclenche. Si le switcher est
  ouvert à ce moment-là, elle est repoussée à sa fermeture ;
- la closure `install` est appelée **au plus une fois** par mise à jour prête ;
- un nouveau `updateReady` remplace la mise à jour en attente.

Un callback `onPendingChange: ((String?) -> Void)?` permet au menu de se reconstruire.

### `WinTab/SparkleUpdater.swift` (nouveau)

- Il n'est créé que si `Bundle.main` contient `SUFeedURL`. Sans cette clé (build
  local), `isEnabled == false` et rien n'est démarré.
- Il enveloppe `SPUUpdater` avec `SPUStandardUserDriver` (fenêtres Sparkle standard pour
  les vérifications manuelles).
- Délégué : `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` (nom exact
  à confirmer dans la doc Sparkle 2 au moment du plan) renvoie `true` et transmet
  `immediateInstallationBlock` au gate avec `item.displayVersionString`.
- Il expose `checkForUpdates()` pour l'item de menu.
- Les échecs des vérifications en arrière-plan sont seulement loggés. Sparkle réessaie
  au cycle suivant (24 h, sa valeur par défaut) et refuse de lui-même une mise à jour
  dont la signature EdDSA ou l'identité de code ne correspond pas.

### Branchements

- `AppDelegate` crée le gate (`autoInstall: Preferences.autoInstallUpdates`) et le
  `SparkleUpdater`. Il appelle `switcherOpened()` et `switcherClosed()` là où `isOpen`
  change déjà.
- `Preferences.autoInstallUpdates` : `Bool`, stocké dans UserDefaults, `true` par
  défaut.
- `StatusItemController`, en haut du menu :
  - `WinTab <CFBundleShortVersionString>`, grisé ;
  - `Rechercher les mises à jour…`, ou `Mises à jour désactivées (build local)` grisé
    si l'updater est inactif ;
  - `Installer automatiquement les mises à jour`, une case à cocher ;
  - `Redémarrer pour installer v<pendingVersion>`, seulement si une mise à jour attend.

### Hors périmètre

Notification « Mis à jour vers vX » après relance (la version dans le menu suffit),
Developer ID et notarisation, DMG, deltas, canal beta, Homebrew cask.

## Partie 3 — Tests, documentation, mise en service

### Tests automatiques

`Tests/SwitcherCoreTests/UpdateInstallGateTests.swift` (swift-testing) :
- prête, switcher fermé, auto actif : installée tout de suite ;
- prête pendant que le switcher est ouvert : non installée, puis installée à
  `switcherClosed` ;
- auto coupé : non installée, `pendingVersion` renseigné, installée par `installNow()` ;
- auto coupé, `installNow()` switcher ouvert : installée à la fermeture ;
- auto réactivé avec une mise à jour en attente : installée (ou à la fermeture) ;
- la closure n'est appelée qu'une seule fois, même après plusieurs événements ;
- un second `updateReady` remplace la version en attente.

`scripts/test-make-appcast.sh` : appcast généré pour un faux zip avec une clé jetable,
signature vérifiée par `sign_update --verify`. Lancé en CI avant le build.

### Vérification de bout en bout (manuelle, humaine)

1. Premier push : la release `v1.0.N` contient le zip, `appcast.xml` et le `.sha256`.
2. Installation manuelle de `v1.0.N` (unzip, `xattr`, les deux autorisations).
3. Push d'un changement minuscule, ce qui donne `v1.0.N+1`.
4. « Rechercher les mises à jour… » : l'app se met à jour et se relance, et le switcher
   fonctionne **sans redonner les autorisations**. C'est le critère de réussite.

### Documentation

- `README.md` :
  - *Install* : `xattr` à la première installation seulement, mises à jour
    automatiques, autorisations conservées ;
  - « Why the scary warning? » corrigé : certificat auto-signé, plus d'ad-hoc ;
  - *Releasing* réécrit (push sur `main` = `1.0.<run>`, `VERSION` pour le
    `major.minor`) ;
  - *Build from source* : Sparkle via SwiftPM, pas d'updater dans les builds locaux ;
  - arborescence mise à jour.
- `CLAUDE.md` :
  - la règle sur les tags est remplacée par « pousser sur `main` publie une release
    chez tous les utilisateurs : ne jamais pousser sans accord explicite » ;
  - « no dependencies to fetch » est corrigé ;
  - le nombre de tests et de suites est mis à jour.

### Mise en service (avant le premier push)

1. `scripts/make-signing-cert.sh` : crée « WinTab Dev » (absent aujourd'hui du
   trousseau).
2. `generate_keys` de Sparkle : crée la paire EdDSA et donne la clé publique à mettre
   dans `build-app.sh`.
3. Export du `.p12` (demande le mot de passe macOS), puis `gh secret set` pour les trois
   secrets et suppression des fichiers temporaires.
4. Push sur `main`, **sur accord explicite**.

## Pourquoi le même certificat en CI

macOS attache les autorisations TCC à l'exigence désignée de la signature de l'app. Pour
un certificat auto-signé, cette exigence inclut l'empreinte du certificat. Une signature
ad-hoc, ou une nouvelle identité à chaque build, ferait donc perdre Accessibilité et
Enregistrement de l'écran à chaque mise à jour, et le switcher cesserait de marcher sans
prévenir. Sparkle refuse de plus une mise à jour signée par une autre identité que l'app
installée.
