import Foundation
import CoreGraphics
import SwitcherCore

/// Thumbnail zoom level. `.medium` is the original size.
enum TileSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2

    /// The preview image area — the single source of truth for thumbnail size.
    /// Both orientations render the thumbnail at exactly this size.
    var thumbnailSize: CGSize {
        switch self {
        case .small:  return CGSize(width: 104, height: 72)
        case .medium: return CGSize(width: 144, height: 100)
        case .large:  return CGSize(width: 208, height: 144)
        }
    }

    /// Card size (horizontal): thumbnail above a 30px icon+title strip, 8px padding.
    var dimensions: CGSize {
        let t = thumbnailSize
        return CGSize(width: t.width + 16, height: t.height + 38)
    }

    /// Row size (vertical): same thumbnail on the left, icon + title beside it.
    var rowDimensions: CGSize {
        let t = thumbnailSize
        return CGSize(width: t.width + 260, height: t.height + 16)
    }
}

/// Layout direction of the switcher bar.
enum PanelOrientation: Int, CaseIterable {
    case horizontal = 0
    case vertical = 1
}

enum Preferences {
    private static let keyCodeKey = "shortcut.keyCode"
    private static let modKey = "shortcut.modifiers"
    private static let tileSizeKey = "appearance.tileSize"
    private static let orientationKey = "appearance.orientation"
    private static let includeMinimizedKey = "behavior.includeMinimized"
    private static let groupByAppKey = "behavior.groupByApp"
    private static let autoInstallUpdatesKey = "updates.autoInstall"

    static var shortcut: ShortcutConfig {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: keyCodeKey) != nil else { return .defaultTab }
            return ShortcutConfig(
                keyCode: UInt16(d.integer(forKey: keyCodeKey)),
                modifierRawValue: UInt(d.integer(forKey: modKey))
            )
        }
        set {
            let d = UserDefaults.standard
            d.set(Int(newValue.keyCode), forKey: keyCodeKey)
            d.set(Int(newValue.modifierRawValue), forKey: modKey)
        }
    }

    static var tileSize: TileSize {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: tileSizeKey) != nil else { return .medium }  // default: medium
            return TileSize(rawValue: d.integer(forKey: tileSizeKey)) ?? .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: tileSizeKey) }
    }

    static var orientation: PanelOrientation {
        get { PanelOrientation(rawValue: UserDefaults.standard.integer(forKey: orientationKey)) ?? .horizontal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: orientationKey) }
    }

    static var includeMinimized: Bool {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: includeMinimizedKey) != nil else { return true }  // default: on
            return d.bool(forKey: includeMinimizedKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: includeMinimizedKey) }
    }

    static var groupByApp: Bool {
        get { UserDefaults.standard.bool(forKey: groupByAppKey) }  // default: off
        set { UserDefaults.standard.set(newValue, forKey: groupByAppKey) }
    }

    static var autoInstallUpdates: Bool {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: autoInstallUpdatesKey) != nil else { return true }  // default: on
            return d.bool(forKey: autoInstallUpdatesKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: autoInstallUpdatesKey) }
    }
}
