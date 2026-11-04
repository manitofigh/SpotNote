// swiftlint:disable function_parameter_count
import CoreGraphics
import Foundation

/// Pure HUD-resize math, factored out of `SpotlightWindowController` so
/// the two anchoring policies (top-anchored at rest, bottom-pinned
/// while cycling notes through the navigation overlay) are
/// independently testable.
///
/// The HUD is a single `NSPanel` whose height changes whenever the
/// editor reflows, the navigation overlay appears/disappears, or the
/// tutorial bar toggles. We never want the editor card to "jump"
/// horizontally, but vertically the right anchor depends on context:
/// at rest the panel pivots around the editor's top edge, and during
/// note-cycling it pivots around the panel's bottom edge so the nav
/// overlay (which sits below the editor) stays nailed to the screen.
///
/// `resolveNewY` is the single source of truth for both. It returns
/// only the new origin Y; the caller owns the rest of the frame.
enum HUDFrameSolver {
  enum NavAnchor: Equatable {
    /// At rest. Panel grows downward from a fixed top edge.
    case none
    /// The nav overlay just became visible. The next resize stays
    /// top-anchored so the editor doesn't jump, then transitions to
    /// `.bottomPinned` so subsequent cycles keep the overlay still.
    case pendingFirstResize
    /// While cycling notes, the panel's bottom edge stays at `y` and
    /// the editor grows upward as content gets longer.
    case bottomPinned(y: CGFloat)
  }

  /// - Parameters:
  ///   - anchor: current anchoring policy.
  ///   - currentOriginY: panel's existing origin Y (used as a final
  ///     fallback when neither anchor cache is populated, e.g. during
  ///     the very first resize).
  ///   - currentHeight: panel's existing height -- needed for the
  ///     fallback path so the implied "panel top" is meaningful.
  ///   - newHeight: the height the panel is being resized TO.
  ///   - chromeAbove: pixels of chrome (find bar / tutorial bar) above
  ///     the editor card. Used to translate between panel origin and
  ///     "editor top".
  ///   - cachedEditorTopY: most recently captured screen-Y of the
  ///     editor card's top edge, or `nil` if not yet cached.
  ///   - pinnedTopY: panel's intended top edge at rest.
  /// - Returns: a tuple of (new origin Y, new editor-top to cache).
  ///   The caller writes both back into the controller's state.
  static func resolveNewY(
    anchor: NavAnchor,
    currentOriginY: CGFloat,
    currentHeight: CGFloat,
    newHeight: CGFloat,
    chromeAbove: CGFloat,
    cachedEditorTopY: CGFloat?,
    pinnedTopY: CGFloat?
  ) -> (newOriginY: CGFloat, editorTopY: CGFloat?) {
    // #lizard forgives
    switch anchor {
    case .bottomPinned(let bottomY):
      // Panel grows upward; editor-top cache is intentionally NOT
      // refreshed here, because the editor IS drifting upward by
      // design while we cycle.
      return (bottomY, cachedEditorTopY)
    case .pendingFirstResize, .none:
      let editorTop: CGFloat
      if let cached = cachedEditorTopY {
        editorTop = cached
      } else if let pinned = pinnedTopY {
        editorTop = pinned - chromeAbove
      } else {
        editorTop = (currentOriginY + currentHeight) - chromeAbove
      }
      let panelTop = editorTop + chromeAbove
      let newY = panelTop - newHeight
      return (newY, editorTop)
    }
  }
}

/// Persisted screen position for the HUD. The top edge is stored instead of
/// the origin Y so a note with a different height reopens at the same visual
/// location.
struct HUDPosition: Equatable {
  let originX: CGFloat
  let topY: CGFloat
}

enum HUDPositionStore {
  static let defaultsKey = "hud.position"

  static func load(from defaults: UserDefaults) -> HUDPosition? {
    guard let values = defaults.dictionary(forKey: defaultsKey),
      let originX = (values["originX"] as? NSNumber)?.doubleValue,
      let topY = (values["topY"] as? NSNumber)?.doubleValue
    else {
      return nil
    }
    return HUDPosition(originX: originX, topY: topY)
  }

  static func save(_ position: HUDPosition, to defaults: UserDefaults) {
    defaults.set(
      [
        "originX": Double(position.originX),
        "topY": Double(position.topY)
      ],
      forKey: defaultsKey
    )
  }

  static func frame(
    for position: HUDPosition,
    size: CGSize,
    in visibleFrame: CGRect
  ) -> CGRect {
    let maxOriginX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maxOriginY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
    let originX = min(max(position.originX, visibleFrame.minX), maxOriginX)
    let desiredOriginY = position.topY - size.height
    let originY = min(max(desiredOriginY, visibleFrame.minY), maxOriginY)
    return CGRect(
      x: originX,
      y: originY,
      width: size.width,
      height: size.height
    )
  }
}
