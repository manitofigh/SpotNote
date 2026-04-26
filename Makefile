SHELL := /usr/bin/env bash
S := ./scripts

.PHONY: help setup build run release test fmt fmt-check lint analyze periphery complexity ci clean tools-check

help:
	@echo "SpotNote — make targets (each delegates to scripts/<name>.sh):"
	@echo "  setup        - one-time toolchain bootstrap (run this first)"
	@echo "  build        - compile debug and assemble .app"
	@echo "  run          - build and launch SpotNote.app"
	@echo "  release      - release-configuration .app"
	@echo "  test         - swift test --parallel + coverage"
	@echo "  fmt          - swift-format in place"
	@echo "  fmt-check    - swift-format lint --strict"
	@echo "  lint         - swiftlint --strict"
	@echo "  analyze      - swiftlint analyze (cross-file rules)"
	@echo "  periphery    - dead-code scan"
	@echo "  complexity   - lizard CC/length/args check"
	@echo "  ci           - full pipeline (fmt-check -> lint -> build -> test -> periphery -> complexity)"
	@echo "  tools-check  - verify required CLIs are installed"
	@echo "  clean        - remove build artifacts"

setup:         ; $(S)/setup.sh
build:         ; $(S)/build.sh debug
run:           ; $(S)/run.sh debug
release:       ; $(S)/build.sh release
test:          ; $(S)/test.sh
fmt:           ; $(S)/fmt.sh
fmt-check:     ; $(S)/fmt-check.sh
lint:          ; $(S)/lint.sh
analyze:       ; $(S)/analyze.sh
periphery:     ; $(S)/periphery.sh
complexity:    ; $(S)/complexity.sh
ci:            ; $(S)/ci.sh
tools-check:   ; $(S)/tools-check.sh

clean:
	rm -rf .build build .swiftpm Tools/reports
