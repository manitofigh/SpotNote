import Testing

@testable import Core

@Suite("AppInfo")
struct AppInfoTests {
  @Test("bundle identifier uses reverse-dns form")
  func bundleIdentifierFormat() {
    #expect(AppInfo.bundleIdentifier.contains("."))
    #expect(AppInfo.bundleIdentifier.hasPrefix("com."))
  }

  @Test("version is non-empty semver-ish")
  func versionShape() {
    #expect(!AppInfo.version.isEmpty)
    #expect(AppInfo.version.split(separator: ".").count >= 2)
  }
}
