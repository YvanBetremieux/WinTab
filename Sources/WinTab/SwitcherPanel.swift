import AppKit
import SwitcherCore

protocol SwitcherPanelDelegate: AnyObject {
    func panelDidClickTile(group: Int, depth: Int)
    func panelDidRequestClose(group: Int, depth: Int)
    func panelThumbnail(for window: WindowInfo,
                        completion: @escaping (NSImage?) -> Void)
}

/// Borderless, non-activating HUD that lays out grouped windows in a 2-D grid.
/// Horizontal: groups are columns (main line across the top row).
/// Vertical: groups are rows (main line down the left column).
final class SwitcherPanel: NSObject, SwitcherViewing {
    weak var delegate: SwitcherPanelDelegate?

    private var panel: NSPanel?
    private var placed: [(tile: WindowTileView, group: Int, depth: Int)] = []

    /// Padding around the grid, also kept around a tile scrolled into view.
    private static let pad: CGFloat = 16

    func show(groups: [[WindowInfo]], groupIndex: Int, depthIndex: Int) {
        build(groups: groups, groupIndex: groupIndex, depthIndex: depthIndex)
    }

    func updateSelection(groupIndex: Int, depthIndex: Int) {
        for entry in placed {
            entry.tile.setSelected(entry.group == groupIndex && entry.depth == depthIndex)
        }
        revealTile(group: groupIndex, depth: depthIndex)
    }

    /// Scrolls the grid just enough for the tile to be fully visible, so stepping
    /// with Tab past the panel's edge follows the selection.
    private func revealTile(group: Int, depth: Int) {
        guard let tile = placed.first(where: { $0.group == group && $0.depth == depth })?.tile
        else { return }
        tile.scrollToVisible(tile.bounds.insetBy(dx: -Self.pad, dy: -Self.pad))
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        placed = []
    }

    private func build(groups: [[WindowInfo]], groupIndex: Int, depthIndex: Int) {
        panel?.orderOut(nil)
        placed = []

        guard let screen = NSScreen.main ?? NSScreen.screens.first, !groups.isEmpty else { return }

        let gap: CGFloat = 12
        let pad = Self.pad
        let horizontal = Preferences.orientation == .horizontal
        let style: TileStyle = horizontal ? .card : .row
        let thumbnail = Preferences.tileSize.thumbnailSize
        let dims = horizontal ? Preferences.tileSize.dimensions : Preferences.tileSize.rowDimensions
        let tileW = dims.width, tileH = dims.height

        // Grid extent.
        let lanes = groups.count                                   // columns (h) / rows (v)
        let depth = groups.map(\.count).max() ?? 1                 // rows (h) / columns (v)
        let cols = horizontal ? lanes : depth
        let rows = horizontal ? depth : lanes

        let docWidth = pad * 2 + CGFloat(cols) * tileW + CGFloat(cols - 1) * gap
        let docHeight = pad * 2 + CGFloat(rows) * tileH + CGFloat(rows - 1) * gap

        let container = NSView(frame: NSRect(x: 0, y: 0, width: docWidth, height: docHeight))

        for (g, group) in groups.enumerated() {
            for (d, window) in group.enumerated() {
                // Column/row within the grid depending on orientation.
                let col = horizontal ? g : d
                let row = horizontal ? d : g
                let x = pad + CGFloat(col) * (tileW + gap)
                // Non-flipped coords: row 0 is the top → highest y.
                let y = docHeight - pad - tileH - CGFloat(row) * (tileH + gap)

                let tile = WindowTileView(window: window, size: dims, thumbnail: thumbnail, style: style)
                tile.setFrameOrigin(NSPoint(x: x, y: y))
                tile.onClick = { [weak self] in self?.delegate?.panelDidClickTile(group: g, depth: d) }
                tile.onClose = { [weak self] in self?.delegate?.panelDidRequestClose(group: g, depth: d) }
                tile.setSelected(g == groupIndex && d == depthIndex)
                delegate?.panelThumbnail(for: window) { [weak tile] image in
                    tile?.setThumbnail(image)
                }
                container.addSubview(tile)
                placed.append((tile, g, d))
            }
        }

        let contentWidth = min(docWidth, screen.frame.width - 80)
        let contentHeight = min(docHeight, screen.frame.height - 120)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        scroll.documentView = container
        // Show the top-left of the grid.
        if docHeight > contentHeight {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: docHeight - contentHeight))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        // The pre-selected window may sit beyond the visible area.
        revealTile(group: groupIndex, depth: depthIndex)

        let visual = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        visual.material = .hudWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 16
        visual.layer?.masksToBounds = true
        visual.addSubview(scroll)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = visual

        let f = screen.frame
        panel.setFrameOrigin(NSPoint(x: f.midX - contentWidth / 2,
                                     y: f.midY - contentHeight / 2))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
