/// Orchestrates one switcher session over grouped windows. Pure of AppKit —
/// talks only to the SwitcherViewing and WindowActing protocols.
public final class SwitcherController {
    private let view: SwitcherViewing
    private let actions: WindowActing
    private var selection: GroupedSelection?

    public init(view: SwitcherViewing, actions: WindowActing) {
        self.view = view
        self.actions = actions
    }

    public var isOpen: Bool { selection != nil }
    public var currentSelection: WindowInfo? { selection?.selected }

    public func open(groups: [[WindowInfo]], groupIndex: Int, depthIndex: Int) {
        let s = GroupedSelection(groups: groups, groupIndex: groupIndex, depthIndex: depthIndex)
        selection = s
        view.show(groups: s.groups, groupIndex: s.groupIndex, depthIndex: s.depthIndex)
    }

    private func mutate(_ change: (inout GroupedSelection) -> Void) {
        guard var s = selection else { return }
        change(&s)
        selection = s
        view.updateSelection(groupIndex: s.groupIndex, depthIndex: s.depthIndex)
    }

    public func nextGroup() { mutate { $0.nextGroup() } }
    public func prevGroup() { mutate { $0.prevGroup() } }
    public func deeper() { mutate { $0.deeper() } }
    public func shallower() { mutate { $0.shallower() } }
    public func select(group: Int, depth: Int) { mutate { $0.select(group: group, depth: depth) } }

    public func closeSelected() {
        guard let s = selection, let target = s.selected else { return }
        actions.close(target) { [weak self] success in
            guard let self, var current = self.selection else { return }
            guard success else { return }  // close failed: keep the tile
            current.removeSelected()
            self.selection = current
            if current.isEmpty {
                self.dismiss()
            } else {
                self.view.show(groups: current.groups,
                               groupIndex: current.groupIndex,
                               depthIndex: current.depthIndex)
            }
        }
    }

    /// Activates the selected window and closes the switcher. Returns the
    /// activated window so the caller can record it in the MRU list.
    @discardableResult
    public func commit() -> WindowInfo? {
        guard let target = selection?.selected else { dismiss(); return nil }
        actions.activate(target)
        dismiss()
        return target
    }

    public func cancel() { dismiss() }

    private func dismiss() {
        selection = nil
        view.hide()
    }
}
