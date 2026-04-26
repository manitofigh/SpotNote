// swiftlint:disable file_length function_body_length identifier_name
// swiftlint:disable multiple_closures_with_trailing_closure
import AppKit
import Combine
import SwiftUI

/// First-run interactive tutorial. Walks the user through five chords
/// (summon, new note, browse older, fuzzy jump, settings). Each cap
/// reacts independently as its key is held; the step advances only
/// when every key in the chord is held at once. The global toggle
/// chord is intercepted by `AppDelegate` while `isActive == true` so
/// the HUD does not summon underneath the tutorial.
@MainActor
public final class OnboardingController: NSObject, NSWindowDelegate {
  public static let completedDefaultsKey = "onboarding.completed.v1"

  private static let windowSize = CGSize(width: 760, height: 440)

  private var window: NSWindow?
  private let theme: Theme
  private let shortcuts: ShortcutStore
  private let onFinished: (_ completed: Bool) -> Void
  private var hostedModel: OnboardingModel?

  public var isActive: Bool { window?.isVisible == true }

  public init(
    theme: Theme,
    shortcuts: ShortcutStore,
    onFinished: @escaping (_ completed: Bool) -> Void
  ) {
    self.theme = theme
    self.shortcuts = shortcuts
    self.onFinished = onFinished
  }

  public static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
    !defaults.bool(forKey: completedDefaultsKey)
  }

  public static func markCompleted(defaults: UserDefaults = .standard) {
    // #lizard forgives
    defaults.set(true, forKey: completedDefaultsKey)
  }

  public func show() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let model = OnboardingModel(shortcuts: shortcuts) { [weak self] completed in
      self?.finish(completed: completed)
    }
    hostedModel = model

    let view = OnboardingView(theme: theme, model: model)
    let hosting = NSHostingController(rootView: view)
    hosting.view.frame = NSRect(origin: .zero, size: Self.windowSize)

    let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Self.windowSize),
      styleMask: style,
      backing: .buffered,
      defer: false
    )
    window.contentViewController = hosting
    window.setContentSize(Self.windowSize)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.isMovable = true
    window.isMovableByWindowBackground = true
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self

    if let screen = NSScreen.main ?? NSScreen.screens.first {
      let v = screen.visibleFrame
      let origin = CGPoint(
        x: v.midX - Self.windowSize.width / 2,
        y: v.midY - Self.windowSize.height / 2
      )
      window.setFrame(NSRect(origin: origin, size: Self.windowSize), display: true)
    }
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// Called by `AppDelegate` when the global toggle hotkey fires while
  /// the tutorial is up. The Carbon hotkey path doesn't deliver
  /// `keyDown`/`keyUp` to the AppKit responder chain, so simulate a
  /// brief held state on the relevant caps so the press animation
  /// still runs visibly.
  public func handleGlobalToggleChord() {
    hostedModel?.simulateGlobalChordPress()
  }

  private func finish(completed: Bool) {
    Self.markCompleted()
    let win = window
    window = nil
    hostedModel = nil
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.55
      ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      win?.animator().alphaValue = 0
    })
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [onFinished] in
      win?.orderOut(nil)
      onFinished(completed)
    }
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    finish(completed: false)
    return false
  }

  public func windowDidResignKey(_ notification: Notification) {
    guard !(hostedModel?.dismissing ?? true),
      window?.isMiniaturized != true
    else { return }
    window?.makeKeyAndOrderFront(nil)
  }
}

// MARK: - Model

@MainActor
final class OnboardingModel: ObservableObject {
  struct Step: Identifiable {
    let id: Int
    let action: ShortcutAction
    let title: String
    let subtitle: String
  }

  @Published private(set) var stepIndex: Int = 0
  @Published private(set) var showingSplash: Bool = true
  /// Tokens currently considered "held" -- both real (driven by
  /// `flagsChanged` / `keyDown`) and simulated (the global hotkey
  /// path). Tokens use the same vocabulary as `KeyCap.split`:
  /// "⌘", "⇧", "⌃", "⌥", "Space", "N", ",", etc.
  @Published private(set) var heldTokens: Set<String> = []
  @Published var dismissing: Bool = false

  let steps: [Step] = [
    Step(
      id: 0,
      action: .toggleHotkey,
      title: "Summon SpotNote from anywhere",
      subtitle: "Press the chord to summon the heads-up display (HUD)."
    ),
    Step(
      id: 1,
      action: .newChat,
      title: "Start a new note",
      subtitle: "A blank canvas, no titles, no files."
    ),
    Step(
      id: 2,
      action: .olderChat,
      title: "Step back through past notes",
      subtitle: "Hold to scroll. Pair with ⌃P to step forward."
    ),
    Step(
      id: 3,
      action: .fuzzyFindAll,
      title: "Jump to any note",
      subtitle: "Type a few characters from anywhere in the note."
    ),
    Step(
      id: 4,
      action: .commandPalette,
      title: "Search commands",
      subtitle: "Find any action or shortcut from one place."
    ),
    Step(
      id: 5,
      action: .openSettings,
      title: "Tweak everything",
      subtitle: "Themes, shortcuts, updates, all live in Settings."
    )
  ]

  private let shortcuts: ShortcutStore
  private let onComplete: (_ completed: Bool) -> Void
  private var advanceLocked = false

  init(
    shortcuts: ShortcutStore,
    onComplete: @escaping (_ completed: Bool) -> Void
  ) {
    self.shortcuts = shortcuts
    self.onComplete = onComplete
  }

  var current: Step { steps[stepIndex] }
  var isLast: Bool { stepIndex == steps.count - 1 }

  var requiredTokens: [String] {
    KeyCap.split(chord: shortcuts.binding(for: current.action).displayString)
  }

  func updateModifiers(_ flags: NSEvent.ModifierFlags) {
    let masked = flags.intersection(.deviceIndependentFlagsMask)
    var next = heldTokens.subtracting(["⌘", "⇧", "⌃", "⌥"])
    if masked.contains(.command) { next.insert("⌘") }
    if masked.contains(.shift) { next.insert("⇧") }
    if masked.contains(.control) { next.insert("⌃") }
    if masked.contains(.option) { next.insert("⌥") }
    setHeld(next)
  }

  func setMainKeyDown(_ token: String) {
    var next = heldTokens
    next.insert(token)
    setHeld(next)
  }

  func setMainKeyUp(_ token: String) {
    var next = heldTokens
    next.remove(token)
    setHeld(next)
  }

  /// Briefly flashes every required token down -> up so the press
  /// animation runs even when AppKit didn't see the keystrokes
  /// (Carbon `RegisterEventHotKey` path).
  func simulateGlobalChordPress() {
    guard !advanceLocked else { return }
    let tokens = requiredTokens
    setHeld(Set(tokens))
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
      self?.setHeld([])
    }
  }

  private func setHeld(_ next: Set<String>) {
    guard next != heldTokens else { return }
    heldTokens = next
    let required = Set(requiredTokens)
    if !advanceLocked, required.isSubset(of: heldTokens), !required.isEmpty {
      advanceLocked = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
        self?.advance()
      }
    }
  }

  /// Returns the display token of the current chord's *main* (non-
  /// modifier) key when `key` matches it, regardless of which
  /// modifiers are currently held. This is what makes each cap react
  /// independently -- the Space cap glows the moment Space is pressed,
  /// even before the user adds ⌘ or ⇧.
  func mainTokenIfKeyMatches(_ key: String) -> String? {
    let binding = shortcuts.binding(for: current.action)
    return binding.key == key ? Shortcut.displayKey(binding.key) : nil
  }

  func advance() {
    if isLast {
      complete(completed: true)
    } else {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
        stepIndex += 1
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        self?.advanceLocked = false
      }
    }
  }

  func skip() { complete(completed: false) }

  private func complete(completed: Bool = true) {
    guard !dismissing else { return }
    dismissing = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.onComplete(completed)
    }
  }

  func dismissSplash() {
    withAnimation(.easeInOut(duration: 0.8)) {
      showingSplash = false
    }
  }

}

// MARK: - Root view

struct OnboardingView: View {
  let theme: Theme
  @ObservedObject var model: OnboardingModel
  @State private var closeHovered = false
  @State private var minimizeHovered = false

  var body: some View {
    ZStack {
      AuroraBackground()
        .ignoresSafeArea()

      if model.showingSplash {
        SplashView()
          .transition(.opacity)
      } else {
        VStack(spacing: 0) {
          topBar
            .padding(.bottom, 6)
          Spacer(minLength: 0)
          keycaps
            .padding(.vertical, 4)
          Spacer(minLength: 14)
          copy
          Spacer(minLength: 0)
          bottomBar
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .transition(.opacity)
      }
    }
    .frame(width: 760, height: 440)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
    )
    .opacity(model.dismissing ? 0 : 1)
    .scaleEffect(model.dismissing ? 0.97 : 1)
    .background(KeyMonitor(model: model))
    .onAppear {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
        model.dismissSplash()
      }
    }
  }

  private var topBar: some View {
    HStack(spacing: 8) {
      Button(action: { model.skip() }) {
        ZStack {
          Circle()
            .fill(
              closeHovered
                ? Color(red: 1.0, green: 0.27, blue: 0.23) : Color.white.opacity(0.12)
            )
            .frame(width: 13, height: 13)
          if closeHovered {
            Image(systemName: "xmark")
              .font(.system(size: 7.5, weight: .bold))
              .foregroundStyle(Color(white: 0.15))
          }
        }
      }
      .buttonStyle(.plain)
      .onHover { closeHovered = $0 }
      Button(action: { NSApp.keyWindow?.miniaturize(nil) }) {
        ZStack {
          Circle()
            .fill(
              minimizeHovered
                ? Color(red: 1.0, green: 0.74, blue: 0.18) : Color.white.opacity(0.12)
            )
            .frame(width: 13, height: 13)
          if minimizeHovered {
            Image(systemName: "minus")
              .font(.system(size: 9, weight: .heavy))
              .foregroundStyle(Color(white: 0.15))
          }
        }
      }
      .buttonStyle(.plain)
      .onHover { minimizeHovered = $0 }
      Spacer()
      Text("SpotNote · Tutorial")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Color.white.opacity(0.4))
      Spacer()
      Color.clear.frame(width: 34, height: 13)
    }
  }

  private var keycaps: some View {
    let tokens = model.requiredTokens
    return HStack(spacing: 14) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { idx, key in
        if idx > 0 {
          Text("+")
            .font(.system(size: 22, weight: .light, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.32))
        }
        TiltedKeyCap(label: key, isPressed: model.heldTokens.contains(key))
      }
    }
    .id(model.stepIndex)
    .transition(
      .asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.92)),
        removal: .opacity.combined(with: .scale(scale: 1.05))
      )
    )
  }

  private var copy: some View {
    VStack(spacing: 8) {
      Text(model.current.title)
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
      subtitleView
      HStack(spacing: 5) {
        Circle()
          .fill(Color(red: 0.35, green: 0.56, blue: 1.0))
          .frame(width: 5, height: 5)
        Text("Press all keys together to continue")
          .font(.system(size: 11, weight: .medium))
        Image(systemName: "arrow.right")
          .font(.system(size: 9, weight: .semibold))
      }
      .foregroundStyle(Color.white.opacity(0.7))
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      )
      .padding(.top, 6)
    }
    .id("text-\(model.stepIndex)")
    .transition(.opacity.combined(with: .offset(y: 8)))
  }

  @ViewBuilder
  private var subtitleView: some View {
    if model.current.action == .olderChat {
      HStack(spacing: 4) {
        Text("Hold to scroll. Pair with")
        inlineChordBadge("⌃P")
        Text("to step forward.")
      }
      .font(.system(size: 13))
      .foregroundStyle(Color.white.opacity(0.55))
    } else {
      Text(model.current.subtitle)
        .font(.system(size: 13))
        .foregroundStyle(Color.white.opacity(0.55))
        .multilineTextAlignment(.center)
    }
  }

  private func inlineChordBadge(_ chord: String) -> some View {
    HStack(spacing: 2) {
      ForEach(Array(KeyCap.split(chord: chord).enumerated()), id: \.offset) { _, key in
        Text(key)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.9))
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(Color.white.opacity(0.12))
          )
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
          )
      }
    }
  }

  private var bottomBar: some View {
    ZStack {
      HStack(spacing: 8) {
        ForEach(0..<model.steps.count, id: \.self) { idx in
          Capsule()
            .fill(idx == model.stepIndex ? Color.white.opacity(0.85) : Color.white.opacity(0.18))
            .frame(width: idx == model.stepIndex ? 18 : 6, height: 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: model.stepIndex)
        }
      }
      HStack {
        Spacer()
        Button(action: { model.skip() }) {
          Text("Skip")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
              Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Splash

private struct SplashView: View {
  @State private var appeared = false
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.white)
        .frame(width: 260, height: 260)
        .blur(radius: 70)
        .opacity(appeared ? 0.14 : 0)

      iconImage
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 1.2)) {
        appeared = true
      }
    }
  }

  private var iconImage: some View {
    let loaded = Bundle.spotlightResources
      .url(forResource: "SpotNote-Icon-Dark", withExtension: "png")
      .flatMap { NSImage(contentsOf: $0) }
    return Group {
      if let img = loaded {
        Image(nsImage: img)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 200, height: 200)
      }
    }
  }
}

// MARK: - Aurora background

private struct AuroraBackground: View {
  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      ZStack {
        LinearGradient(
          colors: [
            Color(red: 0.06, green: 0.06, blue: 0.07),
            Color(red: 0.09, green: 0.09, blue: 0.10)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        // Subtle vignette so edges read calmer than the center.
        RadialGradient(
          colors: [.clear, .black.opacity(0.45)],
          center: .center,
          startRadius: max(w, h) * 0.35,
          endRadius: max(w, h) * 0.85
        )
        .blendMode(.multiply)

        // Procedural grain -- faint, animated, no asset required.
        TimelineView(.periodic(from: .now, by: 0.08)) { context in
          Canvas { ctx, size in
            let seed = Int(context.date.timeIntervalSinceReferenceDate * 12)
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(seed)))
            let count = 320
            for _ in 0..<count {
              let x = rng.nextDouble() * size.width
              let y = rng.nextDouble() * size.height
              let a = 0.04 + rng.nextDouble() * 0.08
              ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                with: .color(.white.opacity(a))
              )
            }
          }
        }
        .blendMode(.overlay)
        .opacity(0.55)
      }
    }
  }

  /// Tiny seedable PRNG so the grain reshuffles on each tick without
  /// pulling in `arc4random`/`Foundation.Random` (which would be
  /// non-deterministic across runs and harder to dial).
  private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
      state = state &+ 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z &>> 31)
    }
    mutating func nextDouble() -> Double {
      Double(next() >> 11) / Double(1 << 53)
    }
  }
}

// MARK: - Tilted key cap

struct TiltedKeyCap: View {
  let label: String
  var isPressed: Bool = false

  var body: some View {
    let metrics = capMetrics(for: label)
    let sideInset: CGFloat = 7
    let baseExpose: CGFloat = 22
    let baseWidth = metrics.width + sideInset * 2
    let totalHeight = metrics.height + baseExpose

    ZStack {
      Ellipse()
        .fill(Color.white)
        .frame(width: baseWidth + 44, height: totalHeight + 30)
        .blur(radius: 30)
        .opacity(isPressed ? 0.30 : 0)
        .offset(y: 2)
        .animation(.easeOut(duration: 0.22), value: isPressed)

      RoundedRectangle(cornerRadius: metrics.corner + 3, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(white: 0.88), Color(white: 0.78)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: baseWidth, height: totalHeight)
        .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 10)

      ZStack {
        RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
          .fill(
            LinearGradient(
              colors: [Color.white, Color(white: 0.92)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
        RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
          .strokeBorder(Color(white: 0.86), lineWidth: 0.6)
        VStack(spacing: 1) {
          Text(capSymbol(for: label))
            .font(.system(size: metrics.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.28))
          if let name = capName(for: label) {
            Text(name)
              .font(.system(size: 10, weight: .medium, design: .rounded))
              .foregroundStyle(Color(white: 0.42))
          }
        }
      }
      .frame(width: metrics.width, height: metrics.height)
      .offset(y: isPressed ? 0 : -(baseExpose / 2))
      .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isPressed)
    }
    .frame(width: baseWidth + 14, height: totalHeight + 16)
  }

  private func capSymbol(for label: String) -> String {
    switch label {
    case "⌘": return "⌘"
    case "⇧": return "⇧"
    case "⌃": return "⌃"
    case "⌥": return "⌥"
    default: return label
    }
  }

  private func capName(for label: String) -> String? {
    switch label {
    case "⌘": return "cmd"
    case "⇧": return "shift"
    case "⌃": return "ctrl"
    case "⌥": return "opt"
    case "Space": return nil
    default: return nil
    }
  }

  private struct CapMetrics {
    let width: CGFloat
    let height: CGFloat
    let fontSize: CGFloat
    let corner: CGFloat
  }

  private func capMetrics(for label: String) -> CapMetrics {
    switch label {
    case "⇧":
      return CapMetrics(width: 96, height: 62, fontSize: 26, corner: 14)
    case "Space":
      return CapMetrics(width: 120, height: 62, fontSize: 22, corner: 14)
    default:
      if label.count <= 1 {
        return CapMetrics(width: 76, height: 62, fontSize: 30, corner: 14)
      }
      return CapMetrics(width: 120, height: 62, fontSize: 22, corner: 14)
    }
  }
}

// MARK: - Local key monitor

/// Watches `keyDown`, `keyUp`, and `flagsChanged` so each key in the
/// chord can react the moment it is pressed or released, regardless of
/// whether the full chord has been completed yet. Modifier flags drive
/// the modifier caps; `keyDown`/`keyUp` drive the main-key cap.
private struct KeyMonitor: NSViewRepresentable {
  let model: OnboardingModel

  func makeCoordinator() -> Coordinator { Coordinator(model: model) }

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    context.coordinator.install()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.uninstall()
  }

  final class Coordinator {
    private let model: OnboardingModel
    private var monitor: Any?
    private var modifierTimer: Timer?

    init(model: OnboardingModel) { self.model = model }

    func install() {
      uninstall()
      let model = self.model
      let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
      monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
        let flags = event.modifierFlags
        let type = event.type
        let key = Shortcut.normalize(event.charactersIgnoringModifiers ?? "")
        var swallow = false
        MainActor.assumeIsolated {
          model.updateModifiers(flags)
          switch type {
          case .keyDown:
            if let token = model.mainTokenIfKeyMatches(key) {
              model.setMainKeyDown(token)
              swallow = true
            }
          case .keyUp:
            model.setMainKeyUp(Shortcut.displayKey(key))
          default:
            break
          }
        }
        return swallow ? nil : event
      }
      modifierTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
        MainActor.assumeIsolated {
          model.updateModifiers(NSEvent.modifierFlags)
        }
      }
    }

    func uninstall() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      modifierTimer?.invalidate()
      modifierTimer = nil
    }

    deinit {
      if let monitor { NSEvent.removeMonitor(monitor) }
      modifierTimer?.invalidate()
    }
  }
}
