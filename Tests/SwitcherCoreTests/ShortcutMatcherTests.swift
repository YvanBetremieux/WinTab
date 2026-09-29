import Testing
@testable import SwitcherCore

@Suite struct ShortcutMatcherTests {
    let matcher = ShortcutMatcher(config: .defaultTab)

    @Test func matchesCommandTab() {
        #expect(matcher.matches(keyCode: 48, modifiers: [.command]))
    }
    @Test func matchesCommandShiftTabForReverse() {
        #expect(matcher.matches(keyCode: 48, modifiers: [.command, .shift]))
    }
    @Test func doesNotMatchTabWithoutCommand() {
        #expect(!matcher.matches(keyCode: 48, modifiers: []))
    }
    @Test func doesNotMatchCommandWithOtherKey() {
        #expect(!matcher.matches(keyCode: 12, modifiers: [.command]))
    }
    @Test func optionTabConfig() {
        let m = ShortcutMatcher(config: ShortcutConfig(keyCode: 48, modifierRawValue: KeyModifiers.option.rawValue))
        #expect(m.matches(keyCode: 48, modifiers: [.option]))
        #expect(!m.matches(keyCode: 48, modifiers: [.command]))
    }
}
