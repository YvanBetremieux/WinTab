import Testing
import CoreGraphics
@testable import SwitcherCore

private final class FakeView: SwitcherViewing {
    var shownGroups: [[WindowInfo]] = []
    var shownSelection: (group: Int, depth: Int)?
    var selectionUpdates: [(group: Int, depth: Int)] = []
    var hideCount = 0
    func show(groups: [[WindowInfo]], groupIndex: Int, depthIndex: Int) {
        shownGroups = groups
        shownSelection = (groupIndex, depthIndex)
    }
    func updateSelection(groupIndex: Int, depthIndex: Int) {
        selectionUpdates.append((groupIndex, depthIndex))
    }
    func hide() { hideCount += 1 }
}

private final class FakeActions: WindowActing {
    var activated: [WindowInfo] = []
    var closed: [WindowInfo] = []
    var closeSucceeds = true
    func activate(_ window: WindowInfo) { activated.append(window) }
    func close(_ window: WindowInfo, completion: @escaping (Bool) -> Void) {
        closed.append(window); completion(closeSucceeds)
    }
}

@Suite struct SwitcherControllerTests {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "A", bundleId: nil, title: "t\(id)", frame: .zero)
    }
    private func groups(_ ids: [[CGWindowID]]) -> [[WindowInfo]] { ids.map { $0.map(win) } }

    @Test func openShowsGroupsAtInitialSelection() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1, 2], [3]]), groupIndex: 1, depthIndex: 0)
        #expect(view.shownGroups.map { $0.map(\.id) } == [[1, 2], [3]])
        #expect(view.shownSelection?.group == 1)
        #expect(c.currentSelection?.id == 3)
        #expect(c.isOpen)
    }

    @Test func nextGroupAndDeeperUpdateSelection() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1, 2], [3]]), groupIndex: 0, depthIndex: 0)
        c.deeper()
        #expect(view.selectionUpdates.last?.depth == 1)
        #expect(c.currentSelection?.id == 2)
        c.nextGroup()
        #expect(view.selectionUpdates.last?.group == 1)
        #expect(c.currentSelection?.id == 3)
    }

    @Test func commitActivatesSelectedAndHides() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1], [2]]), groupIndex: 1, depthIndex: 0)
        let activated = c.commit()
        #expect(activated?.id == 2)
        #expect(actions.activated.map(\.id) == [2])
        #expect(view.hideCount == 1)
        #expect(!c.isOpen)
    }

    @Test func cancelHidesWithoutActivating() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1], [2]]), groupIndex: 0, depthIndex: 0)
        c.cancel()
        #expect(actions.activated.isEmpty)
        #expect(view.hideCount == 1)
        #expect(!c.isOpen)
    }

    @Test func closeSelectedRemovesAndRebuilds() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1, 2], [3]]), groupIndex: 0, depthIndex: 1)  // id 2
        c.closeSelected()
        #expect(actions.closed.map(\.id) == [2])
        #expect(view.shownGroups.map { $0.map(\.id) } == [[1], [3]])
        #expect(c.isOpen)
    }

    @Test func closeFailureKeepsWindow() {
        let view = FakeView(); let actions = FakeActions()
        actions.closeSucceeds = false
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[1, 2]]), groupIndex: 0, depthIndex: 0)
        c.closeSelected()
        #expect(actions.closed.map(\.id) == [1])
        #expect(view.hideCount == 0)
        #expect(c.currentSelection?.id == 1)
        #expect(c.isOpen)
    }

    @Test func closeLastWindowHides() {
        let view = FakeView(); let actions = FakeActions()
        let c = SwitcherController(view: view, actions: actions)
        c.open(groups: groups([[7]]), groupIndex: 0, depthIndex: 0)
        c.closeSelected()
        #expect(view.hideCount == 1)
        #expect(!c.isOpen)
    }
}
