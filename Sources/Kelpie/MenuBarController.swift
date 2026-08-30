import AppKit
import KelpieCore

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 320)

        render(segments: MenuBarModel.segments(
            counts: StatusCounts(blocked: 0, working: 0, done: 0, idle: 0, unknown: 0),
            tick: 0,
            reduceMotion: false
        ))
    }

    func render(segments: [MenuBarSegment]) {
        guard let button = statusItem?.button else { return }
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
        button.attributedTitle = title
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
