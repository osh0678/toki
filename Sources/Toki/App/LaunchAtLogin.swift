import ServiceManagement

/// Registers Toki as a login item so it comes back after a reboot.
///
/// Deliberately not stored in `WidgetConfig`: the system owns this state, and the user
/// can flip it from 시스템 설정 → 일반 → 로그인 항목 without Toki knowing. A copy in the
/// config file would drift from that, so the toggle always reads the live status.
@MainActor
enum LaunchAtLogin {
    private static var service: SMAppService { .mainApp }

    /// Counts `.requiresApproval` as on: the registration exists and only the user's
    /// consent in System Settings is missing, so showing the switch off would invite a
    /// second registration that changes nothing.
    static var isEnabled: Bool {
        switch service.status {
        case .enabled, .requiresApproval: true
        default: false
        }
    }

    /// Set when the item is registered but macOS is still waiting for the user to
    /// allow it, so the settings pane can say where to go.
    static var needsApproval: Bool {
        service.status == .requiresApproval
    }

    /// Returns a user-facing error message on failure, `nil` on success — the same
    /// contract as `SettingsWriter.save`.
    static func setEnabled(_ isEnabled: Bool) -> String? {
        do {
            if isEnabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return nil
        } catch {
            // Most often seen when running the bare executable from `swift run`: only
            // an app bundle can be a login item.
            return "자동 실행 설정 실패: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
