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
    /// A resize animation posts `didResize` on every frame; one pending re-anchor is
    /// enough to correct all of them.
    private var isReanchorScheduled = false

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

        guard let reading = store.snapshot.menuBarReading(preferring: store.config.menuBarWindowID)
        else {
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = nil
            button.toolTip = "Toki — 사용량 읽는 중"
            return
        }

        let peak = reading.fraction
        let remaining = max(0, 1 - peak)
        button.toolTip = "Toki — \(providerName(for: reading.providerID)) 남은 여유 "
            + Display.percent(remaining)

        // The percentage next to the icon is optional; some people want the menu bar
        // to stay quiet until something is actually running low.
        guard store.config.showMenuBarPercent else {
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = tint(forPeak: peak)
            return
        }

        button.attributedTitle = menuBarTitle(
            remaining: remaining,
            symbol: providerSymbol(for: reading.providerID),
            colour: tint(forPeak: peak)
        )
        button.contentTintColor = tint(forPeak: peak)
    }

    /// `" 47% ✳"` — the percentage, then the provider's own symbol.
    ///
    /// The same SF Symbols the cards use, so the mark in the menu bar and the icon on the
    /// card are recognisably the same thing. A letter was tried first and read as noise at
    /// the size a menu bar allows; a glyph carries at 11pt where "C" did not.
    ///
    /// The colour is applied to the symbol explicitly. `contentTintColor` styles the
    /// button's own image but does not reach an image embedded in an attributed title,
    /// and a template image inside a text attachment does not pick up the text colour
    /// either — so the warning colour has to be baked into the symbol configuration.
    private func menuBarTitle(
        remaining: Double,
        symbol: String,
        colour: NSColor?
    ) -> NSAttributedString {
        let text = colour ?? .labelColor
        let title = NSMutableAttributedString(
            string: " \(Display.percent(remaining))",
            attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: text
            ]
        )

        guard !symbol.isEmpty,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                  .withSymbolConfiguration(
                      NSImage.SymbolConfiguration(
                          pointSize: Theme.menuBarMarkPointSize,
                          weight: .semibold
                      )
                      .applying(NSImage.SymbolConfiguration(hierarchicalColor: text))
                  )
        else { return title }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(
            x: 0,
            y: Theme.menuBarMarkBaselineOffset,
            width: image.size.width,
            height: image.size.height
        )

        title.append(NSAttributedString(string: " "))
        title.append(NSAttributedString(attachment: attachment))
        return title
    }

    /// Reuses each provider's card symbol rather than inventing a menu bar one, so the
    /// two places agree.
    private func providerSymbol(for providerID: String) -> String {
        switch providerID {
        case ClaudeUsageProvider.providerID: ClaudeUsageProvider.symbol
        case CodexUsageProvider.providerID: CodexUsageProvider.symbol
        default: ""
        }
    }

    private func providerName(for providerID: String) -> String {
        switch providerID {
        case ClaudeUsageProvider.providerID: ClaudeUsageProvider.displayName
        case CodexUsageProvider.providerID: CodexUsageProvider.displayName
        default: "사용량"
        }
    }

    /// `nil` keeps the default menu bar colour; a colour means the quota is tight.
    private func tint(forPeak peak: Double) -> NSColor? {
        // Same clamp as `Theme.barColor`: the warning point is user-set and the critical
        // one is not, so without this a low warning setting would show red before amber.
        let warningRemaining = store.config.warningRemainingFraction
        let remaining = 1 - peak
        if remaining <= min(Theme.criticalRemaining, warningRemaining) { return NSColor(Theme.ember) }
        if remaining <= warningRemaining { return NSColor(Theme.amber) }
        return nil
    }

    /// Re-arms itself on every change, which is the idiomatic way to bridge an
    /// `@Observable` model into AppKit.
    private func observeStore() {
        withObservationTracking {
            _ = store.snapshot
            // Tracked as well as the snapshot, because three menu bar settings — whether
            // the percentage is shown at all, which window it represents, and the warning
            // threshold that colours it — change nothing about the data. Without this the
            // button kept its old value until some later refresh happened to replace the
            // snapshot, so the setting looked like it had not applied.
            _ = store.config
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

        // Bumped before the first layout so the view returns to the dashboard while it is
        // still off screen, rather than showing settings for a frame and animating away.
        panelSession += 1
        hosting?.rootView = makeRootView()

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
    ///
    /// The move is deferred one runloop turn on purpose. `didResize` is posted while
    /// `NSView.layout` is still on the stack — the hosting view is being sized by the
    /// layout engine — so moving the window from here re-enters a display cycle that is
    /// already running. AppKit answers that by raising from
    /// `_postWindowNeedsUpdateConstraints`, which killed the app whenever the panel
    /// changed height, most reliably on the settings transition. Deferring keeps the
    /// correction and performs it once the cycle has finished.
    @objc private func panelDidResize(_ notification: Notification) {
        guard let panel, (notification.object as? NSWindow) === panel, panel.isVisible else { return }
        guard !isReanchorScheduled else { return }
        isReanchorScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isReanchorScheduled = false
            guard let panel = self.panel, panel.isVisible else { return }
            panel.anchor(below: self.statusItem.button)
        }
    }

    /// SwiftUI's intrinsic height is only known once measured, so ask the hosting
    /// controller directly instead of trusting `fittingSize` before layout — that
    /// returned zero height, producing an invisible window.
    private func resize(_ panel: GlassPanel) {
        guard let hosting else { return }
        let measured = hosting.sizeThatFits(
            in: CGSize(width: Theme.panelWidth, height: .greatestFiniteMagnitude)
        )
        panel.setContentSize(
            CGSize(width: Theme.panelWidth, height: usableHeight(measured.height, for: panel))
        )
    }

    /// A measured height is not automatically a legal window dimension.
    ///
    /// A SwiftUI view that accepts the size it is offered answers `sizeThatFits` with
    /// the proposal itself — `.greatestFiniteMagnitude` — and passing that to
    /// `setContentSize` makes AppKit raise `NSInternalInconsistencyException` and take
    /// the app down. Anything not finite, not positive, or taller than the screen is
    /// therefore treated as unusable rather than trusted.
    private func usableHeight(_ height: CGFloat, for panel: GlassPanel) -> CGFloat {
        guard height.isFinite, height > 1 else { return Theme.panelFallbackHeight }
        let screen = panel.screen ?? statusItem.button?.window?.screen ?? NSScreen.main
        guard let ceiling = screen?.visibleFrame.height else { return height }
        return min(height, ceiling)
    }

    /// Resizes the panel to the height SwiftUI just measured.
    ///
    /// Always asynchronous: the report arrives while SwiftUI is laying out, and resizing
    /// a window at that moment is exactly the re-entrancy that used to crash the app.
    /// One runloop turn later the cycle has finished and the resize is safe.
    private func applyContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 1 else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let target = self.usableHeight(height, for: panel)
            guard abs(panel.frame.height - target) > 0.5 else { return }

            panel.setContentSize(CGSize(width: Theme.panelWidth, height: target))
            panel.anchor(below: self.statusItem.button)
        }
    }

    /// Counts openings. The panel is built once and merely ordered out when dismissed, so
    /// SwiftUI keeps its `@State` — including which screen was showing. Handing the view a
    /// value that changes on every open gives it something to notice, so it can return to
    /// the dashboard rather than reopening on whatever screen it was left on.
    private var panelSession = 0

    private func makeRootView() -> WidgetView {
        WidgetView(
            store: store,
            panelSession: panelSession,
            onClose: { [weak self] in self?.hidePanel() },
            onQuit: { NSApp.terminate(nil) },
            onHeightChange: { [weak self] height in self?.applyContentHeight(height) }
        )
    }

    private func makePanel() -> GlassPanel {
        let controller = NSHostingController(rootView: makeRootView())
        // Deliberately *not* `.preferredContentSize`. That option routes every SwiftUI
        // size change through the Auto Layout engine, so the hosting view's frame is
        // updated from inside `NSView.layout` — and SwiftUI answers that frame change by
        // asking the window for another constraints pass, which AppKit refuses mid-cycle
        // by raising from `_postWindowNeedsUpdateConstraints`. The app died there on
        // every settings transition. The window is sized from `applyContentHeight`
        // instead, outside the layout pass.
        controller.sizingOptions = []
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
