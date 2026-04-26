# SpotNote Engineering Rules

**Target:** macOS-native app (SwiftUI + Metal) written in Swift 6.
**Scope:** This document is the single source of truth for conventions, tooling, and workflows. Read it in full before authoring code or tests.

---

## 0. Philosophy

Lean over clever. The smallest working implementation wins. No speculative abstractions, no protocols added "just in case", no dead parameters.

Trust the type system. Prefer `Sendable`, actors, non-optional types, and exhaustive enums over runtime guards. Compile-time correctness beats runtime checks.

Measure, don't guess. Every performance claim is backed by an Instruments trace. No micro-optimisations without a profile.

Every public symbol is a commitment. Default access is `internal`. `public` only when the symbol crosses a module boundary as a considered API.

Metal is an engineering discipline, not a library call. Resource lifetime, command buffer submission, and memory barriers are first-class design concerns.

---

## 1. Swift Language Rules

### 1.1 Naming
- `UpperCamelCase` for types, protocols, enum cases.
- `lowerCamelCase` for everything else.
- Acronyms follow surrounding case: `urlSession`, `HTTPServer`, `jsonDecoder`.
- File name = primary type name (`NoteEditorView.swift` contains `NoteEditorView`).
- Protocols describing what something *is* use nouns (`Collection`); capability protocols use `-able` / `-ing` (`Equatable`, `ProgressReporting`).
- Booleans read as assertions: `isEmpty`, `hasPrefix(_:)`.

### 1.2 Access Control
- Default to `internal`. `private` for type-internal detail. `fileprivate` only when same-file extensions need access.
- Mark types and methods `final` unless subclassing is a designed extension point.
- `public` symbols carry a doc comment explaining the contract.

### 1.3 Types
- Prefer `struct`. Reach for `class` only for reference semantics, Objective-C interop, or identity.
- Prefer `enum` with associated values over a pair of optionals or a `type` string.
- Never `force-unwrap` (`!`), `force-cast` (`as!`), or `try!` in production code. The linter blocks them.
- Use `Result<Success, Failure>` only when bridging async callback APIs; in async code, throw.

### 1.4 Immutability
- `let` by default. `var` only when mutation is required.
- Value types are `Sendable` by default. Reference types must explicitly conform or be actors.

### 1.5 Control Flow
- Prefer `guard` for early exits over nested `if`.
- Prefer `for ... in` and higher-order functions (`map`/`filter`/`reduce`) over `while` for collections.
- Exhaustive `switch` over enums. No `default:` on internal/private enums so the compiler warns when cases are added.

### 1.6 Documentation
- Doc comments are encouraged but not linter-enforced. Write `///` only when the *why* is non-obvious.
- Skip them when a well-named identifier already says everything.
- When you do write one, prefer Swift Markdown: `- Parameters:`, `- Returns:`, `- Throws:`, `- Complexity:` (big-O) where the function is algorithmic.
- Long files (>400 lines) are themselves a smell. Split.

### 1.7 Errors
- Model domain errors as `enum MyFeatureError: Error, Equatable { ... }`.
- Attach `LocalizedError` when the error can reach the UI.
- Do not swallow errors (`try? ...; // ignore`) without a `// swiftlint:disable:next` justification.

---

## 2. Concurrency (Swift 6)

1. Build with strict concurrency = Complete (`SWIFT_STRICT_CONCURRENCY=complete`). Compile warnings about data races are errors.
2. Never use `@unchecked Sendable` or `nonisolated(unsafe)` as a shortcut. If the compiler complains, there is a real race; fix the design.
3. UI state lives on `@MainActor`. Views, view models, and anything that mutates observable state must be `@MainActor`-isolated.
4. Protect shared mutable state with `actor`. Actors are preferred over locks, `DispatchQueue` serialisation, or `NSLock`.
5. Use structured concurrency (`async let`, `TaskGroup`, `withTaskGroup`) before reaching for unstructured `Task { }`. Every unstructured task has a documented lifecycle and explicit cancellation.
6. Always check `Task.checkCancellation()` inside long-running loops.
7. `async` functions throw `CancellationError`; handle it up to a UI boundary and ignore silently there.
8. Prefer `AsyncStream` / `AsyncSequence` for event pipelines over Combine.
9. GCD (`DispatchQueue`) is permitted only for bridging C APIs or Metal's `MTLCommandQueue` interaction.

---

## 3. UI Architecture (SwiftUI)

SpotNote uses SwiftUI-first MVVM with composable feature modules. TCA is not adopted by default.

### 3.1 Layering
- `View` (SwiftUI): layout, bindings, no business logic, no `Task`-firing beyond `.task { await model.load() }`.
- `ViewModel` (`@Observable` class, `@MainActor`): owns view state, calls into `Core` services. Holds no `View` references.
- `Service` / `Repository` (in `Core`/`Persistence`): async, `Sendable`, no UI imports.

### 3.2 State
- Prefer Swift 5.9+ `@Observable` macro over `ObservableObject`/`@Published`. Less boilerplate, finer-grained invalidation.
- Pass state down via `let` properties or `Binding`. Never use `EnvironmentObject` as a grab bag.
- `@Environment` is reserved for app-wide services (theme, feature flags).

---

## 4. Metal & Rendering

Metal code lives in `Sources/Rendering` (Swift, CPU side) and `Sources/Shaders` (`.metal` MSL files). Rules distil Apple's Metal Best Practices Guide and WWDC20/21/23 sessions.

### 4.1 Command Submission
- One `MTLCommandQueue` per thread of submission. Most apps need exactly one.
- Batch draw calls in a single command buffer; aim for <= 3 command buffers per frame.
- Set resource storage mode deliberately:
  - `.shared` for small CPU-updated-per-frame buffers (uniforms).
  - `.private` for GPU-only textures and large static buffers; upload via blit from a `.shared` staging buffer.
  - `.memoryless` for intermediate render targets that never touch system memory. Use this for G-buffer-style attachments on Apple Silicon.
- Use argument buffers for large bind sets. Reduces CPU overhead and unlocks GPU-driven rendering.
- Never read a resource on the CPU before its command buffer has completed. Synchronise via `addCompletedHandler` or `waitUntilCompleted` (test-only).

### 4.2 Memory & Bandwidth
- Apple GPUs are Tile-Based Deferred Renderers (TBDR). Treat tile memory as a scarce, fast scratchpad.
- Prefer `half` / `half4` over `float` / `float4` in MSL.
- Choose the smallest texture format that meets quality. Avoid `.rgba32Float` unless mathematically required.
- Avoid fragment-stage memory barriers; they flush tile memory to DRAM. Use programmable blending or single-pass deferred shading instead.
- Prefer `loadAction = .clear` over `.load` when a previous value is not needed; prefer `storeAction = .dontCare` for intermediate attachments.

### 4.3 Pipeline State
- Build all `MTLRenderPipelineState` / `MTLComputePipelineState` objects at app launch or first-use, never per frame.
- Compile shaders offline (`.metal` -> `.metallib`) for release builds. Use Metal function constants to specialise variants.
- Enable `MTLCompileOptions.mathMode = .fast` only after confirming no NaN/Inf dependence.

### 4.4 Shaders (MSL)
- Prefer constant-address-space buffers for uniforms (`constant T& uniforms [[buffer(0)]]`); cached, broadcasted, fast.
- Unroll short loops with `[[unroll]]` only when the trip count is compile-time known.
- Use `simd_group` / quad-group intrinsics for reductions when possible.
- Avoid dynamic indexing into large arrays in thread-private memory.

### 4.5 Debugging & Profiling
- Name every resource (`label = "..."`). Names appear in Xcode's GPU frame capture and Metal System Trace.
- Wrap logical work in `commandBuffer.pushDebugGroup(_:) / popDebugGroup()`.
- Validate every rendering feature with: GPU Frame Capture, Metal System Trace (Instruments), and GPU Counters.
- Ship with `MTL_DEBUG_LAYER=1` and `MTL_SHADER_VALIDATION=1` in Debug builds only.

---

## 5. Tooling & Static Analysis

All tools are vendored via SPM plugins or Homebrew and invoked from `make` targets and CI.

### 5.1 Formatter (`swift-format`)
- Config: `Tools/.swift-format`.
- Line length: 120. Indent: 2 spaces.
- Run in CI: `swift-format lint --strict --recursive Sources Tests` must exit 0.

### 5.2 Linter (`SwiftLint`)
- Config: `Tools/.swiftlint.yml`.
- Complexity thresholds (errors, not warnings):
  - `cyclomatic_complexity`: warning 10, error 15.
  - `function_body_length`: warning 40, error 80.
  - `type_body_length`: warning 250, error 400.
  - `file_length`: warning 400, error 700.
- `swiftlint analyze` runs weekly in CI; opt-in rules catch unused declarations the in-file pass cannot.

### 5.3 Dead Code (`Periphery`)
- Scan with `periphery scan --strict` on every PR. New unused declarations block merge.
- Annotate intentional exceptions: `// periphery:ignore - exposed for SwiftUI previews`.

### 5.4 Complexity Analysis
- Cyclomatic complexity enforced by SwiftLint. Target mean CC <= 5 per function; any function > 10 must be justified in code review.
- `lizard` runs nightly with the project's tuned thresholds (CCN, length, args). CI fails on violations.
- Every public algorithmic function carries a `- Complexity:` line in its doc comment (e.g. `- Complexity: O(n log n)`).
- Performance-critical paths get an XCTest `measure { }` block plus an Instruments Time Profiler trace archived on first introduction.

### 5.5 Other
- Clang/Swift static analyzer runs as part of `xcodebuild analyze`; zero warnings required.
- Thread Sanitizer enabled on the `Debug-TSan` scheme; run the full test suite under TSan before every release.
- Address Sanitizer for Metal bridging code.

---

## 6. Testing

### 6.1 Frameworks
- Unit & integration tests use Swift Testing (`import Testing`, `@Test`, `#expect`).
- UI tests and performance tests stay on `XCTest` (`XCUIApplication`, `XCTMetric`).
- Do not mix the two within a single suite.

### 6.2 What to Test
- All pure logic in `Core` is unit-tested. Aim for >= 85% line coverage in `Core`, >= 70% overall.
- View models: test state transitions, not view output.
- Metal rendering: deterministic golden-image tests with a per-pixel tolerance.

### 6.3 Test Quality
- One behaviour per test, full-sentence names: `@Test("loads notes sorted by most-recently-edited")`.
- Prefer parameterised tests over `for`-loops inside a test.
- No `sleep(_:)`. Wait via clocks or event-driven expectations.
- No real network. Stub at `URLProtocol` or repository layer.
- No real clock. Inject one (`ContinuousClock` / test double).
- Tests are deterministic or they are deleted.

---

## 7. Build, CI, and Release

- Single `Makefile` entry points: `make fmt`, `make lint`, `make test`, `make analyze`, `make periphery`, `make ci` (runs everything).
- CI runs, in order: `swift-format lint --strict` -> `swiftlint --strict` -> `swift build` -> `swift test --parallel` -> `periphery scan --strict` -> `lizard` -> `xcodebuild analyze` -> archive.
- Zero-warning policy. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in Release.
- `main` is always releasable. Feature branches rebase onto `main` before merge; no merge commits.

### 7.1 Commit Style
- Format: `<short-tag>: all lowercase and concise msg`.
  - `bug-fix: unexpected app termination on Intel chips`
  - `feat: add Metal-based blur behind the Spotlight panel`
- Lowercase EXCEPT legitimate acronyms: API, URL, CPU, GPU, UI, UX, MSL, SPM, CI, CD, macOS, iOS, JSON, HTML, HTTP, I/O, etc.
- Tags: `feat`, `bug-fix`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `build`, `chore`, `ci`, `revert`.
- Subject line <= 72 chars. No trailing period. Imperative mood.
- Body is optional; when present, separate from subject with a blank line and wrap at ~100 chars.
- One logical change per commit.

### 7.2 Commit Cadence
- After finishing a round of changes, commit and push to `origin` before considering the task complete.
- Never use destructive git commands (`push --force`, `reset --hard`, `branch -D`, history rewrites on `main`) without explicit user instruction.
- Never bypass hooks (`--no-verify`) or signing without explicit user instruction.
