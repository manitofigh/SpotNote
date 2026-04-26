import Foundation

extension Bundle {
  /// The Spotlight module's resources bundle (fonts, SVG icons).
  ///
  /// Under SPM, `Bundle.module` is auto-generated per target and
  /// contains the resources declared in `Package.swift`. Under a
  /// vanilla Xcode project, resources live in the framework bundle
  /// itself -- `Bundle(for:)` resolves it.
  public static var spotlightResources: Bundle {
    #if SWIFT_PACKAGE
    return .module
    #else
    return Bundle(for: _SpotlightBundleAnchor.self)
    #endif
  }
}

// periphery:ignore - referenced inside the `#else` branch of
// `Bundle.spotlightResources` (non-SPM Xcode builds), which periphery
// can't see when scanning an SPM build.
/// Anchor class used by `Bundle(for:)` in non-SPM builds to locate the
/// Spotlight framework bundle that contains the copied resources.
private final class _SpotlightBundleAnchor {}
