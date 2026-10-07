# Make exposes normal runs and reports; advanced options belong to the Swift command.
UI_REPEAT ?= 1
UI_RUN ?=
E2E_PACKAGE := $(CURDIR)/Tests/E2E
E2E_XCODE := $(if $(DEVELOPER_DIR),$(DEVELOPER_DIR),/Applications/Xcode.app/Contents/Developer)
E2E_SWIFT := DEVELOPER_DIR="$(E2E_XCODE)" swift run --package-path "$(E2E_PACKAGE)"

.PHONY: ui-help ui-tools ui-test ui-report
.NOTPARALLEL: ui-test ui-report

ui-help:
	@printf '%s\n' \
	  'make ui-test [UI_REPEAT=1..100]' \
	  'make ui-report UI_RUN=/absolute/path/to/run-directory' \
	  'Advanced options: swift run --package-path Tests/E2E E2EWorkflow --help'

ui-tools:
	@DEVELOPER_DIR="$(E2E_XCODE)" swift build --package-path "$(E2E_PACKAGE)"

ui-test:
	@$(E2E_SWIFT) E2EWorkflow test --root "$(CURDIR)" \
	  --developer-dir "$(E2E_XCODE)" --repeat "$(UI_REPEAT)"

ui-report:
	@$(E2E_SWIFT) E2EWorkflow report --root "$(CURDIR)" \
	  --developer-dir "$(E2E_XCODE)" --run "$(UI_RUN)"
