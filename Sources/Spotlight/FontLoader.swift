import AppKit
import CoreText

/// Registers every `.ttf` / `.otf` bundled with the Spotlight module so that
/// SwiftUI `.custom(fontName:)` lookups resolve without the user installing
/// the fonts system-wide.
///
/// Safe to call multiple times; `CTFontManagerRegisterFontsForURL` reports
/// `alreadyRegistered` errors which are ignored.
enum FontLoader {
  static func registerBundledFonts() {
    let bundle = Bundle.spotlightResources
    let extensions = ["ttf", "otf"]
    let urls = extensions.flatMap { ext in
      bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
    }
    for url in urls {
      var error: Unmanaged<CFError>?
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    }
  }
}
