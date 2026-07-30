import AppKit

/// Borderless glass panel that drops out of the menu bar item, popover-style.
///
/// Dismissal is driven by the panel losing key status, not by `hidesOnDeactivate`:
/// an accessory app is not guaranteed to activate on a status-item click, and with
/// `hidesOnDeactivate` enabled a failed activation hides the panel the instant it is
/// shown. Failing towards "visible" is the right direction for a widget.
final class GlassPanel: NSPanel {
    /// The panel must take key events so ⌘R / ⌘W work while it is open.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(hosting controller: NSViewController) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: 320),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        contentViewController = controller
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Above ordinary windows, like a menu — but below the menu bar itself.
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Centres the panel under the menu bar item, nudged back on screen when the
    /// item sits close to a display edge.
    func anchor(below button: NSStatusBarButton?, gap: CGFloat = 6) {
        guard let button, let barWindow = button.window else { return }

        let anchorRect = barWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: anchorRect.midX - frame.width / 2,
            y: anchorRect.minY - frame.height - gap
        )

        // On a multi-display setup each screen has its own menu bar, so the panel must
        // follow the screen that was actually clicked. `NSScreen.main` would drag it
        // back to the primary display, which is the dual-monitor bug this avoids.
        let screen = barWindow.screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main

        if let visible = screen?.visibleFrame {
            let margin: CGFloat = 8
            origin.x = min(max(visible.minX + margin, origin.x), visible.maxX - frame.width - margin)
            origin.y = max(visible.minY + margin, origin.y)
        }

        setFrameOrigin(origin)
    }
}
