import Testing

@testable import Spotlight

@Suite("FocusTrigger")
@MainActor
struct FocusTriggerTests {
  @Test("pulse increments the tick monotonically")
  func pulseMonotonic() {
    let trigger = FocusTrigger()
    let start = trigger.tick
    trigger.pulse()
    trigger.pulse()
    trigger.pulse()
    #expect(trigger.tick == start &+ 3)
  }

  @Test("tick wraps without crashing -- overflow uses &+")
  func wrapsSafely() {
    let trigger = FocusTrigger()
    for _ in 0..<1000 { trigger.pulse() }
    #expect(trigger.tick >= 1000)
  }
}
