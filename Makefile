.PHONY: help format lint build test check FORCE

# Commands in this checkout share one SwiftPM build directory.
.NOTPARALLEL:

format:
	python3 scripts/swift-style.py

lint:
	python3 scripts/swift-style.py --check

build:
	swift build

# A phony prerequisite keeps colon commands unconditional on macOS Make.
build\:bundle: FORCE
	./scripts/bundle.sh debug

build\:bundle\:release: FORCE
	./scripts/bundle.sh release

check: lint build test

help:
	@printf '%s\n' \
		'Commands:' \
		'  make format                       Format Swift sources' \
		'  make lint                         Check Swift formatting' \
		'  make build                        Build the executable' \
		'  make build:bundle                 Build the debug app bundle' \
		'  make build:bundle:release         Build the release app bundle' \
		'  make check                        Run formatting, build, and all tests' \
		'  make test                         Run all 668 discovered tests' \
		'  make test PARALLEL=0              Run the full suite sequentially' \
		'  make test:<group>                 Run only that group in one process' \
		'  make test FILTER="regex"          Run a custom selection in one process' \
		'  make help                         Show this help' \
		'  Bundle signing: CODEX_GUI_SIGNING_IDENTITY=<identity> (see README)' \
		'' \
		'Test groups (make test:<group>):'
	@printf '  %s\n' $(TEST_GROUPS)
	@printf '\n'
	@$(MAKE) --no-print-directory help:ui

FORCE:

include Tests/Workflow.mk
include Tests/E2E/Workflow.mk
