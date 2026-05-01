// swiftlint:disable file_length
import AppKit
import Core
import SwiftUI

public struct SettingsView: View {
  @ObservedObject var preferences: ThemePreferences
  @ObservedObject var shortcuts: ShortcutStore
  @State private var selection: SettingsSection = .general
  @State private var sidebarCollapsed = false

  private let bg = ThemeCatalog.obsidian.background

  public init(preferences: ThemePreferences, shortcuts: ShortcutStore) {
    self.preferences = preferences
    self.shortcuts = shortcuts
  }

  public var body: some View {
    HStack(spacing: 0) {
      if !sidebarCollapsed {
        sidebar
          .transition(.move(edge: .leading))
      } else {
        collapsedStrip
          .transition(.move(edge: .leading))
      }

      SettingsDividerLine()

      detail
    }
    .background(bg)
    .colorScheme(.dark)
    .frame(minWidth: 680, minHeight: 520)
    .animation(.easeInOut(duration: 0.18), value: sidebarCollapsed)
  }

  // MARK: - Sidebar (expanded)

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      sidebarToggle(collapse: true)
        .padding(.leading, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)

      VStack(alignment: .leading, spacing: 2) {
        ForEach(SettingsSection.allCases) { section in
          SidebarButton(
            section: section,
            isSelected: selection == section
          ) {
            selection = section
          }
        }
      }
      .padding(.horizontal, 10)

      Spacer()

      Text("SpotNote \(AppInfo.version)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary.opacity(0.6))
        .padding(.leading, 18)
        .padding(.bottom, 12)
    }
    .frame(width: 200)
    .background(Color.white.opacity(0.03))
  }

  // MARK: - Sidebar (collapsed)

  private var collapsedStrip: some View {
    VStack(spacing: 0) {
      sidebarToggle(collapse: false)
        .padding(.top, 10)

      Spacer()
    }
    .frame(width: 36)
    .background(Color.white.opacity(0.03))
  }

  private func sidebarToggle(collapse: Bool) -> some View {
    Button {
      sidebarCollapsed = collapse
    } label: {
      Image(systemName: "sidebar.left")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(collapse ? "Collapse sidebar" : "Show sidebar")
  }

  // MARK: - Detail

  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        switch selection {
        case .general: GeneralPane(preferences: preferences)
        case .editor: EditorPane(preferences: preferences)
        case .vim: VimPane(preferences: preferences)
        case .theme: ThemePane(preferences: preferences)
        case .shortcuts: ShortcutsPane(shortcuts: shortcuts)
        case .updates: UpdatesPane()
        }
      }
      .padding(.horizontal, 32)
      .padding(.vertical, 28)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case editor
  case vim
  case theme
  case shortcuts
  case updates

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .editor: return "Editor"
    case .vim: return "Vim"
    case .theme: return "Theme"
    case .shortcuts: return "Shortcuts"
    case .updates: return "Updates"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .editor: return "text.alignleft"
    case .vim: return "command"
    case .theme: return "paintpalette"
    case .shortcuts: return "keyboard"
    case .updates: return "arrow.down.circle"
    }
  }

  var iconColor: Color {
    switch self {
    case .general: return Color(red: 0.55, green: 0.55, blue: 0.58)
    case .editor: return Color(red: 0.35, green: 0.60, blue: 0.95)
    case .vim: return Color(red: 0.20, green: 0.55, blue: 0.40)
    case .theme: return Color(red: 0.85, green: 0.50, blue: 0.90)
    case .shortcuts: return Color(red: 0.95, green: 0.65, blue: 0.30)
    case .updates: return Color(red: 0.30, green: 0.75, blue: 0.50)
    }
  }
}

// MARK: - Sidebar button

private struct SidebarButton: View {
  let section: SettingsSection
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        SettingsIcon(systemName: section.icon, color: section.iconColor)
        Text(section.title)
          .font(.system(.body, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? .primary : .secondary)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            isSelected
              ? Color.white.opacity(0.10)
              : (isHovering ? Color.white.opacity(0.05) : Color.clear)
          )
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeInOut(duration: 0.12), value: isSelected)
    .animation(.easeInOut(duration: 0.12), value: isHovering)
  }
}

/// macOS System Settings–style icon: SF Symbol on a small colored
/// rounded-rect with a subtle top-to-bottom gradient.
struct SettingsIcon: View {
  let systemName: String
  let color: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 24, height: 24)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            LinearGradient(
              colors: [color, color.opacity(0.78)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
      )
  }
}

/// Thin vertical separator between sidebar and detail pane.
private struct SettingsDividerLine: View {
  var body: some View {
    Rectangle()
      .fill(Color.white.opacity(0.08))
      .frame(width: 1)
  }
}

// MARK: - General pane

private struct GeneralPane: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "General")

      SettingsCard {
        SettingsToggleRow(
          title: "Show in Dock",
          subtitle: "Display the SpotNote icon in the Dock and app switcher.",
          isOn: Binding(
            get: { preferences.showDockIcon },
            set: { preferences.showDockIcon = $0 }
          )
        )

        if preferences.showDockIcon {
          SettingsDivider()
          DockIconRow(preferences: preferences)
        }
      }

      SettingsCard {
        SettingsToggleRow(
          title: "Launch at login",
          subtitle: "Start SpotNote in the background when you log in to your Mac.",
          isOn: Binding(
            get: { preferences.launchAtLogin },
            set: { preferences.launchAtLogin = $0 }
          )
        )

        SettingsDivider()

        SettingsToggleRow(
          title: "Menu bar icon",
          subtitle: "Show the SpotNote icon in the macOS menu bar.",
          isOn: Binding(
            get: { preferences.showMenuBarIcon },
            set: { preferences.showMenuBarIcon = $0 }
          )
        )

        SettingsDivider()

        SettingsToggleRow(
          title: "Hints bar",
          subtitle: "Show the keyboard shortcut hint strip above the editor.",
          isOn: Binding(
            get: { preferences.showHints },
            set: { preferences.showHints = $0 }
          )
        )

        SettingsDivider()

        SettingsToggleRow(
          title: "Dim instead of hide",
          subtitle: "Keep the HUD visible at reduced opacity when it loses focus.",
          isOn: Binding(
            get: { preferences.dimOnFocusLoss },
            set: { preferences.dimOnFocusLoss = $0 }
          )
        )

        if preferences.dimOnFocusLoss {
          SettingsDivider()
          SettingsSliderRow(
            title: "Unfocused opacity",
            subtitle: "How transparent the HUD becomes when unfocused.",
            value: Binding(
              get: { preferences.unfocusedOpacity },
              set: { preferences.unfocusedOpacity = $0 }
            ),
            range: 0.1...1.0,
            step: 0.05,
            displayValue: "\(Int(preferences.unfocusedOpacity * 100))%"
          )
        }
      }
    }
  }
}

// MARK: - Editor pane

private struct EditorPane: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "Editor")

      SettingsCard {
        SettingsToggleRow(
          title: "Vim mode",
          subtitle: "Use vim-style keybindings for modal editing.",
          isOn: Binding(
            get: { preferences.vimMode },
            set: { preferences.vimMode = $0 }
          )
        )

        SettingsDivider()

        SettingsToggleRow(
          title: "Line numbers",
          subtitle: "Show line numbers on the left side of the editor.",
          isOn: Binding(
            get: { preferences.showLineNumbers },
            set: { preferences.showLineNumbers = $0 }
          )
        )

        SettingsDivider()

        SettingsSliderRow(
          title: "Max visible lines",
          subtitle: "Panel grows up to this many rows before scrolling.",
          value: Binding(
            get: { Double(preferences.maxVisibleLines) },
            set: { preferences.maxVisibleLines = Int($0.rounded()) }
          ),
          range: Double(ThemePreferences.minVisibleLines)...Double(ThemePreferences.maxVisibleLinesCap),
          step: 1,
          displayValue: "\(preferences.maxVisibleLines)"
        )
      }
    }
  }
}

// MARK: - Theme pane

private struct ThemePane: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PaneHeader(title: "Theme")

      themeGroup(title: "Dark", themes: ThemeCatalog.darkThemes)
      themeGroup(title: "Light", themes: ThemeCatalog.lightThemes)
    }
  }

  private func themeGroup(title: String, themes: [Theme]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(.subheadline, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.6)

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
        alignment: .leading,
        spacing: 12
      ) {
        ForEach(themes) { theme in
          ThemeSwatchButton(
            theme: theme,
            isSelected: preferences.selectedThemeID == theme.id,
            action: { preferences.selectedThemeID = theme.id }
          )
          .id("theme.\(theme.id)")
        }
      }
    }
  }
}

// MARK: - Pill button

/// Tailwind blue-50/blue-700 pill with KeyCap-style 3D depth -- gradient
/// face, darker lip below, inset ring. Dark-mode uses blue-950/blue-300.
struct SettingsPillButton: View {
  let label: String
  let action: () -> Void
  @State private var isHovering = false
  @State private var isPressing = false

  private let textColor = Color(red: 0.576, green: 0.784, blue: 1.0)
  private let faceTop = Color(red: 0.110, green: 0.165, blue: 0.310)
  private let faceBottom = Color(red: 0.075, green: 0.120, blue: 0.240)
  private let lip = Color(red: 0.050, green: 0.080, blue: 0.180)
  private let ring = Color(red: 0.30, green: 0.50, blue: 0.90)

  init(_ label: String, action: @escaping () -> Void) {
    self.label = label
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(face)
        .overlay(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(ring.opacity(isHovering ? 0.30 : 0.18), lineWidth: 0.8)
            .padding(.bottom, 1.2)
        )
        .scaleEffect(isPressing ? 0.97 : 1.0)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .onLongPressGesture(
      minimumDuration: 0,
      pressing: { isPressing = $0 },
      perform: {}
    )
    .animation(.easeInOut(duration: 0.10), value: isHovering)
    .animation(.easeInOut(duration: 0.08), value: isPressing)
  }

  private var face: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(lip)
        .padding(.top, 1.2)
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              isHovering ? faceTop.opacity(1.0) : faceTop.opacity(0.85),
              isHovering ? faceBottom.opacity(1.0) : faceBottom.opacity(0.85)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .padding(.bottom, 1.2)
    }
  }
}

// MARK: - Dock icon picker

private struct DockIconRow: View {
  @ObservedObject var preferences: ThemePreferences

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Dock icon")
          .font(.system(.body, weight: .regular))
        Text("Choose the icon style shown in the Dock and app switcher.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack(spacing: 12) {
        ForEach(DockIconStyle.allCases) { style in
          DockIconOption(
            style: style,
            isSelected: preferences.dockIconStyle == style
          ) {
            preferences.dockIconStyle = style
            DockIconSwitcher.apply(style)
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

private struct DockIconOption: View {
  let style: DockIconStyle
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        iconPreview
        Text(style.displayName)
          .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
          .foregroundStyle(isSelected ? .primary : .secondary)
      }
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeInOut(duration: 0.12), value: isSelected)
    .animation(.easeInOut(duration: 0.12), value: isHovering)
  }

  private var iconPreview: some View {
    Group {
      if let url = Bundle.spotlightResources.url(
        forResource: style.resourceName,
        withExtension: "png"
      ), let nsImage = NSImage(contentsOf: url) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
      } else {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.gray.opacity(0.3))
      }
    }
    .frame(width: 48, height: 48)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(
          isSelected ? Color.accentColor : (isHovering ? Color.white.opacity(0.15) : Color.clear),
          lineWidth: isSelected ? 2 : 1
        )
    )
  }
}

// MARK: - Shared components

struct PaneHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.system(.title, design: .default, weight: .bold))
  }
}

struct SettingsCard<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      content()
    }
    .padding(.vertical, 2)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.05))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
    )
  }
}

struct SettingsDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, 16)
      .opacity(0.5)
  }
}

struct SettingsToggleRow: View {
  let title: String
  let subtitle: String
  @Binding var isOn: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.body, weight: .regular))
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

private struct SettingsSliderRow: View {
  let title: String
  let subtitle: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let displayValue: String

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(.body, weight: .regular))
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        Slider(value: $value, in: range, step: step)
          .frame(width: 160)
        Text(displayValue)
          .font(.system(.callout, design: .monospaced))
          .frame(minWidth: 36, alignment: .trailing)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }
}

// MARK: - Theme swatch

private struct ThemeSwatchButton: View {
  let theme: Theme
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false
  @State private var isPressing = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        preview
        nameRow
      }
      .padding(10)
      .background(cardFill)
      .overlay(selectionRing)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .scaleEffect(isPressing ? 0.985 : 1.0)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .onLongPressGesture(
      minimumDuration: 0,
      pressing: { pressing in
        withAnimation(.easeInOut(duration: 0.08)) { isPressing = pressing }
      },
      perform: {}
    )
    .animation(.easeInOut(duration: 0.14), value: isHovering)
    .animation(.easeInOut(duration: 0.14), value: isSelected)
  }

  private var preview: some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(theme.background)
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(theme.border, lineWidth: 1)
      Text("Jot something down…")
        .font(.system(size: 11))
        .foregroundColor(theme.placeholder)
        .padding(.horizontal, 10)
    }
    .frame(height: 38)
  }

  private var nameRow: some View {
    HStack(spacing: 6) {
      Text(theme.name)
        .font(.system(.callout, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
      if isSelected {
        Image(systemName: "checkmark")
          .font(.caption.weight(.bold))
          .foregroundStyle(Color.accentColor)
          .transition(.scale.combined(with: .opacity))
      }
    }
  }

  private var cardFill: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(
        isSelected
          ? Color.accentColor.opacity(0.10)
          : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
      )
  }

  private var selectionRing: some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .strokeBorder(
        isSelected ? Color.accentColor : Color.clear,
        lineWidth: 1.5
      )
  }
}
