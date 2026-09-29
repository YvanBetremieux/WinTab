/// A 2-D selection over grouped windows. Each group is a list of windows
/// (index 0 = the "main line" representative, most recent). Selection is a
/// (groupIndex, depthIndex) coordinate. Ungrouped mode = groups of size 1,
/// so `deeper`/`shallower` become no-ops and it behaves like a flat row.
public struct GroupedSelection: Sendable {
    public private(set) var groups: [[WindowInfo]]
    public private(set) var groupIndex: Int
    public private(set) var depthIndex: Int

    public init(groups: [[WindowInfo]], groupIndex: Int = 0, depthIndex: Int = 0) {
        let cleaned = groups.filter { !$0.isEmpty }
        self.groups = cleaned
        if cleaned.isEmpty {
            self.groupIndex = 0
            self.depthIndex = 0
        } else {
            let g = min(max(groupIndex, 0), cleaned.count - 1)
            self.groupIndex = g
            self.depthIndex = min(max(depthIndex, 0), cleaned[g].count - 1)
        }
    }

    public var isEmpty: Bool { groups.isEmpty }

    public var selected: WindowInfo? {
        guard groups.indices.contains(groupIndex),
              groups[groupIndex].indices.contains(depthIndex) else { return nil }
        return groups[groupIndex][depthIndex]
    }

    /// Move along the main line to the next group (wraps), resetting depth.
    public mutating func nextGroup() {
        guard !groups.isEmpty else { return }
        groupIndex = (groupIndex + 1) % groups.count
        depthIndex = 0
    }

    public mutating func prevGroup() {
        guard !groups.isEmpty else { return }
        groupIndex = (groupIndex - 1 + groups.count) % groups.count
        depthIndex = 0
    }

    /// Descend into the current group's other windows (clamped).
    public mutating func deeper() {
        guard !groups.isEmpty else { return }
        depthIndex = min(depthIndex + 1, groups[groupIndex].count - 1)
    }

    /// Rise back toward the main line (clamped at 0).
    public mutating func shallower() {
        depthIndex = max(depthIndex - 1, 0)
    }

    public mutating func select(group: Int, depth: Int) {
        guard groups.indices.contains(group),
              groups[group].indices.contains(depth) else { return }
        groupIndex = group
        depthIndex = depth
    }

    /// Remove the selected window. If its group empties, drop the group.
    /// Indices are re-clamped so the selection stays valid.
    public mutating func removeSelected() {
        guard groups.indices.contains(groupIndex),
              groups[groupIndex].indices.contains(depthIndex) else { return }
        groups[groupIndex].remove(at: depthIndex)
        if groups[groupIndex].isEmpty {
            groups.remove(at: groupIndex)
            if groupIndex >= groups.count { groupIndex = max(0, groups.count - 1) }
            depthIndex = 0
        } else if depthIndex >= groups[groupIndex].count {
            depthIndex = groups[groupIndex].count - 1
        }
    }
}
