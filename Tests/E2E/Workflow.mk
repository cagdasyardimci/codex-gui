# Make exposes normal runs and reports; advanced options belong to the Swift command.
UI_REPEAT ?= 1
UI_RUN ?=
E2E_PACKAGE := $(CURDIR)/Tests/E2E
E2E_XCODE := $(if $(DEVELOPER_DIR),$(DEVELOPER_DIR),/Applications/Xcode.app/Contents/Developer)
E2E_SWIFT := DEVELOPER_DIR="$(E2E_XCODE)" swift run --package-path "$(E2E_PACKAGE)"

help\:ui: FORCE
	@printf '%s\n' \
	  'make help:ui' \
	  'make test:ui [UI_REPEAT=1..100]' \
	  'make report:ui UI_RUN=/absolute/path/to/run-directory' \
	  'Advanced options: swift run --package-path Tests/E2E E2EWorkflow --help'

test\:ui: FORCE
	@$(E2E_SWIFT) E2EWorkflow test --root "$(CURDIR)" \
	  --developer-dir "$(E2E_XCODE)" --repeat "$(UI_REPEAT)"

report\:ui: FORCE
	@$(E2E_SWIFT) E2EWorkflow report --root "$(CURDIR)" \
	  --developer-dir "$(E2E_XCODE)" --run "$(UI_RUN)"
