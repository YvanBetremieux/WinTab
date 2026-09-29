import CoreGraphics

public struct MRUList: Sendable {
    public private(set) var order: [CGWindowID] = []
    public init() {}

    public mutating func touch(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    public mutating func remove(_ id: CGWindowID) {
        order.removeAll { $0 == id }
    }

    public func ordered(_ windows: [WindowInfo]) -> [WindowInfo] {
        windows.enumerated().sorted { lhs, rhs in
            let ra = order.firstIndex(of: lhs.element.id) ?? Int.max
            let rb = order.firstIndex(of: rhs.element.id) ?? Int.max
            if ra != rb { return ra < rb }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
