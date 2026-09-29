# Working on WinTab

Per-window Alt-Tab replacement for macOS. Menu-bar app, no Dock icon. See
[README.md](README.md) for install, usage and the full project layout.

## Commands

```bash
swift test                        # 34 tests, 6 suites — run this before claiming anything works
./scripts/build-app.sh            # build + sign WinTab.app in the working directory
./scripts/build-app.sh --install  # …and copy to /Applications and relaunch
```

The only dependency, Sparkle, is fetched by SwiftPM on the first build. Local
builds have no Sparkle feed, so they never self-update.

## Things that will waste your time if you don't know them

- **Toolchain before source.** If the compiler reports impossible errors
  (`cannot find type 'CGFloat' in scope`, `CGPoint has no member 'zero'`,
  `unknown argument: '-target-arch-variant'`), it is a toolchain/SDK mismatch,
  not a bug in the code. Check `swift --version` first — Swift 6.4+ from
  Xcode/CLT works; the Homebrew Swift 6.3 toolchain is currently broken against
  the macOS 26.6 SDK. `build-app.sh` uses `$PATH`'s `swift`, overridable with
  `SWIFT=…`.
- **Tests are swift-testing**, not XCTest: `import Testing`, `@Suite`, `@Test`,
  `#expect`. Don't convert them to XCTest.
- **`.build/` is ~770 MB** and `WinTab.app/` is a build artifact. Both are
  gitignored — never commit them, never read through them when searching.
- Verifying a UI change needs a human: the switcher only renders with
  Accessibility + Screen Recording granted to the *installed* app. Build with
  `--install` and ask, rather than asserting it works.

## Where code goes

`Sources/SwitcherCore` is pure logic with no system frameworks, and it is unit
tested. `Sources/WinTab` is the untested shell around AppKit, ScreenCaptureKit,
the Accessibility API and CGEventTap, talking to the core through the ports in
`SwitcherProtocols.swift`.

New behaviour belongs in `SwitcherCore` with a test. Only reach for
`Sources/WinTab` when the system genuinely has to be touched.

## Git

Personal project. The repo-local identity is `yvan.betremieux@gmail.com` — the
papernest work address must never appear in a commit here. Don't push without
being asked.

**Every push to `main` (beyond docs) publishes a release that installed copies pick
up automatically.** Never push without Yvan's explicit go-ahead for that push, and
never create release tags by hand — the workflow does it.
