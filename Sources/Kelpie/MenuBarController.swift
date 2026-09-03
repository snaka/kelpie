import AppKit
import KelpieCore

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    /// A template image, not text: macOS composites template images against
    /// whatever is behind the menu bar, so the resting state stays legible
    /// over colourful wallpapers where a dim text glyph disappeared.
    /// `dog.fill` needs macOS 14.4's SF Symbols; older point releases of
    /// Sonoma fall back to the paw print.
    private static let restingIcon: NSImage? = {
        let image = NSImage(systemSymbolName: "dog.fill", accessibilityDescription: "Kelpie")
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Kelpie")
        image?.isTemplate = true
        return image
    }()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 320)

        render(.resting)
    }

    func render(_ content: MenuBarContent) {
        guard let button = statusItem?.button else { return }
        switch content {
        case .resting:
            button.image = Self.restingIcon
            button.attributedTitle = NSAttributedString()
        case .segments(let segments):
            button.image = nil
            button.attributedTitle = title(for: segments)
        }
    }

    private func title(for segments: [MenuBarSegment]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        // Monospaced digits stop the item from resizing as counts cross 9→10,
        // which would nudge every menu bar icon to its left.
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small),
            weight: .regular
        )
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: " "))
            }
            title.append(NSAttributedString(
                string: segment.text,
                attributes: [
                    .font: font,
                    .foregroundColor: MenuBarPalette.color(for: segment.role),
                ]
            ))
        }
        return title
    }

    func setPopoverContent(_ viewController: NSViewController) {
        popover.contentViewController = viewController
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
