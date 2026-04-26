import AppKit
import SwiftUI

/// Cross-cutting "did-copy" signal so the keyboard shortcut and the
/// in-editor button can share the same animation. Bumps `feedbackTick`
/// after each successful copy; views listen via `onChange` and play a
/// brief checkmark/scale flash.
@MainActor
final class CopyController: ObservableObject {
  @Published private(set) var feedbackTick: Int = 0

  /// Writes `text` to the general pasteboard (no-op when empty) and
  /// triggers the visual feedback. Caller decides whether to copy the
  /// full note or just a selection -- see
  /// `SpotlightWindowController.dispatch` and `CopyButton.action`.
  func copy(_ text: String) {
    guard !text.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    feedbackTick &+= 1
  }
}

/// Small floating button anchored at the top-right of the editor card.
/// Tapping copies the whole note via `action`; both the tap and the
/// keyboard shortcut path animate the same checkmark feedback.
struct CopyButton: View {
  @ObservedObject var controller: CopyController
  let theme: Theme
  let action: () -> Void

  @State private var showCheck = false
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      ZStack {
        Image(systemName: "doc.on.doc")
          .opacity(showCheck ? 0 : 1)
        Image(systemName: "checkmark")
          .opacity(showCheck ? 1 : 0)
          .foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.45))
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(theme.text.opacity(isHovering ? 0.85 : 0.55))
      .scaleEffect(showCheck ? 1.18 : 1.0)
      .frame(width: 24, height: 24)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isHovering ? theme.text.opacity(0.08) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .help("Copy note (⌘C)")
    .onChange(of: controller.feedbackTick) { _, _ in
      withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
        showCheck = true
      }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(750))
        withAnimation(.easeOut(duration: 0.18)) {
          showCheck = false
        }
      }
    }
  }
}
