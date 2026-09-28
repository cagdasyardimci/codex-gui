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
	python3 scripts/swift-style.py --check

build:
	swift build

test:
	# Transient native popovers need a separate SwiftPM test-host lifecycle.
	swift test $(TEST_FLAGS) --skip TaskWorkspaceWindowLayoutTests
	swift test $(TEST_FLAGS) --filter TaskWorkspaceWindowLayoutTests

check: lint build test
