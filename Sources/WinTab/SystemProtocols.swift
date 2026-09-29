import CoreGraphics
import SwitcherCore

protocol WindowSource {
    func currentWindows() async -> [WindowInfo]
    func captureThumbnail(for window: WindowInfo, maxSize: CGSize) async -> CGImage?
}

enum NavDirection { case left, right, up, down }

protocol HotkeyDelegate: AnyObject {
    var switcherIsOpen: Bool { get }
    func hotkeyOpenOrAdvance(reverse: Bool)
    func hotkeyNavigate(_ direction: NavDirection)
    func hotkeyCloseSelected()
    func hotkeyCancel()
    func hotkeyCommit()
}
