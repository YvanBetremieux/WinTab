# WinTab

A **per-window** Alt-Tab replacement for macOS.

macOS switches between *applications*; WinTab switches between *windows* — every
window of every app, in most-recently-used order, with live thumbnails. It runs
as a menu-bar app with no Dock icon (`LSUIElement`).

Requires macOS 14 or later (Apple Silicon and Intel).

---

## Install

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

Then grant **two** permissions in **System Settings → Privacy & Security**, and
relaunch the app:

| Permission | Why it is needed |
|---|---|
| **Accessibility** | Focus, close and raise other apps' windows |
| **Screen Recording** | Draw the live window thumbnails |

Without them WinTab starts but shows an empty switcher.

### Updates

WinTab updates itself (Sparkle): it checks at launch and every 24 hours, downloads in
the background and relaunches as soon as the switcher is closed. Every release is
signed with the same certificate, so Accessibility and Screen Recording are kept.
Untick **Installer automatiquement les mises à jour** in the menu to install only
when you click **Redémarrer pour installer…**; **Rechercher les mises à jour…**
checks immediately.

### Why the scary warning?

Releases are signed with a self-signed certificate ("WinTab Dev"), not a paid Apple
Developer ID, so they cannot be notarized: macOS refuses the first launch of the
downloaded app, and the `xattr` command above removes the quarantine flag that
triggers this. Terminal-free alternative: double-click the app, let it be blocked,
then go to **System Settings → Privacy & Security** and click **Open Anyway**.

Because every release carries the same signature, macOS keeps your permissions across
updates, and Sparkle refuses an update signed by anything else.

---

## Use

Press **⌘ + Tab** (the default; switchable to **⌥ + Tab** from the menu-bar icon)
and keep the modifier held down:

| Key | Action |
|---|---|
| `Tab` | Step forward through windows |
| `Shift` (tapped, modifier still held) | Step backward |
| `←` `→` | Move between windows / groups |
| `↑` `↓` | Move within a group (when *Group by application* is on) |
| `W` | Close the selected window |
| `Esc` | Cancel, switch nothing |
| *release the modifier* | Switch to the selected window |

The menu-bar icon holds the settings: shortcut (⌘/⌥), thumbnail size, horizontal
or vertical layout, include minimized windows, group by application, launch at
login.

Settings are stored in `UserDefaults` under the `com.yvanb.wintab` domain. To
carry them to another Mac:

```bash
defaults export com.yvanb.wintab wintab-prefs.plist   # old Mac
defaults import com.yvanb.wintab wintab-prefs.plist   # new Mac
```

---

## Build from source

**Requirements:** macOS 14+, and Xcode or Command Line Tools providing Swift 6.4
or newer (`swift --version`). The only dependency, [Sparkle](https://sparkle-project.org), is fetched by SwiftPM.

```bash
git clone https://github.com/YvanBetremieux/WinTab.git
cd WinTab

swift test                        # 34 tests across 6 suites

./scripts/make-signing-cert.sh    # run once — see below
./scripts/build-app.sh --install  # build, sign, install to /Applications, relaunch
```

`build-app.sh` without `--install` just leaves `WinTab.app` in the working
directory. Local builds are stamped `<VERSION>.0` and have **no updater** (no
Sparkle feed), so a release never overwrites the build you are working on.

### `make-signing-cert.sh` — run it once

It creates a self-signed **"WinTab Dev"** code-signing identity in your login
keychain. Its only job is to give the app a *stable* code identity, so macOS
keeps your Accessibility and Screen Recording grants across rebuilds. Without
it, `build-app.sh` falls back to ad-hoc signing and macOS makes you re-grant
both permissions after **every single build** — which is miserable while
developing.

On the first build afterwards macOS shows a one-time *"codesign wants to sign
using key…"* dialog: click **Always Allow**.

### Toolchain notes

Read this before debugging a build failure — this project has already been
bitten twice:

- **On macOS 26.0**, the Command Line Tools `swift` could not build *any*
  SwiftPM package (a dropped `PackageDescription` symbol), so the build was
  pinned to a Homebrew toolchain.
- **Since macOS 26.6 / CLT 27 (Swift 6.4)** the situation is reversed: the
  system `swift` builds this package fine, and the Homebrew Swift 6.3 toolchain
  is the broken one — it fails with `unknown argument: '-target-arch-variant'`
  and bogus `cannot find type 'CGFloat' in scope` errors against the current SDK.

`build-app.sh` therefore uses whatever `swift` is first on `PATH`, overridable:

```bash
SWIFT=/path/to/some/swift ./scripts/build-app.sh
```

If you hit compiler errors that make no sense (missing `CGFloat`, missing
`CGPoint.zero`), you are almost certainly on a toolchain/SDK mismatch — check
`swift --version` before suspecting the source.

Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`, `#expect`),
**not XCTest** — XCTest was unavailable when the suite was written (no full
Xcode on the machine at the time).

---

## Project layout

```
Sources/SwitcherCore/   Pure logic, no system frameworks — fully unit-tested
  WindowInfo            Value type describing a window
  MRUList               Most-recently-used ordering
  WindowGrouping        Grouping windows by application
  GroupedSelection      Cursor over groups/windows (next, prev, deeper, …)
  SwitcherController    Orchestration: open, navigate, close, commit, cancel
  ShortcutConfig        Shortcut model + matcher
  UpdateInstallGate     When to install a downloaded update
  KeyModifiers          Modifier flag set
  SwitcherProtocols     Ports implemented by the system layer

Sources/WinTab/         System layer (AppKit, ScreenCaptureKit, Accessibility)
  main.swift            Entry point
  AppDelegate           Wires the ports to the controller
  CGEventTapHotkey      Global hotkey capture via CGEventTap
  ScreenCaptureWindowSource  Window enumeration + thumbnails
  AXWindowActions       Focus / close / raise via the Accessibility API
  WorkspaceMRUTracker   Tracks window activation order
  SwitcherPanel         The overlay panel
  WindowTileView        A single window tile
  StatusItemController  Menu-bar icon and its menu
  Preferences           UserDefaults-backed settings
  Permissions           Accessibility / Screen Recording checks
  SparkleUpdater        Sparkle → UpdateInstallGate bridge

Tests/SwitcherCoreTests/   swift-testing suites for SwitcherCore
docs/superpowers/          Original design spec and implementation plan
scripts/                   Build, signing, bundle check and appcast scripts
VERSION                    major.minor of the next releases
```

The split is deliberate: everything that can be tested without a window server
lives in `SwitcherCore`; `WinTab` is the thin, untested shell around the system
frameworks. Put new logic in `SwitcherCore` with tests.

---

## Releasing

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
