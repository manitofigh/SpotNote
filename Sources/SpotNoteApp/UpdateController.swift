import AppKit
import Sparkle

/// Wraps `SPUStandardUpdaterController` so the rest of the app can
/// trigger update checks via a stable `@MainActor` API. The
/// `SUFeedURL` and `SUPublicEDKey` are read from Info.plist (set by
/// project.yml).
@MainActor
final class UpdateController: NSObject {
  static let shared = UpdateController()

  private let controller: SPUStandardUpdaterController

  override private init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    super.init()
  }

  // periphery:ignore - exposed so future code paths (custom updater UI,
  // background scheduler) can reach Sparkle's underlying `SPUUpdater`
  // without re-wrapping.
  var updater: SPUUpdater { controller.updater }

  @objc func checkForUpdates(_ sender: Any?) {
    controller.checkForUpdates(sender)
  }
}
