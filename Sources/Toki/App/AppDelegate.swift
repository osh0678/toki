import AppKit
import SwiftUI

/// Wires the store to the menu bar item. Toki has no Dock icon and no windows
/// beyond the panel the menu bar item toggles, and it persists nothing on disk.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var statusItem: StatusItemController?

    /// Set `TOKI_DEBUG_OPEN_PANEL=1` to have the panel appear at launch. Used to
    /// verify panel geometry without simulating a menu bar click.
    private static let debugOpenPanelVariable = "TOKI_DEBUG_OPEN_PANEL"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(store: store)
        statusItem = controller
        store.start()

        if ProcessInfo.processInfo.environment[Self.debugOpenPanelVariable] == "1" {
            // Deferred: the status item has no window until the run loop has turned,
            // and without it the panel cannot be anchored under the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                controller.presentPanel()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
