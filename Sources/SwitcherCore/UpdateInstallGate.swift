/// Decides *when* a downloaded update gets installed, independently of Sparkle.
///
/// An update is installed only while the switcher is closed — relaunching while the
/// user holds ⌘ would drop their switch. With `autoInstall` on it happens as soon as
/// possible; with it off, only after `installNow()`.
public final class UpdateInstallGate {
    private var pending: (version: String, install: () -> Void)?
    private var switcherOpen = false
    private var installRequested = false

    public var autoInstall: Bool {
        didSet { installIfAllowed() }
    }

    public var pendingVersion: String? { pending?.version }

    /// Called with the new pending version, or nil once it is installed.
    public var onPendingChange: ((String?) -> Void)?

    public init(autoInstall: Bool) {
        self.autoInstall = autoInstall
    }

    /// A newer update replaces one still waiting.
    public func updateReady(version: String, install: @escaping () -> Void) {
        pending = (version, install)
        onPendingChange?(version)
        installIfAllowed()
    }

    public func switcherOpened() { switcherOpen = true }

    public func switcherClosed() {
        switcherOpen = false
        installIfAllowed()
    }

    /// Menu action. Ignored when nothing is pending, so it cannot arm a later install.
    public func installNow() {
        guard pending != nil else { return }
        installRequested = true
        installIfAllowed()
    }

    private func installIfAllowed() {
        guard let update = pending, !switcherOpen, autoInstall || installRequested else { return }
        pending = nil
        installRequested = false
        onPendingChange?(nil)
        update.install()
    }
}
