import Testing
@testable import SwitcherCore

@Suite struct UpdateInstallGateTests {
    /// Counts calls to the install closure handed to the gate.
    private final class Installer {
        var count = 0
        func action() -> () -> Void { { self.count += 1 } }
    }

    @Test func installsImmediatelyWhenReadyAndSwitcherClosed() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 1)
        #expect(gate.pendingVersion == nil)
    }

    @Test func waitsForSwitcherToClose() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.switcherOpened()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func manualModeKeepsUpdatePendingUntilInstallNow() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened(); gate.switcherClosed()
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
        gate.installNow()
        #expect(i.count == 1)
        #expect(gate.pendingVersion == nil)
    }

    @Test func manualInstallNowWhileOpenDefersToClose() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened()
        gate.installNow()
        #expect(i.count == 0)
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func reenablingAutoInstallInstallsPendingUpdate() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.autoInstall = true
        #expect(i.count == 1)
    }

    @Test func reenablingAutoInstallWhileOpenWaitsForClose() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened()
        gate.autoInstall = true
        #expect(i.count == 0)
        gate.switcherClosed()
        #expect(i.count == 1)
    }

    @Test func installsAtMostOncePerReadyUpdate() {
        let gate = UpdateInstallGate(autoInstall: true); let i = Installer()
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.switcherOpened(); gate.switcherClosed()
        gate.installNow()
        gate.autoInstall = false; gate.autoInstall = true
        #expect(i.count == 1)
    }

    @Test func laterUpdateReplacesPendingOne() {
        let gate = UpdateInstallGate(autoInstall: false)
        let first = Installer(); let second = Installer()
        gate.updateReady(version: "1.0.2", install: first.action())
        gate.updateReady(version: "1.0.3", install: second.action())
        #expect(gate.pendingVersion == "1.0.3")
        gate.installNow()
        #expect(first.count == 0)
        #expect(second.count == 1)
    }

    @Test func notifiesPendingChanges() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        var seen: [String?] = []
        gate.onPendingChange = { seen.append($0) }
        gate.updateReady(version: "1.0.2", install: i.action())
        gate.installNow()
        #expect(seen == ["1.0.2", nil])
    }

    @Test func installNowWithoutPendingDoesNotArmLaterUpdate() {
        let gate = UpdateInstallGate(autoInstall: false); let i = Installer()
        gate.installNow()
        gate.updateReady(version: "1.0.2", install: i.action())
        #expect(i.count == 0)
        #expect(gate.pendingVersion == "1.0.2")
    }
}
