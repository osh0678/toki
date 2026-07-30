import AppKit
import Observation
import SwiftUI

/// Owns the menu bar item and the popover-style panel it toggles.
///
/// Left click toggles the panel, right click opens a small menu. The panel hides
/// itself as soon as the app is deactivated, which gives popover dismissal without
/// installing any global event monitor.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private var panel: GlassPanel?
    private var hosting: NSHostingController<WidgetView>?
    /// Mouse-down on the status item makes the open panel resign key, which hides it
    /// before the click action fires. Remembering when that happened lets a second
    /// click read as "close" instead of instantly reopening.
    private var lastHiddenAt: Date?
    private var shownAt: Date?
    private var outsideClickMonitor: Any?

    /// Ignore dismissal signals briefly after opening, so the activation that happens
    /// while the panel appears cannot immediately close it again.
    private static let dismissGrace: TimeInterval = 0.4

    init(store: UsageStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureButton()
        observeStore()
        updateButton()
    }

    // MARK: - Menu bar button

    private func configureButton() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: "hare.fill",
            accessibilityDescription: "Toki — Claude / Codex 사용량"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Shows the worst window across both providers, so the menu bar alone answers
    /// "am I about to run out?".
    private func updateButton() {
        guard let button = statusItem.button else { return }

        guard let peak = store.snapshot.peakFraction else {
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "Toki — 사용량 읽는 중"
            return
        }

        let remaining = max(0, 1 - peak)
        button.toolTip = "Toki — 남은 여유 \(Display.percent(remaining))"

        // The percentage next to the icon is optional; some people want the menu bar
        // to stay quiet until something is actually running low.
        guard store.config.showMenuBarPercent else {
            button.title = ""
            button.contentTintColor = tint(forPeak: peak)
            return
        }

        button.title = " \(Display.percent(remaining))"
        button.contentTintColor = tint(forPeak: peak)
    }

    /// `nil` keeps the default menu bar colour; a colour means the quota is tight.
    private func tint(forPeak peak: Double) -> NSColor? {
        if peak >= Theme.criticalThreshold { return NSColor(Theme.ember) }
        if peak >= Theme.warningThreshold { return NSColor(Theme.amber) }
        return nil
    }

    /// Re-arms itself on every change, which is the idiomatic way to bridge an
    /// `@Observable` model into AppKit.
    private func observeStore() {
        withObservationTracking {
            _ = store.snapshot
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateButton()
                self?.observeStore()
            }
        }
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "새로고침", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Toki 종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Attaching the menu and re-clicking keeps it anchored to the status item;
        // detaching afterwards restores plain left-click toggling.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() {
        // Explicit user action, so bypass the official-usage throttle.
        store.refresh(force: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Panel

    private func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
            return
        }
        if let lastHiddenAt, Date().timeIntervalSince(lastHiddenAt) < 0.3 {
            return
        }
        showPanel()
    }

    /// Opens the panel without a click. Used by the launch-time debug hook and by
    /// anything that needs to surface the widget programmatically.
    func presentPanel() {
        showPanel()
    }

    private func showPanel() {
        let shown = panel ?? makePanel()
        panel = shown

        resize(shown)
        shown.anchor(below: statusItem.button)

        // An accessory app is not guaranteed to activate from a status-item click, so
        // order front unconditionally and only then try to take key status. Worst case
        // the panel is visible but not key — far better than invisible.
        // Activation is requested but not relied on: this accessory app was measured
        // failing to become active even with the forcing APIs, so the panel is ordered
        // front unconditionally. Dismissal therefore cannot depend on key status —
        // that is what the click monitor is for.
        NSApp.activate()
        shown.orderFrontRegardless()
        statusItem.button?.highlight(true)
        shownAt = Date()
        startOutsideClickMonitor()

        logPanelState(shown)
        store.refreshIfStale()
    }

    private func hidePanel() {
        stopOutsideClickMonitor()
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        lastHiddenAt = Date()
        shownAt = nil
    }

    private var isWithinDismissGrace: Bool {
        guard let shownAt else { return false }
        return Date().timeIntervalSince(shownAt) < Self.dismissGrace
    }

    /// Closes the panel when a click lands anywhere else.
    ///
    /// A global monitor receives only events delivered to *other* applications, so a
    /// hit here already means "outside Toki" — no window coordinates are inspected.
    /// Only mouse-down is watched (never keystrokes), the event value itself is
    /// discarded, and the monitor exists only while the panel is on screen. Mouse
    /// monitoring requires no accessibility or input-monitoring permission.
    ///
    /// This replaces dismissing on `didResignKey`: an accessory app is not guaranteed
    /// to take key status at all, so that signal never arrived and the panel stayed up.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // Event monitors are delivered on the main thread.
            MainActor.assumeIsolated {
                guard let self, !self.isWithinDismissGrace else { return }
                self.hidePanel()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    // Escape-to-close is deliberately absent. It would need the panel to be the key
    // window, and this accessory app was measured never becoming active — so neither a
    // local key monitor nor `cancelOperation` is ever reached. The alternative, a
    // global keyboard monitor, would observe every keystroke on the machine and needs
    // input-monitoring permission, which is not a trade worth making for one shortcut.

    /// Diagnostics for `TOKI_DEBUG_OPEN_PANEL=1`: without this, a panel that fails to
    /// appear gives nothing to go on from the outside.
    private func logPanelState(_ panel: GlassPanel) {
        guard ProcessInfo.processInfo.environment["TOKI_DEBUG_OPEN_PANEL"] == "1" else { return }

        let measured = hosting?.sizeThatFits(
            in: CGSize(width: Theme.panelWidth, height: .greatestFiniteMagnitude)
        ) ?? .zero

        // stderr, because redirected stdout is block-buffered and would show nothing
        // until the process exits.
        let lines = [
            "measured=\(measured)",
            "frame=\(panel.frame) visible=\(panel.isVisible) key=\(panel.isKeyWindow)",
            "level=\(panel.level.rawValue) alpha=\(panel.alphaValue)",
            "panelScreen=\(panel.screen?.frame.debugDescription ?? "nil")",
            "statusButtonWindow=\(statusItem.button?.window?.frame.debugDescription ?? "nil")",
            "appActive=\(NSApp.isActive)"
        ]
        for line in lines { fputs("[toki] \(line)\n", stderr) }
    }

    @objc private func panelDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, !isWithinDismissGrace else { return }
        hidePanel()
    }

    /// Covers ⌘Tab and Mission Control, which the click monitor cannot see.
    @objc private func appDidResignActive() {
        guard let panel, panel.isVisible, !isWithinDismissGrace else { return }
        hidePanel()
    }

    /// The panel opens showing only a loading row and grows once data arrives. Without
    /// re-anchoring, that growth moves the content off the top of the screen — which
    /// looks exactly like "the panel opens but shows nothing".
    @objc private func panelDidResize(_ notification: Notification) {
        guard let panel, (notification.object as? NSWindow) === panel, panel.isVisible else { return }
        panel.anchor(below: statusItem.button)
    }

    /// SwiftUI's intrinsic height is only known once measured, so ask the hosting
    /// controller directly instead of trusting `fittingSize` before layout — that
    /// returned zero height, producing an invisible window.
    private func resize(_ panel: GlassPanel) {
        guard let hosting else { return }
        let measured = hosting.sizeThatFits(
            in: CGSize(width: Theme.panelWidth, height: .greatestFiniteMagnitude)
        )
        let height = measured.height > 1 ? measured.height : Theme.panelFallbackHeight
        panel.setContentSize(CGSize(width: Theme.panelWidth, height: height))
    }

    private func makePanel() -> GlassPanel {
        let controller = NSHostingController(
            rootView: WidgetView(
                store: store,
                onClose: { [weak self] in self?.hidePanel() },
                onQuit: { NSApp.terminate(nil) }
            )
        )
        controller.sizingOptions = [.preferredContentSize]
        hosting = controller

        let panel = GlassPanel(hosting: controller)
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        center.addObserver(
            self,
            selector: #selector(panelDidResize),
            name: NSWindow.didResizeNotification,
            object: panel
        )
        center.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
        return panel
    }
}
