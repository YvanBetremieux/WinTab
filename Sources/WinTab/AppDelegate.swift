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
    private let updateGate = UpdateInstallGate(autoInstall: Preferences.autoInstallUpdates)
    private lazy var updater = SparkleUpdater(gate: updateGate)

    /// Every open/close path goes through here, so the update gate never misses
    /// a close (commit, Esc, click, last window closed, aborted open).
    private var isOpen = false {
        didSet {
            guard isOpen != oldValue else { return }
            if isOpen { updateGate.switcherOpened() } else { updateGate.switcherClosed() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusController.updater = updater
        statusController.updateGate = updateGate
        updateGate.onPendingChange = { [weak self] _ in self?.statusController.refresh() }
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
            reverse ? controller.prevGroup() : controller.nextGroup()
            return
        }
        isOpen = true
        Task { @MainActor in
            var windows = await source.currentWindows()
            if Preferences.includeMinimized {
                let existing = Set(windows.map(\.id))
                windows += actions.minimizedWindows().filter { !existing.contains($0.id) }
            }
            windows = mruTracker.mru.ordered(windows)
            guard !windows.isEmpty else { isOpen = false; return }

            let groups = WindowGrouping.groups(from: windows, byApp: Preferences.groupByApp)
            // Pre-select the previous window (2nd in MRU), wherever it landed.
            var initial = (group: 0, depth: 0)
            if windows.count > 1,
               let coord = WindowGrouping.coordinate(of: windows[1].id, in: groups) {
                initial = coord
            }
            controller.open(groups: groups, groupIndex: initial.group, depthIndex: initial.depth)
        }
    }

    func hotkeyNavigate(_ direction: NavDirection) {
        // Main line runs along the bar; the perpendicular axis enters groups.
        switch (Preferences.orientation, direction) {
        case (.horizontal, .left):  controller.prevGroup()
        case (.horizontal, .right): controller.nextGroup()
        case (.horizontal, .down):  controller.deeper()
        case (.horizontal, .up):    controller.shallower()
        case (.vertical, .up):      controller.prevGroup()
        case (.vertical, .down):    controller.nextGroup()
        case (.vertical, .right):   controller.deeper()
        case (.vertical, .left):    controller.shallower()
        }
    }

    func hotkeyCloseSelected() {
        controller.closeSelected()
        isOpen = controller.isOpen  // closing the last window dismisses the switcher
    }

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

    func panelDidClickTile(group: Int, depth: Int) {
        controller.select(group: group, depth: depth)
        if let activated = controller.commit() {
            mruTracker.recordSwitch(to: activated.id)
        }
        isOpen = false
    }

    func panelDidRequestClose(group: Int, depth: Int) {
        controller.select(group: group, depth: depth)
        controller.closeSelected()
        isOpen = controller.isOpen  // closing the last window dismisses the switcher
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
