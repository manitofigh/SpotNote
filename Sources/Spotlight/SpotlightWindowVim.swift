import AppKit

extension SpotlightWindowController {
  /// Wires the controller's command-runner / search-handler / find-step
  /// closures so the `:`-prompt and normal-mode `n`/`N`/`/` keystrokes
  /// can reach the session, find controller, theme catalog, preferences,
  /// and the close-HUD path.
  func installVimCommandRunner() {
    vimController.commandRunner = { [weak self] command in
      self?.runVimCommand(command)
    }
    vimController.searchHandler = { [weak self] query in
      self?.runVimSearch(query)
    }
    vimController.findStepHandler = { [weak self] delta in
      self?.stepVimSearch(delta)
    }
  }

  private func runVimSearch(_ query: String) -> VimController.SearchOutcome? {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    findController.query = trimmed
    findController.search(in: session.currentText)
    return searchOutcome()
  }

  private func stepVimSearch(_ delta: Int) -> VimController.SearchOutcome? {
    if delta >= 0 { findController.next() } else { findController.previous() }
    return searchOutcome()
  }

  private func searchOutcome() -> VimController.SearchOutcome? {
    let total = findController.matches.count
    guard total > 0 else { return nil }
    return VimController.SearchOutcome(
      current: findController.currentIndex + 1,
      total: total
    )
  }

  private func runVimCommand(_ command: VimCommand) -> VimController.Message? {
    switch command {
    case .quit:
      close()
      return nil
    case .writeNoOp:
      return VimController.Message(text: "No need. SpotNote autosaves.", kind: .info)
    case .newNote:
      let target = session
      Task { await target.newChat() }
      return nil
    case .deleteNote:
      let target = session
      Task { await target.deleteCurrent() }
      return nil
    case .substitute(let req):
      return runSubstitute(req)
    case .gotoLine(let line):
      return runGotoLine(line)
    case .clearHighlight:
      runClearHighlight()
      return nil
    case .help:
      preferences.showHints = true
      return VimController.Message(text: "hints on", kind: .info)
    default:
      return runVimSetting(command)
    }
  }

  private func runVimSetting(_ command: VimCommand) -> VimController.Message? {
    switch command {
    case .setLineNumbers(let on):
      preferences.showLineNumbers = on
      return VimController.Message(text: on ? "line numbers on" : "line numbers off", kind: .info)
    case .setVimMode(let on):
      preferences.vimMode = on
      return on ? nil : VimController.Message(text: "vim mode off", kind: .info)
    case .setHints(let on):
      preferences.showHints = on
      return VimController.Message(text: on ? "hints on" : "hints off", kind: .info)
    case .setTheme(let name):
      return runSetTheme(name)
    case .setMaxLines(let count):
      let clamped = ThemePreferences.clampVisibleLines(count)
      preferences.maxVisibleLines = clamped
      return VimController.Message(text: "max lines: \(clamped)", kind: .info)
    default:
      return nil
    }
  }

  private func runSetTheme(_ name: String) -> VimController.Message? {
    let needle = name.lowercased()
    let match = ThemeCatalog.all.first {
      $0.id == needle || $0.name.lowercased() == needle
    }
    guard let match else {
      return VimController.Message(text: "E518: unknown theme: \(name)", kind: .error)
    }
    preferences.selectedThemeID = match.id
    return VimController.Message(text: "theme: \(match.name)", kind: .info)
  }

  private func runSubstitute(_ req: SubstituteRequest) -> VimController.Message? {
    let count = vimController.substituteHandler?(req) ?? 0
    if count == 0 {
      return VimController.Message(text: "E486: pattern not found", kind: .error)
    }
    let scope = req.global ? "in note" : "on line"
    let plural = count == 1 ? "" : "s"
    return VimController.Message(
      text: "\(count) substitution\(plural) \(scope)",
      kind: .success
    )
  }

  private func runGotoLine(_ line: Int) -> VimController.Message? {
    let ok = vimController.lineJumpHandler?(line) ?? false
    if !ok { return VimController.Message(text: "E16: invalid line: \(line)", kind: .error) }
    return nil
  }

  private func runClearHighlight() {
    if findController.isVisible {
      findController.close()
    } else {
      findController.query = ""
      findController.search(in: session.currentText)
    }
    vimController.clearSearchStatus()
  }
}
