import Foundation
import Sparkle
import SwitcherCore

/// Bridges Sparkle to `UpdateInstallGate`. Sparkle downloads updates silently and
/// would normally install them on quit — which a menu-bar app almost never does —
/// so the immediate-install handler is handed to the gate instead.
///
/// Inactive in local builds: only the release workflow injects `SUFeedURL`
/// (see scripts/build-app.sh).
final class SparkleUpdater: NSObject, SPUUpdaterDelegate {
    private let gate: UpdateInstallGate
    private var controller: SPUStandardUpdaterController?

    var isEnabled: Bool { controller != nil }

    init(gate: UpdateInstallGate) {
        self.gate = gate
        super.init()
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
        )
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater,
                 willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        gate.updateReady(version: item.displayVersionString, install: immediateInstallHandler)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("WinTab: update cycle aborted: \(error.localizedDescription)")
    }
}
