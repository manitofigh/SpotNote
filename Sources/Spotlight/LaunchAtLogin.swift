import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` so the rest of the app can
/// treat "launch at login" as a `Bool`. The service itself persists state
/// across reboots, so we don't shadow it in `UserDefaults`.
public enum LaunchAtLogin {
  public static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Register or unregister the main app as a login item. Returns `true`
  /// when the requested state matches the post-call status. Failures are
  /// expected in unsigned dev builds and when the user has revoked the
  /// item from System Settings; callers fall back to the current status.
  @discardableResult
  public static func setEnabled(_ enabled: Bool) -> Bool {
    let service = SMAppService.mainApp
    do {
      if enabled {
        try service.register()
      } else if service.status != .notRegistered {
        try service.unregister()
      }
    } catch {
      return false
    }
    return (service.status == .enabled) == enabled
  }
}
