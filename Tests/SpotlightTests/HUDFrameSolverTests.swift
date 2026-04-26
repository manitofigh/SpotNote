import CoreGraphics
import Testing

@testable import Spotlight

@Suite("HUDFrameSolver -- anchoring policy for the resizing HUD panel")
struct HUDFrameSolverTests {
  // The user-reported bug: pressing ⌃N/⌃P to cycle through saved
  // notes shifted the bottom of the HUD up and down (the nav overlay
  // sits at the bottom of the panel). The required behavior is the
  // opposite: while the overlay is visible, the bottom edge stays
  // pinned and the editor grows UPWARD as the cycled note's content
  // gets longer. These tests lock that invariant in place.

  @Test("bottomPinned: panel origin Y equals the anchor regardless of new height -- bottom stays put")
  func bottomPinnedKeepsBottomEdge() {
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: .bottomPinned(y: 500),
      currentOriginY: 500,
      currentHeight: 240,
      newHeight: 360,  // longer note -> taller panel
      chromeAbove: 0,
      cachedEditorTopY: 740,
      pinnedTopY: 740
    )
    #expect(resolved.newOriginY == 500)
  }

  @Test("bottomPinned: shorter note shrinks the panel upward, bottom still anchored")
  func bottomPinnedShorterNote() {
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: .bottomPinned(y: 500),
      currentOriginY: 500,
      currentHeight: 360,
      newHeight: 200,
      chromeAbove: 0,
      cachedEditorTopY: 860,
      pinnedTopY: 860
    )
    #expect(resolved.newOriginY == 500)
  }

  @Test("bottomPinned: cached editor-top is NOT mutated -- the editor IS allowed to drift while cycling")
  func bottomPinnedDoesNotRefreshEditorTop() {
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: .bottomPinned(y: 400),
      currentOriginY: 400,
      currentHeight: 240,
      newHeight: 360,
      chromeAbove: 30,
      cachedEditorTopY: 600,
      pinnedTopY: 700
    )
    #expect(resolved.editorTopY == 600)
  }

  @Test("rest: editor-top stays in place across resizes -- only the bottom edge moves")
  func restAnchorsEditorTop() {
    let chromeAbove: CGFloat = 24
    let editorTop: CGFloat = 700
    let firstResize = HUDFrameSolver.resolveNewY(
      anchor: .none,
      currentOriginY: 500,
      currentHeight: 200,
      newHeight: 240,
      chromeAbove: chromeAbove,
      cachedEditorTopY: editorTop,
      pinnedTopY: nil
    )
    // editor-top is editorTop=700; panel-top = 700+24 = 724; new origin = 724-240 = 484.
    #expect(firstResize.newOriginY == 484)
    #expect(firstResize.editorTopY == 700)

    let secondResize = HUDFrameSolver.resolveNewY(
      anchor: .none,
      currentOriginY: 484,
      currentHeight: 240,
      newHeight: 300,
      chromeAbove: chromeAbove,
      cachedEditorTopY: firstResize.editorTopY,
      pinnedTopY: nil
    )
    // editor-top still 700; new origin = 724-300 = 424.
    #expect(secondResize.newOriginY == 424)
    #expect(secondResize.editorTopY == 700)
  }

  @Test("rest: with no editor-top cache, derive it from pinnedTopY")
  func restDerivesEditorTopFromPinned() {
    let resolved = HUDFrameSolver.resolveNewY(
      anchor: .none,
      currentOriginY: 0,
      currentHeight: 0,
      newHeight: 200,
      chromeAbove: 24,
      cachedEditorTopY: nil,
      pinnedTopY: 800
    )
    // editor-top = pinned 800 - chrome 24 = 776; panel-top = 800; origin = 800-200 = 600.
    #expect(resolved.editorTopY == 776)
    #expect(resolved.newOriginY == 600)
  }

  @Test("pendingFirstResize: behaves like .none so the first resize after opening the overlay does not jump")
  func pendingFirstResizeBehavesLikeNone() {
    let asNone = HUDFrameSolver.resolveNewY(
      anchor: .none,
      currentOriginY: 500,
      currentHeight: 200,
      newHeight: 280,
      chromeAbove: 16,
      cachedEditorTopY: 716,
      pinnedTopY: nil
    )
    let asPending = HUDFrameSolver.resolveNewY(
      anchor: .pendingFirstResize,
      currentOriginY: 500,
      currentHeight: 200,
      newHeight: 280,
      chromeAbove: 16,
      cachedEditorTopY: 716,
      pinnedTopY: nil
    )
    #expect(asNone.newOriginY == asPending.newOriginY)
    #expect(asNone.editorTopY == asPending.editorTopY)
  }

  /// **Bug reproducer** -- the symptom the user reported: "going through
  /// older chats with ctrl+n/p, the note content shifts the bottom
  /// sheet that contains the list". A bottom-pinned anchor must NOT
  /// produce different origin Ys for two different new heights.
  @Test("regression: bottom edge does not shift between two notes with different line counts")
  func bottomEdgeStableAcrossNoteCycle() {
    let bottom: CGFloat = 320
    let shortNote = HUDFrameSolver.resolveNewY(
      anchor: .bottomPinned(y: bottom),
      currentOriginY: bottom,
      currentHeight: 200,
      newHeight: 200,
      chromeAbove: 24,
      cachedEditorTopY: 544,
      pinnedTopY: 544
    )
    let longNote = HUDFrameSolver.resolveNewY(
      anchor: .bottomPinned(y: bottom),
      currentOriginY: bottom,
      currentHeight: 200,
      newHeight: 420,
      chromeAbove: 24,
      cachedEditorTopY: 544,
      pinnedTopY: 544
    )
    // Both panels share the same bottom edge -- that's the entire
    // point. The top edge differs: long note's top is higher.
    #expect(shortNote.newOriginY == longNote.newOriginY)
    #expect(shortNote.newOriginY == bottom)
    #expect(shortNote.newOriginY + 200 == longNote.newOriginY + 420 - 220)
  }
}
