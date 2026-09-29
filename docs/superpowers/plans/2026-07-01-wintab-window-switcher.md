# WinTab — Per-Window Alt-Tab Switcher — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu-bar app that replaces ⌘+Tab with a switcher showing one tile per *window* (each Chrome window, each Cursor project), with keyboard/mouse navigation, per-window close, MRU pre-selection of the previous window, and live thumbnails.

**Architecture:** Pure, unit-tested logic in a `SwitcherCore` library (models, MRU ordering, selection math, shortcut matching, and a `SwitcherController` orchestrator wired to protocols). System side-effects live in the `WinTab` executable behind those protocols: `CGEventTap` for hotkey interception, `ScreenCaptureKit` for window enumeration + thumbnails, Accessibility (`AXUIElement`) for focus/close, an `NSPanel` HUD for the UI, and an `NSStatusItem` menu bar.

**Tech Stack:** Swift 6.3 / SwiftPM (no Xcode), AppKit, ScreenCaptureKit, ApplicationServices (Accessibility), CoreGraphics event taps, ServiceManagement (`SMAppService`). Target macOS 14+.

> **NOTE — no git in this project.** The owner chose not to version this project. Every task ends with a **Checkpoint** (build + tests green) instead of a git commit. Do not run `git init`, `git commit`, or `git push`.

> **TOOLCHAIN (macOS 26) — REQUIRED.** The Command Line Tools `swift` is broken on this machine (it cannot compile *any* `Package.swift` — a macOS 26 CLT regression). Use the Homebrew Swift toolchain for every `swift`/`swiftc` command. Prepend it to PATH at the start of each shell:
> ```bash
> export PATH="/opt/homebrew/opt/swift/Swift-6.3.xctoolchain/usr/bin:$PATH"
> ```
> All `swift build` / `swift test` command lines below assume this PATH is set.

> **TESTING — REQUIRED.** `XCTest` is unavailable without a full Xcode install, so this project uses **swift-testing** (bundled with Swift 6.3), NOT XCTest. In every test file use `import Testing` with `@Suite`/`@Test`/`#expect(...)` instead of `import XCTest`/`XCTestCase`/`XCTAssert*`. The XCTest code blocks in the tasks below are behavioral specifications — translate each to swift-testing using this mapping:
> - `final class FooTests: XCTestCase { func test_x() {...} }` → `@Suite struct FooTests { @Test func x() {...} }`
> - `XCTAssertTrue(e)` → `#expect(e)`  ·  `XCTAssertFalse(e)` → `#expect(!(e))`
> - `XCTAssertEqual(a, b)` → `#expect(a == b)`  ·  `XCTAssertNil(a)` → `#expect(a == nil)`
> - private helper methods on the class → plain functions or methods on the struct
> Run tests with `swift test`. Filtering: `swift test --filter FooTests`.

---

## File Structure

```
Package.swift
Sources/
  SwitcherCore/                 # pure, testable — no AppKit/SCK
    WindowInfo.swift            # window data model (id, pid, appName, bundleId, title, frame)
    KeyModifiers.swift          # platform-agnostic modifier OptionSet
    ShortcutConfig.swift        # ShortcutConfig + ShortcutMatcher
    MRUList.swift               # most-recently-used ordering by CGWindowID
    SelectionState.swift        # selected index + navigation math
    SwitcherProtocols.swift     # WindowActing, SwitcherViewing
    SwitcherController.swift    # orchestration (open/navigate/close/commit/cancel)
  WinTab/                       # executable — system shells
    main.swift                  # NSApplication bootstrap
    AppDelegate.swift           # wiring; implements HotkeyDelegate + SwitcherPanelDelegate
    SystemProtocols.swift       # WindowSource, HotkeyDelegate, NavDirection
    CGEventTapHotkey.swift      # global ⌘+Tab interception (+ KeyModifiers.from(cgFlags:))
    ScreenCaptureWindowSource.swift  # SCK enumeration + thumbnails (WindowSource impl)
    AXWindowActions.swift       # AX raise/activate/close (WindowActing impl) + frontmostWindowID
    WorkspaceMRUTracker.swift   # NSWorkspace observer feeding MRUList
    SwitcherPanel.swift         # NSPanel HUD (SwitcherViewing impl)
    WindowTileView.swift        # one tile: thumbnail + icon + title + close button
    Permissions.swift           # accessibility + screen-recording checks
    Preferences.swift           # UserDefaults-backed ShortcutConfig
    StatusItemController.swift  # menu bar item + launch-at-login
Tests/
  SwitcherCoreTests/
    ShortcutMatcherTests.swift
    MRUListTests.swift
    SelectionStateTests.swift
    SwitcherControllerTests.swift
scripts/
  build-app.sh                  # assembles + ad-hoc signs WinTab.app
```

**Responsibility boundaries:** `SwitcherCore` never imports AppKit/ScreenCaptureKit — it holds only value logic and protocol definitions, so it is fully unit-testable with fakes. Images (icons, thumbnails) are *not* stored in the model; the UI fetches them by window id at display time. The executable target contains every side-effecting integration, each isolated in its own file behind a protocol from `SwitcherCore` or `SystemProtocols.swift`.

---

## Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/SwitcherCore/Placeholder.swift`
- Create: `Sources/WinTab/main.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinTab",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SwitcherCore"),
        .executableTarget(name: "WinTab", dependencies: ["SwitcherCore"]),
        .testTarget(name: "SwitcherCoreTests", dependencies: ["SwitcherCore"]),
    ]
)
```

- [ ] **Step 2: Create a temporary placeholder so the library compiles**

`Sources/SwitcherCore/Placeholder.swift`:

```swift
// Temporary — removed in Task 2 once real types exist.
enum SwitcherCorePlaceholder {}
```

- [ ] **Step 3: Create a minimal `main.swift`**

`Sources/WinTab/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Real delegate wired in Task 15.
app.run()
```

- [ ] **Step 4: Verify the package builds**

Run: `swift build`
Expected: `Build complete!` with no errors.

- [ ] **Step 5: Checkpoint** — `swift build` is green.

---

## Task 2: KeyModifiers + ShortcutConfig + ShortcutMatcher (TDD)

**Files:**
- Create: `Sources/SwitcherCore/KeyModifiers.swift`
- Create: `Sources/SwitcherCore/ShortcutConfig.swift`
- Create: `Tests/SwitcherCoreTests/ShortcutMatcherTests.swift`
- Delete: `Sources/SwitcherCore/Placeholder.swift`

- [ ] **Step 1: Write the failing test**

`Tests/SwitcherCoreTests/ShortcutMatcherTests.swift`:

```swift
import XCTest
@testable import SwitcherCore

final class ShortcutMatcherTests: XCTestCase {
    let matcher = ShortcutMatcher(config: .defaultTab)  // ⌘+Tab, keyCode 48

    func test_matches_command_tab() {
        XCTAssertTrue(matcher.matches(keyCode: 48, modifiers: [.command]))
    }

    func test_matches_command_shift_tab_for_reverse() {
        XCTAssertTrue(matcher.matches(keyCode: 48, modifiers: [.command, .shift]))
    }

    func test_does_not_match_tab_without_command() {
        XCTAssertFalse(matcher.matches(keyCode: 48, modifiers: []))
    }

    func test_does_not_match_command_with_other_key() {
        XCTAssertFalse(matcher.matches(keyCode: 12, modifiers: [.command])) // Q
    }

    func test_option_tab_config() {
        let m = ShortcutMatcher(config: ShortcutConfig(keyCode: 48, modifierRawValue: KeyModifiers.option.rawValue))
        XCTAssertTrue(m.matches(keyCode: 48, modifiers: [.option]))
        XCTAssertFalse(m.matches(keyCode: 48, modifiers: [.command]))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShortcutMatcherTests`
Expected: FAIL — `cannot find 'ShortcutMatcher' in scope`.

- [ ] **Step 3: Delete the placeholder and write `KeyModifiers.swift`**

Delete `Sources/SwitcherCore/Placeholder.swift`, then create `Sources/SwitcherCore/KeyModifiers.swift`:

```swift
public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift   = KeyModifiers(rawValue: 1 << 1)
    public static let option  = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}
```

- [ ] **Step 4: Write `ShortcutConfig.swift`**

`Sources/SwitcherCore/ShortcutConfig.swift`:

```swift
public struct ShortcutConfig: Equatable, Sendable {
    public var keyCode: UInt16          // Tab = 48
    public var modifierRawValue: UInt

    public init(keyCode: UInt16, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
    }

    public var modifiers: KeyModifiers { KeyModifiers(rawValue: modifierRawValue) }

    /// Default: ⌘+Tab
    public static let defaultTab = ShortcutConfig(
        keyCode: 48,
        modifierRawValue: KeyModifiers.command.rawValue
    )
}

public struct ShortcutMatcher {
    public let config: ShortcutConfig
    public init(config: ShortcutConfig) { self.config = config }

    /// True when the trigger key is pressed and all configured modifiers are held.
    /// Extra modifiers (e.g. Shift for reverse) are allowed.
    public func matches(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        keyCode == config.keyCode && modifiers.contains(config.modifiers)
    }

    /// The modifier(s) whose release commits the switch (e.g. Command).
    public var holdModifiers: KeyModifiers { config.modifiers }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter ShortcutMatcherTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Checkpoint** — `swift test --filter ShortcutMatcherTests` green.

---

## Task 3: WindowInfo model

**Files:**
- Create: `Sources/SwitcherCore/WindowInfo.swift`

- [ ] **Step 1: Write `WindowInfo.swift`**

`Sources/SwitcherCore/WindowInfo.swift`:

```swift
import CoreGraphics
import Darwin  // pid_t

/// Value describing one on-screen window. Identity is the CGWindowID.
/// Images (icon/thumbnail) are intentionally NOT stored here — the UI
/// fetches them by id so this type stays pure and testable.
public struct WindowInfo: Equatable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let bundleId: String?
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, pid: pid_t, appName: String,
                bundleId: String?, title: String, frame: CGRect) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleId = bundleId
        self.title = title
        self.frame = frame
    }

    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 4: MRUList (TDD)

**Files:**
- Create: `Sources/SwitcherCore/MRUList.swift`
- Create: `Tests/SwitcherCoreTests/MRUListTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/SwitcherCoreTests/MRUListTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SwitcherCore

final class MRUListTests: XCTestCase {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "A", bundleId: nil, title: "t\(id)",
                   frame: .zero)
    }

    func test_touch_moves_to_front() {
        var mru = MRUList()
        mru.touch(10); mru.touch(20); mru.touch(30)
        XCTAssertEqual(mru.order, [30, 20, 10])
        mru.touch(10)
        XCTAssertEqual(mru.order, [10, 30, 20])
    }

    func test_ordered_puts_recent_first_and_keeps_unknown_stable() {
        var mru = MRUList()
        mru.touch(2); mru.touch(1)          // order: [1, 2]
        let windows = [win(3), win(2), win(1), win(4)]  // 3 and 4 unknown
        let ordered = mru.ordered(windows).map(\.id)
        XCTAssertEqual(ordered, [1, 2, 3, 4])  // known by recency, unknown keep input order
    }

    func test_remove_drops_id() {
        var mru = MRUList()
        mru.touch(1); mru.touch(2)
        mru.remove(1)
        XCTAssertEqual(mru.order, [2])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MRUListTests`
Expected: FAIL — `cannot find 'MRUList' in scope`.

- [ ] **Step 3: Write `MRUList.swift`**

`Sources/SwitcherCore/MRUList.swift`:

```swift
import CoreGraphics

/// Tracks window focus recency. `order[0]` is most-recently-used.
public struct MRUList: Sendable {
    public private(set) var order: [CGWindowID] = []
    public init() {}

    public mutating func touch(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    public mutating func remove(_ id: CGWindowID) {
        order.removeAll { $0 == id }
    }

    /// Sort windows by recency. Known ids come first (most-recent first);
    /// unknown ids keep their original relative order (stable).
    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.enumerated().sorted { lhs, rhs in
            let ra = order.firstIndex(of: lhs.element.id) ?? Int.max
            let rb = order.firstIndex(of: rhs.element.id) ?? Int.max
            if ra != rb { return ra < rb }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MRUListTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Checkpoint** — `swift test --filter MRUListTests` green.

---

## Task 5: SelectionState (TDD)

**Files:**
- Create: `Sources/SwitcherCore/SelectionState.swift`
- Create: `Tests/SwitcherCoreTests/SelectionStateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/SwitcherCoreTests/SelectionStateTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SwitcherCore

final class SelectionStateTests: XCTestCase {
    private func wins(_ ids: [CGWindowID]) -> [WindowInfo] {
        ids.map { WindowInfo(id: $0, pid: 1, appName: "A", bundleId: nil,
                             title: "t\($0)", frame: .zero) }
    }

    func test_preselects_second_window() {
        let s = SelectionState(windows: wins([1, 2, 3]))
        XCTAssertEqual(s.selectedIndex, 1)
        XCTAssertEqual(s.selected?.id, 2)
    }

    func test_single_window_selects_first() {
        let s = SelectionState(windows: wins([9]))
        XCTAssertEqual(s.selectedIndex, 0)
    }

    func test_next_wraps_around() {
        var s = SelectionState(windows: wins([1, 2, 3])) // starts at 1
        s.next()                    // 2
        s.next()                    // wrap -> 0
        XCTAssertEqual(s.selectedIndex, 0)
    }

    func test_previous_wraps_around() {
        var s = SelectionState(windows: wins([1, 2, 3])) // starts at 1
        s.previous()                // 0
        s.previous()                // wrap -> 2
        XCTAssertEqual(s.selectedIndex, 2)
    }

    func test_select_index_bounds_checked() {
        var s = SelectionState(windows: wins([1, 2, 3]))
        s.select(2); XCTAssertEqual(s.selectedIndex, 2)
        s.select(99); XCTAssertEqual(s.selectedIndex, 2) // ignored
    }

    func test_remove_selected_reclamps_index() {
        var s = SelectionState(windows: wins([1, 2, 3]))
        s.select(2)                 // last
        s.removeSelected()          // removes id 3
        XCTAssertEqual(s.windows.map(\.id), [1, 2])
        XCTAssertEqual(s.selectedIndex, 1)
    }

    func test_remove_last_window_empties() {
        var s = SelectionState(windows: wins([1]))
        s.removeSelected()
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.selected)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SelectionStateTests`
Expected: FAIL — `cannot find 'SelectionState' in scope`.

- [ ] **Step 3: Write `SelectionState.swift`**

`Sources/SwitcherCore/SelectionState.swift`:

```swift
/// Holds the ordered window list and the current selection index.
/// Opening pre-selects the second window (the "previous" window).
public struct SelectionState: Sendable {
    public private(set) var windows: [WindowInfo]
    public private(set) var selectedIndex: Int

    public init(windows: [WindowInfo]) {
        self.windows = windows
        self.selectedIndex = windows.count > 1 ? 1 : 0
    }

    public var isEmpty: Bool { windows.isEmpty }

    public var selected: WindowInfo? {
        windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
    }

    public mutating func next() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
    }

    public mutating func previous() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + windows.count) % windows.count
    }

    public mutating func select(_ index: Int) {
        if windows.indices.contains(index) { selectedIndex = index }
    }

    public mutating func removeSelected() {
        guard windows.indices.contains(selectedIndex) else { return }
        windows.remove(at: selectedIndex)
        if selectedIndex >= windows.count {
            selectedIndex = max(0, windows.count - 1)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SelectionStateTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Checkpoint** — `swift test --filter SelectionStateTests` green.

---

## Task 6: Core protocols (WindowActing, SwitcherViewing)

**Files:**
- Create: `Sources/SwitcherCore/SwitcherProtocols.swift`

- [ ] **Step 1: Write `SwitcherProtocols.swift`**

`Sources/SwitcherCore/SwitcherProtocols.swift`:

```swift
/// Side-effecting actions on real windows. Implemented by AXWindowActions;
/// faked in tests.
public protocol WindowActing: AnyObject {
    func activate(_ window: WindowInfo)
    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void)
}

/// The switcher UI surface. Implemented by SwitcherPanel; faked in tests.
public protocol SwitcherViewing: AnyObject {
    func show(windows: [WindowInfo], selectedIndex: Int)
    func updateSelection(_ index: Int)
    func updateWindows(_ windows: [WindowInfo], selectedIndex: Int)
    func hide()
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 7: SwitcherController (TDD, with fakes)

**Files:**
- Create: `Sources/SwitcherCore/SwitcherController.swift`
- Create: `Tests/SwitcherCoreTests/SwitcherControllerTests.swift`

- [ ] **Step 1: Write the failing test (with fakes)**

`Tests/SwitcherCoreTests/SwitcherControllerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SwitcherCore

private final class FakeView: SwitcherViewing {
    var shown: [WindowInfo] = []
    var selectionUpdates: [Int] = []
    var rebuilds: [(windows: [WindowInfo], index: Int)] = []
    var hideCount = 0
    func show(windows: [WindowInfo], selectedIndex: Int) { shown = windows }
    func updateSelection(_ index: Int) { selectionUpdates.append(index) }
    func updateWindows(_ windows: [WindowInfo], selectedIndex: Int) {
        rebuilds.append((windows, selectedIndex))
    }
    func hide() { hideCount += 1 }
}

private final class FakeActions: WindowActing {
    var activated: [WindowInfo] = []
    var closed: [WindowInfo] = []
    var closeSucceeds = true
    func activate(_ window: WindowInfo) { activated.append(window) }
    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void) {
        closed.append(window)
        completion(closeSucceeds)
    }
}

final class SwitcherControllerTests: XCTestCase {
    private func wins(_ ids: [CGWindowID]) -> [WindowInfo] {
        ids.map { WindowInfo(id: $0, pid: 1, appName: "A", bundleId: nil,
                             title: "t\($0)", frame: .zero) }
    }

    func test_open_shows_windows_preselecting_second() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([1, 2, 3]))
        XCTAssertEqual(view.shown.map(\.id), [1, 2, 3])
        XCTAssertTrue(c.isOpen)
        XCTAssertEqual(c.currentSelection?.id, 2)
    }

    func test_selectNext_updates_view() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([1, 2, 3]))
        c.selectNext()   // 1 -> 2
        XCTAssertEqual(view.selectionUpdates.last, 2)
    }

    func test_commit_activates_selected_and_hides() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([1, 2, 3]))
        let activated = c.commit()
        XCTAssertEqual(activated?.id, 2)
        XCTAssertEqual(actions.activated.map(\.id), [2])
        XCTAssertEqual(view.hideCount, 1)
        XCTAssertFalse(c.isOpen)
    }

    func test_cancel_hides_without_activating() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([1, 2]))
        c.cancel()
        XCTAssertTrue(actions.activated.isEmpty)
        XCTAssertEqual(view.hideCount, 1)
        XCTAssertFalse(c.isOpen)
    }

    func test_closeSelected_closes_and_rebuilds() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([1, 2, 3]))   // selected id 2
        c.closeSelected()
        XCTAssertEqual(actions.closed.map(\.id), [2])
        XCTAssertEqual(view.rebuilds.last?.windows.map(\.id), [1, 3])
        XCTAssertTrue(c.isOpen)
    }

    func test_closeSelected_last_window_hides() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(windows: wins([7]))
        c.closeSelected()
        XCTAssertEqual(view.hideCount, 1)
        XCTAssertFalse(c.isOpen)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SwitcherControllerTests`
Expected: FAIL — `cannot find 'SwitcherController' in scope`.

- [ ] **Step 3: Write `SwitcherController.swift`**

`Sources/SwitcherCore/SwitcherController.swift`:

```swift
/// Orchestrates one switcher session. Pure of AppKit — talks only to the
/// SwitcherViewing and WindowActing protocols, so it is fully unit-testable.
public final class SwitcherController {
    private let view: SwitcherViewing
    private let actions: WindowActing
    private var state: SelectionState?

    public init(view: SwitcherViewing, actions: WindowActing) {
        self.view = view
        self.actions = actions
    }

    public var isOpen: Bool { state != nil }
    public var currentSelection: WindowInfo? { state?.selected }

    public func open(windows: [WindowInfo]) {
        let s = SelectionState(windows: windows)
        state = s
        view.show(windows: s.windows, selectedIndex: s.selectedIndex)
    }

    public func selectNext() {
        guard var s = state else { return }
        s.next(); state = s
        view.updateSelection(s.selectedIndex)
    }

    public func selectPrevious() {
        guard var s = state else { return }
        s.previous(); state = s
        view.updateSelection(s.selectedIndex)
    }

    public func selectIndex(_ index: Int) {
        guard var s = state else { return }
        s.select(index); state = s
        view.updateSelection(s.selectedIndex)
    }

    public func closeSelected() {
        guard var s = state, let target = s.selected else { return }
        actions.close(target) { [weak self] _ in
            guard let self, var current = self.state else { return }
            current.removeSelected()
            self.state = current
            if current.isEmpty {
                self.dismiss()
            } else {
                self.view.updateWindows(current.windows,
                                        selectedIndex: current.selectedIndex)
            }
        }
    }

    /// Activates the selected window and closes the switcher. Returns the
    /// activated window so the caller can record it in the MRU list.
    @discardableResult
    public func commit() -> WindowInfo? {
        guard let target = state?.selected else { dismiss(); return nil }
        actions.activate(target)
        dismiss()
        return target
    }

    public func cancel() { dismiss() }

    private func dismiss() {
        state = nil
        view.hide()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SwitcherControllerTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full core suite**

Run: `swift test`
Expected: PASS (all tasks 2/4/5/7 tests — 21 total).

- [ ] **Step 6: Checkpoint** — `swift test` green.

---

## Task 8: System protocols + hotkey delegate

**Files:**
- Create: `Sources/WinTab/SystemProtocols.swift`

- [ ] **Step 1: Write `SystemProtocols.swift`**

`Sources/WinTab/SystemProtocols.swift`:

```swift
import CoreGraphics
import SwitcherCore

/// Enumerates windows and captures thumbnails. Implemented by
/// ScreenCaptureWindowSource.
protocol WindowSource {
    func currentWindows() async -> [WindowInfo]
    func captureThumbnail(for window: WindowInfo, maxSize: CGSize) async -> CGImage?
}

enum NavDirection { case left, right }

/// Callbacks from the global event tap. AppDelegate conforms.
protocol HotkeyDelegate: AnyObject {
    var switcherIsOpen: Bool { get }
    func hotkeyOpenOrAdvance(reverse: Bool)  // trigger key pressed w/ hold modifier
    func hotkeyNavigate(_ direction: NavDirection)
    func hotkeyCloseSelected()               // W
    func hotkeyCancel()                      // Esc
    func hotkeyCommit()                      // hold modifier released
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 9: CGEventTapHotkey (⌘+Tab interception)

**Files:**
- Create: `Sources/WinTab/CGEventTapHotkey.swift`

- [ ] **Step 1: Write `CGEventTapHotkey.swift`**

`Sources/WinTab/CGEventTapHotkey.swift`:

```swift
import CoreGraphics
import SwitcherCore

/// Maps CoreGraphics event flags onto the platform-agnostic KeyModifiers.
extension KeyModifiers {
    static func from(cgFlags f: CGEventFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if f.contains(.maskCommand)   { m.insert(.command) }
        if f.contains(.maskShift)     { m.insert(.shift) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskControl)   { m.insert(.control) }
        return m
    }
}

// Virtual keycodes (US layout, layout-independent for these keys).
private enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let w: UInt16 = 13
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}

/// Global keyboard tap that intercepts (and swallows) the configured shortcut
/// so the native ⌘+Tab switcher never appears. Requires Accessibility.
final class CGEventTapHotkey {
    weak var delegate: HotkeyDelegate?
    var config: ShortcutConfig = .defaultTab

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<CGEventTapHotkey>
                    .fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-arm if the system disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let delegate = delegate else {
            return Unmanaged.passUnretained(event)
        }

        let mods = KeyModifiers.from(cgFlags: event.flags)

        if type == .flagsChanged {
            // Hold modifier released while open -> commit.
            if delegate.switcherIsOpen && !mods.contains(config.modifiers) {
                DispatchQueue.main.async { delegate.hotkeyCommit() }
            }
            return Unmanaged.passUnretained(event)
        }

        // keyDown
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let matcher = ShortcutMatcher(config: config)

        if matcher.matches(keyCode: keyCode, modifiers: mods) {
            let reverse = mods.contains(.shift)
            DispatchQueue.main.async { delegate.hotkeyOpenOrAdvance(reverse: reverse) }
            return nil  // swallow — native switcher never sees it
        }

        if delegate.switcherIsOpen {
            switch keyCode {
            case KeyCode.escape:
                DispatchQueue.main.async { delegate.hotkeyCancel() }
            case KeyCode.w:
                DispatchQueue.main.async { delegate.hotkeyCloseSelected() }
            case KeyCode.leftArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.left) }
            case KeyCode.rightArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.right) }
            default:
                break
            }
            return nil  // swallow all keys while the switcher is open
        }

        return Unmanaged.passUnretained(event)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green. (Runtime behavior verified in Task 16.)

---

## Task 10: ScreenCaptureWindowSource (enumeration + thumbnails)

**Files:**
- Create: `Sources/WinTab/ScreenCaptureWindowSource.swift`

- [ ] **Step 1: Write `ScreenCaptureWindowSource.swift`**

`Sources/WinTab/ScreenCaptureWindowSource.swift`:

```swift
import AppKit
import CoreGraphics
import ScreenCaptureKit
import SwitcherCore

/// Enumerates normal, on-screen windows and captures per-window thumbnails
/// via ScreenCaptureKit. Requires Screen Recording permission.
final class ScreenCaptureWindowSource: WindowSource {

    func currentWindows() async -> [WindowInfo] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ) else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowInfo] = []

        for w in content.windows {
            guard w.isOnScreen,
                  w.windowLayer == 0,                 // normal window layer
                  let app = w.owningApplication else { continue }
            if app.processID == myPID { continue }    // skip our own panel
            if w.frame.width < 40 || w.frame.height < 40 { continue }

            let title = w.title ?? ""
            result.append(WindowInfo(
                id: w.windowID,
                pid: app.processID,
                appName: app.applicationName,
                bundleId: app.bundleIdentifier,
                title: title.isEmpty ? app.applicationName : title,
                frame: w.frame
            ))
        }
        return result
    }

    func captureThumbnail(for window: WindowInfo, maxSize: CGSize) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            true, onScreenWindowsOnly: true
        ), let scWindow = content.windows.first(where: { $0.windowID == window.id })
        else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let cfg = SCStreamConfiguration()
        let w = max(scWindow.frame.width, 1)
        let h = max(scWindow.frame.height, 1)
        let scale = min(maxSize.width / w, maxSize.height / h, 1)
        cfg.width = max(1, Int(w * scale))
        cfg.height = max(1, Int(h * scale))
        cfg.showsCursor = false

        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: cfg
        )
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 11: AXWindowActions (raise / activate / close)

**Files:**
- Create: `Sources/WinTab/AXWindowActions.swift`

- [ ] **Step 1: Write `AXWindowActions.swift`**

`Sources/WinTab/AXWindowActions.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import SwitcherCore

/// Private CoreGraphics helper (used by AltTab and others) to read the
/// CGWindowID backing an AXUIElement. This is how we match SCK windows to
/// their Accessibility element.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(
    _ element: AXUIElement,
    _ identifier: UnsafeMutablePointer<CGWindowID>
) -> AXError

final class AXWindowActions: WindowActing {

    func activate(_ window: WindowInfo) {
        if let axWindow = axElement(for: window) {
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void) {
        guard let axWindow = axElement(for: window) else { completion(false); return }
        var buttonRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            axWindow, kAXCloseButtonAttribute as CFString, &buttonRef
        )
        if err == .success, let button = buttonRef {
            let pressErr = AXUIElementPerformAction(
                button as! AXUIElement, kAXPressAction as CFString
            )
            completion(pressErr == .success)
        } else {
            completion(false)
        }
    }

    /// CGWindowID of the frontmost app's focused window (for MRU seeding).
    func frontmostWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appEl, kAXFocusedWindowAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else { return nil }
        var wid = CGWindowID(0)
        if _AXUIElementGetWindow(focused as! AXUIElement, &wid) == .success {
            return wid
        }
        return nil
    }

    private func axElement(for window: WindowInfo) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appEl, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success, let axWindows = windowsRef as? [AXUIElement] else {
            return nil
        }
        for el in axWindows {
            var wid = CGWindowID(0)
            if _AXUIElementGetWindow(el, &wid) == .success, wid == window.id {
                return el
            }
        }
        return nil
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 12: WorkspaceMRUTracker

**Files:**
- Create: `Sources/WinTab/WorkspaceMRUTracker.swift`

- [ ] **Step 1: Write `WorkspaceMRUTracker.swift`**

`Sources/WinTab/WorkspaceMRUTracker.swift`:

```swift
import AppKit
import CoreGraphics
import SwitcherCore

/// Maintains the MRU list. It records our own committed switches and also
/// listens for external app activations, seeding the front window's id.
final class WorkspaceMRUTracker {
    private(set) var mru = MRUList()
    private var observer: NSObjectProtocol?

    /// Supplies the current frontmost window id (set by AppDelegate).
    var focusedWindowProvider: (() -> CGWindowID?)?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Small delay so the newly-activated app has a focused window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let id = self?.focusedWindowProvider?() {
                    self?.mru.touch(id)
                }
            }
        }
    }

    func recordSwitch(to id: CGWindowID) { mru.touch(id) }
    func remove(_ id: CGWindowID) { mru.remove(id) }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 13: WindowTileView

**Files:**
- Create: `Sources/WinTab/WindowTileView.swift`

- [ ] **Step 1: Write `WindowTileView.swift`**

`Sources/WinTab/WindowTileView.swift`:

```swift
import AppKit
import SwitcherCore

/// One tile: thumbnail on top, app icon + title below, ✕ close button on hover.
final class WindowTileView: NSView {
    static let tileWidth: CGFloat = 160
    static let tileHeight: CGFloat = 140

    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    private let thumbView = NSImageView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    init(window: WindowInfo) {
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: Self.tileWidth, height: Self.tileHeight))
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.tileWidth).isActive = true
        heightAnchor.constraint(equalToConstant: Self.tileHeight).isActive = true

        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.frame = NSRect(x: 10, y: 34, width: 140, height: 96)
        thumbView.autoresizingMask = [.width, .height]
        addSubview(thumbView)

        iconView.image = NSRunningApplication(processIdentifier: window.pid)?.icon
        iconView.frame = NSRect(x: 10, y: 6, width: 22, height: 22)
        addSubview(iconView)

        titleLabel.stringValue = window.title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 38, y: 7, width: 112, height: 18)
        addSubview(titleLabel)

        closeButton.title = "✕"
        closeButton.font = .systemFont(ofSize: 11, weight: .bold)
        closeButton.isBordered = false
        closeButton.frame = NSRect(x: 132, y: 112, width: 20, height: 20)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = selected ? 2 : 0
        layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : nil
    }

    func setThumbnail(_ image: NSImage?) { thumbView.image = image }

    @objc private func closeClicked() { onClose?() }

    override func mouseUp(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent)  { closeButton.isHidden = true }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 14: SwitcherPanel (NSPanel HUD)

**Files:**
- Create: `Sources/WinTab/SwitcherPanel.swift`

- [ ] **Step 1: Write `SwitcherPanel.swift`**

`Sources/WinTab/SwitcherPanel.swift`:

```swift
import AppKit
import SwitcherCore

protocol SwitcherPanelDelegate: AnyObject {
    func panelDidClickTile(at index: Int)
    func panelDidRequestClose(at index: Int)
    func panelThumbnail(for window: WindowInfo,
                        completion: @escaping (NSImage?) -> Void)
}

/// A borderless, non-activating HUD panel that renders a horizontal row of
/// window tiles. Because it never becomes key, all keyboard handling is done
/// by the event tap; the panel only handles mouse interaction.
final class SwitcherPanel: NSObject, SwitcherViewing {
    weak var delegate: SwitcherPanelDelegate?

    private var panel: NSPanel?
    private var tiles: [WindowTileView] = []

    func show(windows: [WindowInfo], selectedIndex: Int) {
        build(windows: windows, selectedIndex: selectedIndex)
    }

    func updateSelection(_ index: Int) {
        for (i, tile) in tiles.enumerated() { tile.setSelected(i == index) }
    }

    func updateWindows(_ windows: [WindowInfo], selectedIndex: Int) {
        build(windows: windows, selectedIndex: selectedIndex)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        tiles = []
    }

    private func build(windows: [WindowInfo], selectedIndex: Int) {
        panel?.orderOut(nil)

        let gap: CGFloat = 12
        let pad: CGFloat = 16
        let count = CGFloat(max(windows.count, 1))
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let maxWidth = screen.frame.width - 80

        tiles = windows.enumerated().map { index, window in
            let tile = WindowTileView(window: window)
            tile.onClick = { [weak self] in self?.delegate?.panelDidClickTile(at: index) }
            tile.onClose = { [weak self] in self?.delegate?.panelDidRequestClose(at: index) }
            tile.setSelected(index == selectedIndex)
            delegate?.panelThumbnail(for: window) { [weak tile] image in
                tile?.setThumbnail(image)
            }
            return tile
        }

        let stack = NSStackView(views: tiles)
        stack.orientation = .horizontal
        stack.spacing = gap
        stack.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        stack.translatesAutoresizingMaskIntoConstraints = true

        let contentWidth = min(
            count * WindowTileView.tileWidth + (count - 1) * gap + 2 * pad,
            maxWidth
        )
        let contentHeight = WindowTileView.tileHeight + 2 * pad

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0,
                                                width: contentWidth, height: contentHeight))
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        stack.frame = NSRect(
            x: 0, y: 0,
            width: max(contentWidth,
                       count * WindowTileView.tileWidth + (count - 1) * gap + 2 * pad),
            height: contentHeight
        )
        scroll.documentView = stack

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0,
                                                      width: contentWidth, height: contentHeight))
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 16
        visual.layer?.masksToBounds = true
        visual.addSubview(scroll)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = visual

        let f = screen.frame
        panel.setFrameOrigin(NSPoint(x: f.midX - contentWidth / 2,
                                     y: f.midY - contentHeight / 2))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Checkpoint** — `swift build` green.

---

## Task 15: Permissions + Preferences + StatusItemController

**Files:**
- Create: `Sources/WinTab/Permissions.swift`
- Create: `Sources/WinTab/Preferences.swift`
- Create: `Sources/WinTab/StatusItemController.swift`

- [ ] **Step 1: Write `Permissions.swift`**

`Sources/WinTab/Permissions.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    static func hasAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func hasScreenRecording() -> Bool { CGPreflightScreenCaptureAccess() }
    static func requestScreenRecording() { CGRequestScreenCaptureAccess() }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
}
```

- [ ] **Step 2: Write `Preferences.swift`**

`Sources/WinTab/Preferences.swift`:

```swift
import Foundation
import SwitcherCore

enum Preferences {
    private static let keyCodeKey = "shortcut.keyCode"
    private static let modKey = "shortcut.modifiers"

    static var shortcut: ShortcutConfig {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: keyCodeKey) != nil else { return .defaultTab }
            return ShortcutConfig(
                keyCode: UInt16(d.integer(forKey: keyCodeKey)),
                modifierRawValue: UInt(d.integer(forKey: modKey))
            )
        }
        set {
            let d = UserDefaults.standard
            d.set(Int(newValue.keyCode), forKey: keyCodeKey)
            d.set(Int(newValue.modifierRawValue), forKey: modKey)
        }
    }
}
```

- [ ] **Step 3: Write `StatusItemController.swift`**

`Sources/WinTab/StatusItemController.swift`:

```swift
import AppKit
import ServiceManagement
import SwitcherCore

/// Menu-bar item: shortcut choice (⌘+Tab / ⌥+Tab), launch-at-login, quit.
final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    var onShortcutChange: ((ShortcutConfig) -> Void)?

    func install() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.on.square", accessibilityDescription: "WinTab"
        )
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let mods = Preferences.shortcut.modifiers

        let cmdItem = NSMenuItem(title: "Raccourci : ⌘ + Tab",
                                 action: #selector(setCommand), keyEquivalent: "")
        cmdItem.target = self
        cmdItem.state = mods.contains(.command) ? .on : .off

        let optItem = NSMenuItem(title: "Raccourci : ⌥ + Tab",
                                 action: #selector(setOption), keyEquivalent: "")
        optItem.target = self
        optItem.state = mods.contains(.option) ? .on : .off

        menu.addItem(cmdItem)
        menu.addItem(optItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Lancer au démarrage",
                                   action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter WinTab",
                                  action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func setCommand() { apply(.defaultTab) }

    @objc private func setOption() {
        apply(ShortcutConfig(keyCode: 48, modifierRawValue: KeyModifiers.option.rawValue))
    }

    private func apply(_ config: ShortcutConfig) {
        Preferences.shortcut = config
        onShortcutChange?(config)
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("WinTab: launch-at-login toggle failed: \(error)")
        }
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Checkpoint** — `swift build` green.

---

## Task 16: AppDelegate wiring + main.swift

**Files:**
- Create: `Sources/WinTab/AppDelegate.swift`
- Modify: `Sources/WinTab/main.swift`

- [ ] **Step 1: Write `AppDelegate.swift`**

`Sources/WinTab/AppDelegate.swift`:

```swift
import AppKit
import CoreGraphics
import SwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate,
                         HotkeyDelegate, SwitcherPanelDelegate {

    private let source = ScreenCaptureWindowSource()
    private let actions = AXWindowActions()
    private let hotkey = CGEventTapHotkey()
    private let panel = SwitcherPanel()
    private let mruTracker = WorkspaceMRUTracker()
    private let statusController = StatusItemController()
    private lazy var controller = SwitcherController(view: panel, actions: actions)

    private var isOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusController.install()
        statusController.onShortcutChange = { [weak self] config in
            self?.hotkey.config = config
        }

        panel.delegate = self
        mruTracker.focusedWindowProvider = { [weak self] in self?.actions.frontmostWindowID() }
        mruTracker.start()

        if !Permissions.hasAccessibility(prompt: true) {
            Permissions.openAccessibilitySettings()
        }
        if !Permissions.hasScreenRecording() {
            Permissions.requestScreenRecording()
        }

        hotkey.delegate = self
        hotkey.config = Preferences.shortcut
        if !hotkey.start() {
            NSLog("WinTab: could not start event tap — grant Accessibility, then relaunch.")
        }
    }

    // MARK: HotkeyDelegate

    var switcherIsOpen: Bool { isOpen }

    func hotkeyOpenOrAdvance(reverse: Bool) {
        if isOpen {
            reverse ? controller.selectPrevious() : controller.selectNext()
            return
        }
        isOpen = true
        Task { @MainActor in
            var windows = await source.currentWindows()
            windows = mruTracker.mru.ordered(windows)
            guard !windows.isEmpty else { isOpen = false; return }
            controller.open(windows: windows)
        }
    }

    func hotkeyNavigate(_ direction: NavDirection) {
        direction == .left ? controller.selectPrevious() : controller.selectNext()
    }

    func hotkeyCloseSelected() { controller.closeSelected() }

    func hotkeyCancel() {
        controller.cancel()
        isOpen = false
    }

    func hotkeyCommit() {
        if let activated = controller.commit() {
            mruTracker.recordSwitch(to: activated.id)
        }
        isOpen = false
    }

    // MARK: SwitcherPanelDelegate

    func panelDidClickTile(at index: Int) {
        controller.selectIndex(index)
        if let activated = controller.commit() {
            mruTracker.recordSwitch(to: activated.id)
        }
        isOpen = false
    }

    func panelDidRequestClose(at index: Int) {
        controller.selectIndex(index)
        controller.closeSelected()
    }

    func panelThumbnail(for window: WindowInfo,
                        completion: @escaping (NSImage?) -> Void) {
        Task {
            let cg = await source.captureThumbnail(
                for: window, maxSize: CGSize(width: 280, height: 192)
            )
            await MainActor.run {
                completion(cg.map { NSImage(cgImage: $0, size: .zero) })
            }
        }
    }
}
```

- [ ] **Step 2: Replace `main.swift` to wire the delegate**

`Sources/WinTab/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 3: Verify build + full test suite**

Run: `swift build && swift test`
Expected: `Build complete!` and all core tests PASS.

- [ ] **Step 4: Checkpoint** — build + tests green.

---

## Task 17: Packaging (build-app.sh) + manual verification

**Files:**
- Create: `scripts/build-app.sh`

- [ ] **Step 1: Write `scripts/build-app.sh`**

`scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP="WinTab"
BUNDLE_ID="com.yvanb.wintab"
RELEASE_BIN=".build/release/$APP"
APP_DIR="$APP.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$RELEASE_BIN" "$APP_DIR/Contents/MacOS/$APP"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>WinTab affiche un aperçu de vos fenêtres ouvertes.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --deep --sign - --options runtime "$APP_DIR"

echo "==> Done. Move $APP_DIR to /Applications and launch it."
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x scripts/build-app.sh && ./scripts/build-app.sh`
Expected: ends with `==> Done.` and a `WinTab.app` directory exists.

> **TCC note:** ad-hoc (`--sign -`) signatures change their code hash whenever the binary changes, so macOS may re-prompt for Accessibility/Screen Recording after a rebuild. For stable permission across rebuilds, create a self-signed certificate in Keychain Access ("WinTab Dev") and replace `--sign -` with `--sign "WinTab Dev"`. Optional for personal use.

- [ ] **Step 3: Install and grant permissions**

```bash
cp -R WinTab.app /Applications/
open /Applications/WinTab.app
```
Then in System Settings → Privacy & Security:
- **Accessibility** → enable WinTab
- **Screen Recording** → enable WinTab
Relaunch WinTab after granting (quit via its menu-bar icon, then `open` again).

- [ ] **Step 4: Manual verification checklist**

Open several windows first: 3 Chrome windows (different pages), 2 Cursor windows (different projects), Finder.

- [ ] Press and hold ⌘, tap Tab → the WinTab HUD appears with **one tile per window** (3 distinct Chrome tiles, 2 distinct Cursor tiles), each with its title; the native ⌘+Tab switcher does **not** appear.
- [ ] On first open, the **2nd tile is pre-selected**; releasing ⌘ immediately switches to the previous window.
- [ ] Holding ⌘, repeated Tab advances selection and wraps; ⇧+Tab goes backward.
- [ ] Left/Right arrows move the selection while the HUD is open.
- [ ] Moving the mouse over a tile highlights the ✕ button; clicking a tile switches to that window.
- [ ] With a tile selected, pressing **W** closes that window; the tile disappears and selection re-clamps. Closing the last window dismisses the HUD.
- [ ] **Esc** dismisses the HUD without switching.
- [ ] Thumbnails populate shortly after the HUD appears (icon+title show immediately).
- [ ] Menu bar icon: switching between ⌘+Tab and ⌥+Tab changes the trigger; "Lancer au démarrage" toggles; "Quitter" exits.
- [ ] Trigger the HUD while a full-screen app is frontmost → the HUD still appears on top.

- [ ] **Step 5: Checkpoint** — release build produced, `WinTab.app` installed, manual checklist passes.

---

## Self-Review (author checklist — completed)

**Spec coverage:**
- Per-window enumeration → Task 10 (SCK, layer-0 filter). ✅
- Configurable shortcut, block native ⌘+Tab → Tasks 2, 9, 15 (matcher, event-tap swallow, menu toggle). ✅
- Navigation ⌘+Tab / ⇧+Tab / arrows / mouse / Esc → Tasks 7, 9, 13, 16. ✅
- Pre-select 2nd window (MRU) → Tasks 4, 5, 7, 12, 16. ✅
- Close window with W → Tasks 7, 11, 16. ✅
- Live thumbnails → Tasks 10, 13, 14, 16. ✅
- Non-activating HUD over full-screen → Task 14. ✅
- Menu-bar app, launch-at-login → Task 15. ✅
- `.app` packaging, ad-hoc sign, drag to /Applications → Task 17. ✅
- Permissions onboarding + degraded mode → Tasks 15, 16 (checks + settings deep-links). ✅

**Placeholder scan:** No TBD/TODO; every code step contains full code. ✅

**Type consistency:** `ShortcutConfig(keyCode:modifierRawValue:)`, `KeyModifiers`, `WindowInfo(id:pid:appName:bundleId:title:frame:)`, `SwitcherController.commit() -> WindowInfo?`, `WindowActing.close(_:completion:)`, `SwitcherViewing.{show,updateSelection,updateWindows,hide}` are used identically across tasks. ✅

**Known limitations (documented, out of v1 scope):** minimized windows, other Spaces / other-desktop full-screen apps, hidden apps, and quit-app (Q) are excluded per the spec. The shortcut editor is limited to ⌘+Tab / ⌥+Tab (a full key recorder is a future enhancement). Horizontal overflow with very many windows scrolls but has no scroller chrome.
```
