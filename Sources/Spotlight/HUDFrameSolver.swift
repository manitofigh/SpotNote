// swiftlint:disable function_parameter_count
import CoreGraphics

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
