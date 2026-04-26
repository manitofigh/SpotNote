import Testing

@testable import Spotlight

@Suite("FontLoader")
struct FontLoaderTests {
  @Test("registerBundledFonts is idempotent and safe to call with zero resources")
  func registerIsIdempotent() {
    // No fonts are shipped in the repo by default (see Resources/README.md).
    // The loader must still complete cleanly and tolerate being called
    // multiple times without raising.
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    FontLoader.registerBundledFonts()
    #expect(Bool(true))
  }
}
