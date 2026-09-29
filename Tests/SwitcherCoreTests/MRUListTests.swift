import Testing
import CoreGraphics
@testable import SwitcherCore

@Suite struct MRUListTests {
    private func win(_ id: CGWindowID) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: "A", bundleId: nil, title: "t\(id)", frame: .zero)
    }
    @Test func touchMovesToFront() {
        var mru = MRUList()
        mru.touch(10); mru.touch(20); mru.touch(30)
        #expect(mru.order == [30, 20, 10])
        mru.touch(10)
        #expect(mru.order == [10, 30, 20])
    }
    @Test func orderedPutsRecentFirstAndKeepsUnknownStable() {
        var mru = MRUList()
        mru.touch(2); mru.touch(1)
        let windows = [win(3), win(2), win(1), win(4)]
        #expect(mru.ordered(windows).map(\.id) == [1, 2, 3, 4])
    }
    @Test func removeDropsId() {
        var mru = MRUList()
        mru.touch(1); mru.touch(2)
        mru.remove(1)
        #expect(mru.order == [2])
    }
}
