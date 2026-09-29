import AppKit
import CoreGraphics
import SwitcherCore

final class WorkspaceMRUTracker {
    private(set) var mru = MRUList()
    private var observer: NSObjectProtocol?

    var focusedWindowProvider: (() -> CGWindowID?)?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
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
