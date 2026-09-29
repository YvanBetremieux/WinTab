# WinTab

A **per-window** Alt-Tab replacement for macOS.

macOS switches between *applications*; WinTab switches between *windows* — every
window of every app, in most-recently-used order, with live thumbnails. It runs
as a menu-bar app with no Dock icon (`LSUIElement`).

Requires macOS 14 or later (Apple Silicon and Intel).

---

## Install

Download the latest `WinTab.zip` from the
[**Releases**](https://github.com/YvanBetremieux/WinTab/releases/latest) page, then:

```bash
# 1. Unzip and install
unzip ~/Downloads/WinTab.zip -d /Applications

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

### Why the scary warning?

Releases are **ad-hoc signed**, not signed with a paid Apple Developer ID, so
they cannot be notarized by Apple. macOS therefore refuses the first launch of
the downloaded app. The `xattr` command above removes the quarantine flag that
triggers this.

Terminal-free alternative: double-click the app, let it be blocked, then go to
**System Settings → Privacy & Security** and click **Open Anyway**.

Consequence of ad-hoc signing: the code identity changes with every release, so
macOS asks you to re-grant Accessibility and Screen Recording after each update.
Building from source with `scripts/make-signing-cert.sh` avoids this locally.

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
or newer (`swift --version`). No third-party dependencies.

```bash
git clone https://github.com/YvanBetremieux/WinTab.git
cd WinTab

swift test                        # 24 tests across 5 suites

./scripts/make-signing-cert.sh    # run once — see below
./scripts/build-app.sh --install  # build, sign, install to /Applications, relaunch
```

`build-app.sh` without `--install` just leaves `WinTab.app` in the working
directory. `VERSION=1.2.3 ./scripts/build-app.sh` stamps the bundle version.

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

Tests/SwitcherCoreTests/   swift-testing suites for SwitcherCore
docs/superpowers/          Original design spec and implementation plan
scripts/                   Build and signing scripts
```

The split is deliberate: everything that can be tested without a window server
lives in `SwitcherCore`; `WinTab` is the thin, untested shell around the system
frameworks. Put new logic in `SwitcherCore` with tests.

---

## Releasing

Releases are built by GitHub Actions on a macOS runner
([`.github/workflows/release.yml`](.github/workflows/release.yml)) — never from a
local machine, so the artifact is always reproducible from a clean checkout.

```bash
git tag v1.0.1
git push origin v1.0.1
```

The workflow runs the tests, builds and signs the bundle, stamps the version
from the tag, zips it with `ditto` (preserving the signature), and publishes a
release with `WinTab.zip` plus its SHA-256 checksum.

`workflow_dispatch` can also be used to re-run a release for an existing tag.
