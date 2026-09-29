public struct ShortcutConfig: Equatable, Sendable {
    public var keyCode: UInt16
    public var modifierRawValue: UInt

    public init(keyCode: UInt16, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
    }

    public var modifiers: KeyModifiers { KeyModifiers(rawValue: modifierRawValue) }

    public static let defaultTab = ShortcutConfig(
        keyCode: 48,
        modifierRawValue: KeyModifiers.command.rawValue
    )
}

public struct ShortcutMatcher {
    public let config: ShortcutConfig
    public init(config: ShortcutConfig) { self.config = config }

    public func matches(keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        keyCode == config.keyCode && modifiers.contains(config.modifiers)
    }

    public var holdModifiers: KeyModifiers { config.modifiers }
}
