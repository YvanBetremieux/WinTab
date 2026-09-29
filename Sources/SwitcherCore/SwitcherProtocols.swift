/// Side-effecting actions on real windows. Implemented by AXWindowActions;
/// faked in tests.
public protocol WindowActing: AnyObject {
    func activate(_ window: WindowInfo)
    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void)
}

/// The switcher UI surface (grouped, 2-D). Implemented by SwitcherPanel;
/// faked in tests.
public protocol SwitcherViewing: AnyObject {
    func show(groups: [[WindowInfo]], groupIndex: Int, depthIndex: Int)
    func updateSelection(groupIndex: Int, depthIndex: Int)
    func hide()
}
