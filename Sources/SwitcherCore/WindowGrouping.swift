import CoreGraphics

/// Turns an ordered (MRU-first) window list into display groups.
public enum WindowGrouping {

    /// When `byApp` is true, windows are grouped by application (bundle id,
    /// falling back to pid). App order follows first appearance in `windows`
    /// (i.e. recency), and within each app the given order is preserved.
    /// When `byApp` is false, every window becomes its own single-item group,
    /// which reproduces the flat (ungrouped) row.
    public static func groups(from windows: [WindowInfo], byApp: Bool) -> [[WindowInfo]] {
        guard byApp else { return windows.map { [$0] } }
        var order: [String] = []
        var map: [String: [WindowInfo]] = [:]
        for w in windows {
            let key = w.bundleId ?? "pid:\(w.pid)"
            if map[key] == nil { order.append(key); map[key] = [] }
            map[key]?.append(w)
        }
        return order.map { map[$0] ?? [] }
    }

    /// The (group, depth) coordinate of the window with `id`, or nil if absent.
    /// Used to pre-select the previous window regardless of grouping.
    public static func coordinate(of id: CGWindowID,
                                  in groups: [[WindowInfo]]) -> (group: Int, depth: Int)? {
        for (g, group) in groups.enumerated() {
            if let d = group.firstIndex(where: { $0.id == id }) {
                return (g, d)
            }
        }
        return nil
    }
}
