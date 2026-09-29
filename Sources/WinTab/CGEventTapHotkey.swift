import CoreGraphics
import SwitcherCore

extension KeyModifiers {
    static func from(cgFlags f: CGEventFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if f.contains(.maskCommand)   { m.insert(.command) }
        if f.contains(.maskShift)     { m.insert(.shift) }
        if f.contains(.maskAlternate) { m.insert(.option) }
        if f.contains(.maskControl)   { m.insert(.control) }
        return m
    }
}

private enum KeyCode {
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let w: UInt16 = 13
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}

final class CGEventTapHotkey {
    weak var delegate: HotkeyDelegate?
    var config: ShortcutConfig = .defaultTab

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastModifiers: KeyModifiers = []

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
                 | (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                let me = Unmanaged<CGEventTapHotkey>
                    .fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let delegate = delegate else {
            return Unmanaged.passUnretained(event)
        }

        let mods = KeyModifiers.from(cgFlags: event.flags)

        if type == .flagsChanged {
            if delegate.switcherIsOpen {
                if !mods.contains(config.modifiers) {
                    // Hold modifier (e.g. ⌘) released -> commit the selection.
                    DispatchQueue.main.async { delegate.hotkeyCommit() }
                } else if mods.contains(.shift) && !lastModifiers.contains(.shift) {
                    // Hold still down and Shift just pressed -> step backward.
                    DispatchQueue.main.async { delegate.hotkeyNavigate(.left) }
                }
            }
            lastModifiers = mods
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let matcher = ShortcutMatcher(config: config)

        if matcher.matches(keyCode: keyCode, modifiers: mods) {
            // Tab always steps forward; reverse is now done by tapping Shift.
            DispatchQueue.main.async { delegate.hotkeyOpenOrAdvance(reverse: false) }
            return nil
        }

        if delegate.switcherIsOpen {
            switch keyCode {
            case KeyCode.escape:
                DispatchQueue.main.async { delegate.hotkeyCancel() }
            case KeyCode.w:
                DispatchQueue.main.async { delegate.hotkeyCloseSelected() }
            case KeyCode.leftArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.left) }
            case KeyCode.rightArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.right) }
            case KeyCode.upArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.up) }
            case KeyCode.downArrow:
                DispatchQueue.main.async { delegate.hotkeyNavigate(.down) }
            default:
                break
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
