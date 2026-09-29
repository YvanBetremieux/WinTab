import CoreGraphics
import Darwin

public struct WindowInfo: Equatable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let bundleId: String?
    public let title: String
    public let frame: CGRect
    public let isMinimized: Bool

    public init(id: CGWindowID, pid: pid_t, appName: String,
                bundleId: String?, title: String, frame: CGRect,
                isMinimized: Bool = false) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.bundleId = bundleId
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }

    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
    }
}
