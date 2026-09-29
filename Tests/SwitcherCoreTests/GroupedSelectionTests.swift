import Testing
import CoreGraphics
@testable import SwitcherCore

@Suite struct GroupedSelectionTests {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "A", bundleId: nil, title: "t\(id)", frame: .zero)
    }
    private func groups(_ ids: [[CGWindowID]]) -> [[WindowInfo]] {
        ids.map { $0.map(win) }
    }

    @Test func initClampsCoordinate() {
        let s = GroupedSelection(groups: groups([[1, 2], [3]]), groupIndex: 9, depthIndex: 9)
        #expect(s.groupIndex == 1)
        #expect(s.depthIndex == 0)   // group 1 has one window
        #expect(s.selected?.id == 3)
    }

    @Test func nextGroupWrapsAndResetsDepth() {
        var s = GroupedSelection(groups: groups([[1, 2], [3, 4]]), groupIndex: 0, depthIndex: 1)
        s.nextGroup()
        #expect(s.groupIndex == 1)
        #expect(s.depthIndex == 0)
        s.nextGroup()                // wrap
        #expect(s.groupIndex == 0)
    }

    @Test func deeperClampsToGroupSize() {
        var s = GroupedSelection(groups: groups([[1, 2, 3]]))
        s.deeper(); #expect(s.depthIndex == 1)
        s.deeper(); #expect(s.depthIndex == 2)
        s.deeper(); #expect(s.depthIndex == 2)   // clamped
    }

    @Test func shallowerClampsAtZero() {
        var s = GroupedSelection(groups: groups([[1, 2]]), groupIndex: 0, depthIndex: 1)
        s.shallower(); #expect(s.depthIndex == 0)
        s.shallower(); #expect(s.depthIndex == 0)
    }

    @Test func removeSelectedDropsWindowThenGroup() {
        var s = GroupedSelection(groups: groups([[1, 2], [3]]), groupIndex: 0, depthIndex: 1)
        s.removeSelected()                       // removes id 2
        #expect(s.groups.map { $0.map(\.id) } == [[1], [3]])
        #expect(s.depthIndex == 0)
        s.select(group: 1, depth: 0)
        s.removeSelected()                       // removes id 3, group empties
        #expect(s.groups.map { $0.map(\.id) } == [[1]])
        #expect(s.groupIndex == 0)
    }

    @Test func emptyGroupsAreDropped() {
        let s = GroupedSelection(groups: groups([[1], []]))
        #expect(s.groups.count == 1)
    }
}
