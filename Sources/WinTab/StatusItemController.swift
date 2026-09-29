import AppKit
import ServiceManagement
import SwitcherCore

final class StatusItemController {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )

    var onShortcutChange: ((ShortcutConfig) -> Void)?
    var updater: SparkleUpdater?
    var updateGate: UpdateInstallGate?

    func refresh() { rebuildMenu() }

    func install() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.on.square", accessibilityDescription: "WinTab"
        )
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let mods = Preferences.shortcut.modifiers

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
        menu.addItem(NSMenuItem(title: "WinTab \(version)", action: nil, keyEquivalent: ""))

        if let pending = updateGate?.pendingVersion {
            let installItem = NSMenuItem(title: "Redémarrer pour installer v\(pending)",
                                         action: #selector(installUpdate), keyEquivalent: "")
            installItem.target = self
            menu.addItem(installItem)
        } else if updater?.isEnabled == true {
            let checkItem = NSMenuItem(title: "Rechercher les mises à jour…",
                                       action: #selector(checkForUpdates), keyEquivalent: "")
            checkItem.target = self
            menu.addItem(checkItem)
        } else {
            menu.addItem(NSMenuItem(title: "Mises à jour désactivées (build local)",
                                    action: nil, keyEquivalent: ""))
        }
        if updater?.isEnabled == true {
            let autoItem = NSMenuItem(title: "Installer automatiquement les mises à jour",
                                      action: #selector(toggleAutoInstall), keyEquivalent: "")
            autoItem.target = self
            autoItem.state = Preferences.autoInstallUpdates ? .on : .off
            menu.addItem(autoItem)
        }
        menu.addItem(.separator())

        let cmdItem = NSMenuItem(title: "Raccourci : ⌘ + Tab",
                                 action: #selector(setCommand), keyEquivalent: "")
        cmdItem.target = self
        cmdItem.state = mods.contains(.command) ? .on : .off

        let optItem = NSMenuItem(title: "Raccourci : ⌥ + Tab",
                                 action: #selector(setOption), keyEquivalent: "")
        optItem.target = self
        optItem.state = mods.contains(.option) ? .on : .off

        menu.addItem(cmdItem)
        menu.addItem(optItem)
        menu.addItem(.separator())

        // Thumbnail zoom
        let sizeMenu = NSMenu()
        let currentSize = Preferences.tileSize
        for (title, value) in [("Petites", TileSize.small),
                               ("Moyennes", TileSize.medium),
                               ("Grandes", TileSize.large)] {
            let item = NSMenuItem(title: title, action: #selector(setTileSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value.rawValue
            item.state = (currentSize == value) ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Taille des vignettes", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Bar orientation
        let orientMenu = NSMenu()
        let currentOrient = Preferences.orientation
        for (title, value) in [("Horizontale", PanelOrientation.horizontal),
                               ("Verticale", PanelOrientation.vertical)] {
            let item = NSMenuItem(title: title, action: #selector(setOrientation(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value.rawValue
            item.state = (currentOrient == value) ? .on : .off
            orientMenu.addItem(item)
        }
        let orientItem = NSMenuItem(title: "Disposition", action: nil, keyEquivalent: "")
        orientItem.submenu = orientMenu
        menu.addItem(orientItem)
        menu.addItem(.separator())

        let minItem = NSMenuItem(title: "Inclure les fenêtres réduites",
                                 action: #selector(toggleMinimized), keyEquivalent: "")
        minItem.target = self
        minItem.state = Preferences.includeMinimized ? .on : .off
        menu.addItem(minItem)

        let groupItem = NSMenuItem(title: "Grouper par application",
                                   action: #selector(toggleGroupByApp), keyEquivalent: "")
        groupItem.target = self
        groupItem.state = Preferences.groupByApp ? .on : .off
        menu.addItem(groupItem)
        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Lancer au démarrage",
                                   action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter WinTab",
                                  action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func setCommand() { apply(.defaultTab) }

    @objc private func setOption() {
        apply(ShortcutConfig(keyCode: 48, modifierRawValue: KeyModifiers.option.rawValue))
    }

    private func apply(_ config: ShortcutConfig) {
        Preferences.shortcut = config
        onShortcutChange?(config)
        rebuildMenu()
    }

    @objc private func setTileSize(_ sender: NSMenuItem) {
        Preferences.tileSize = TileSize(rawValue: sender.tag) ?? .medium
        rebuildMenu()
    }

    @objc private func setOrientation(_ sender: NSMenuItem) {
        Preferences.orientation = PanelOrientation(rawValue: sender.tag) ?? .horizontal
        rebuildMenu()
    }

    @objc private func toggleMinimized() {
        Preferences.includeMinimized.toggle()
        rebuildMenu()
    }

    @objc private func toggleGroupByApp() {
        Preferences.groupByApp.toggle()
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("WinTab: launch-at-login toggle failed: \(error)")
        }
        rebuildMenu()
    }

    @objc private func checkForUpdates() { updater?.checkForUpdates() }

    @objc private func installUpdate() { updateGate?.installNow() }

    @objc private func toggleAutoInstall() {
        Preferences.autoInstallUpdates.toggle()
        updateGate?.autoInstall = Preferences.autoInstallUpdates
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
