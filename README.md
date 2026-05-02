# SpotNote

A Spotlight-style macOS note capture app. Toggle with **⌘⇧Space**.

Live site: https://spotnote.org

## Requirements

macOS 14+, Xcode 16+ (Swift 6 toolchain).

## Quick start

```bash
./scripts/setup.sh   # one-time: brew, swift-format, swiftlint, periphery, lizard
./scripts/run.sh     # builds and runs. You can then toggle with the shortcut.
```

Equivalent Make targets exist for every script: `make build`, `make run`, `make test`, `make ci`.

## Common tasks

| Task | Script | Make |
| --- | --- | --- |
| Format | `scripts/fmt.sh` | `make fmt` |
| Lint | `scripts/lint.sh` | `make lint` |
| Tests | `scripts/test.sh` | `make test` |
| Build .app | `scripts/build.sh [debug\|release]` | `make build` / `make release` |
| Build + launch | `scripts/run.sh` | `make run` |
| Full pipeline | `scripts/ci.sh` | `make ci` |

`ci.sh` runs: `tools-check -> fmt-check -> lint -> build -> test -> periphery -> complexity`.

## Contributing

Read [`RULES.md`](./RULES.md) before opening a PR. It covers Swift 6 conventions, concurrency, Metal discipline, the linter thresholds CI enforces, and the commit-message format.
