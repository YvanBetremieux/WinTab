import Testing
import CoreGraphics
@testable import SwitcherCore

@Suite struct WindowGroupingTests {
    private static func win(_ id: CGWindowID, _ bundle: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: bundle, bundleId: bundle, title: "t\(id)", frame: .zero)
    }

    // MRU order: Cursor(1), Chrome(2), Cursor(3), Finder(4), Chrome(5)
    private var windows: [WindowInfo] {
        [
            Self.win(1, "cursor"), Self.win(2, "chrome"), Self.win(3, "cursor"),
            Self.win(4, "finder"), Self.win(5, "chrome"),
        ]
    }

    @Test func ungroupedIsOnePerGroup() {
        let g = WindowGrouping.groups(from: windows, byApp: false)
        #expect(g.map { $0.map(\.id) } == [[1], [2], [3], [4], [5]])
    }

    @Test func groupedByAppPreservesRecencyOrder() {
        let g = WindowGrouping.groups(from: windows, byApp: true)
        // App order = first appearance: cursor, chrome, finder.
        // Within app: MRU order preserved.
        #expect(g.map { $0.map(\.id) } == [[1, 3], [2, 5], [4]])
    }

    @Test func coordinateFindsWindow() {
        let g = WindowGrouping.groups(from: windows, byApp: true)
        let c = WindowGrouping.coordinate(of: 5, in: g)
        #expect(c?.group == 1)
        #expect(c?.depth == 1)
        #expect(WindowGrouping.coordinate(of: 99, in: g) == nil)
    }
}
