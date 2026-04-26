import AppKit

public enum DockIconStyle: String, CaseIterable, Identifiable, Sendable {
  case dark
  case light

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .dark: return "Dark"
    case .light: return "Light"
    }
  }

  var resourceName: String {
    switch self {
    case .dark: return "SpotNote-Icon-Dark"
    case .light: return "SpotNote-Icon-Light"
    }
  }
}

@MainActor
public enum DockIconSwitcher {
  public static func apply(_ style: DockIconStyle) {
    let bundle = Bundle.spotlightResources
    guard let url = bundle.url(forResource: style.resourceName, withExtension: "png"),
      let source = NSImage(contentsOf: url)
    else { return }
    NSApplication.shared.applicationIconImage = paddedDockIcon(from: source)
  }

  private static func paddedDockIcon(
    from image: NSImage,
    canvasSize: NSSize = NSSize(width: 1024, height: 1024),
    inset: CGFloat = -96
  ) -> NSImage {
    let rect = NSRect(origin: .zero, size: canvasSize)
    let tileRect = rect.insetBy(dx: inset, dy: inset)
    let padded = NSImage(size: canvasSize)
    padded.lockFocus()
    NSColor.clear.setFill()
    rect.fill()
    image.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    padded.unlockFocus()
    return padded
  }

  public static func applyVisibility(_ showInDock: Bool) {
    let desired: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
    guard NSApplication.shared.activationPolicy() != desired else { return }
    NSApplication.shared.setActivationPolicy(desired)
  }
}
