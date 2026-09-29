import AppKit
import SwitcherCore

/// How a tile arranges its contents.
enum TileStyle {
    case card  // thumbnail on top, icon + title below (horizontal bar)
    case row   // thumbnail on the left, icon + title beside it (vertical bar)
}

final class WindowTileView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?

    private let thumbView = NSImageView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private var trackingArea: NSTrackingArea?

    /// `size` is the whole tile; `thumbnail` is the exact preview area (identical
    /// across orientations); `style` comes from the orientation.
    init(window: WindowInfo, size: CGSize, thumbnail: CGSize, style: TileStyle) {
        super.init(frame: NSRect(origin: .zero, size: size))
        let w = size.width, h = size.height
        let p: CGFloat = 8
        let iconSize: CGFloat = 22
        let thumbW = thumbnail.width, thumbH = thumbnail.height

        wantsLayer = true
        layer?.cornerRadius = 10

        let appIcon = NSRunningApplication(processIdentifier: window.pid)?.icon
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        if window.isMinimized {
            // No live preview for a minimized window: show a dimmed app icon.
            thumbView.image = appIcon
            thumbView.imageScaling = .scaleProportionallyDown
            thumbView.alphaValue = 0.4
        }
        addSubview(thumbView)

        iconView.image = appIcon
        addSubview(iconView)

        titleLabel.stringValue = window.title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        switch style {
        case .card:
            // Thumbnail on top (centered), icon + title in the bottom strip.
            thumbView.frame = NSRect(x: (w - thumbW) / 2, y: h - p - thumbH,
                                     width: thumbW, height: thumbH)
            let strip: CGFloat = 30
            iconView.frame = NSRect(x: p, y: (strip - iconSize) / 2, width: iconSize, height: iconSize)
            let titleX = p + iconSize + 6
            titleLabel.frame = NSRect(x: titleX, y: (strip - 16) / 2, width: w - titleX - p, height: 16)

        case .row:
            // Same-sized thumbnail on the left, icon + title beside it.
            thumbView.frame = NSRect(x: p, y: (h - thumbH) / 2, width: thumbW, height: thumbH)
            let iconX = p + thumbW + 8
            iconView.frame = NSRect(x: iconX, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
            let titleX = iconX + iconSize + 6
            titleLabel.frame = NSRect(x: titleX, y: (h - 16) / 2, width: w - titleX - 28, height: 16)
        }

        closeButton.title = "✕"
        closeButton.font = .systemFont(ofSize: 11, weight: .bold)
        closeButton.isBordered = false
        closeButton.frame = NSRect(x: w - 24, y: h - 24, width: 20, height: 20)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor = selected
            ? NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = selected ? 2 : 0
        layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : nil
    }

    func setThumbnail(_ image: NSImage?) {
        // Ignore nil so a minimized window keeps its placeholder icon.
        if let image { thumbView.image = image }
    }

    @objc private func closeClicked() { onClose?() }

    override func mouseUp(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent)  { closeButton.isHidden = true }
}
