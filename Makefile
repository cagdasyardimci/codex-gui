.PHONY: format lint build test check

DEVELOPER_DIRECTORY := $(shell xcode-select -p)
TESTING_FRAMEWORK_DIRECTORY := $(DEVELOPER_DIRECTORY)/Library/Developer/Frameworks
TESTING_PLUGIN_DIRECTORY := $(DEVELOPER_DIRECTORY)/usr/lib/swift/host/plugins/testing
TESTING_INTEROP_DIRECTORY := $(DEVELOPER_DIRECTORY)/Library/Developer/usr/lib

ifneq ($(wildcard $(TESTING_FRAMEWORK_DIRECTORY)/Testing.framework),)
TEST_FLAGS := -Xswiftc -F -Xswiftc $(TESTING_FRAMEWORK_DIRECTORY) \
	-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGIN_DIRECTORY) \
	-Xlinker -F -Xlinker $(TESTING_FRAMEWORK_DIRECTORY) \
	-Xlinker -rpath -Xlinker $(TESTING_FRAMEWORK_DIRECTORY) \
	-Xlinker -rpath -Xlinker $(TESTING_INTEROP_DIRECTORY)
endif

format:
	python3 scripts/swift-style.py

lint:
	python3 scripts/test-swift-style.py
	python3 scripts/test-run-swift-tests.py
	python3 scripts/swift-style.py --check

build:
	swift build

test:
	# AppKit tests share the process-wide application and run serially.
	# Shown native windows and popovers need separate SwiftPM test-host lifecycles.
	python3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel --skip 'WindowLayoutTests|closedWindowDetachesItsStorePublicationObserver|shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning'
	python3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel --filter '^CodexGUITests.WindowLayoutTests'
	python3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel --filter TaskWorkspaceWindowLayoutTests
	python3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel --filter closedWindowDetachesItsStorePublicationObserver
	python3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel --filter shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning

check: lint build test
