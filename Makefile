.PHONY: format lint build test test-suites test-groups check
.NOTPARALLEL: test-suites

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

# Named SwiftPM selections; each invocation uses a separate test process.
TEST_SUITE ?= all
ISOLATED_TEST_SUITES := window-layout task-window-layout full-access desktop-layout \
	window-lifecycle settled-hover terminal-hover task-title task-hover task-archive \
	turn-rail search-rebinding search-sheet image-panel sidebar-appearance \
	transcript-appearance composer-appearance sources-appearance rail-appearance \
	task-execution
TEST_SUITES := all common summary navigation navigation-common $(ISOLATED_TEST_SUITES)

FILTER_summary := PinnedSummary.*Tests
FILTER_navigation-common := NavigationViewControllerTests
NAVIGATION_NATIVE_SUITES := task-title task-hover task-archive
FILTER_window-layout := ^CodexGUITests[.]WindowLayoutTests/
FILTER_task-window-layout := TaskWorkspaceWindowLayoutTests
FILTER_full-access := FullAccessConfirmationTests
FILTER_desktop-layout := DesktopLayoutTests
FILTER_window-lifecycle := closedWindowDetachesItsStorePublicationObserver
FILTER_settled-hover := shownWindowHoverUsesSettledHeaderGeometryAfterRepositioning
FILTER_terminal-hover := terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus|ConversationTerminalCopyButtonTests
FILTER_task-title := taskTitleScrollsOnceAndResetsAfterHover
FILTER_task-hover := taskHoverCardUsesOwnRowMetadataAndDismissesOnExitOrWindowResign
FILTER_task-archive := taskArchiveButtonRoutesToItsOwnRowWithoutChangingSelection
FILTER_turn-rail := railJumpsBookmarksAndClearsOnChatSwitch
FILTER_search-rebinding := searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding
FILTER_search-sheet := MessageSearchSheetLifecycleTests
FILTER_image-panel := ExpandedImagePreviewTests|localAndInlineImagesExpandInTheWindowAndReuseOrDetachDismissesThem|imageImportCreatesPreviewAndRemovalControl|imageThumbnailUsesSharedViewerAndDismissesWithItsOwner
FILTER_sidebar-appearance := TaskSidebarAppearanceTests
FILTER_transcript-appearance := TranscriptLayerAppearanceTests
FILTER_composer-appearance := Composer(CustomDrawing)?AppearanceTests
FILTER_sources-appearance := SourcesHoverAppearanceTests
FILTER_rail-appearance := TurnRailAppearanceTests
FILTER_task-execution := ^CodexGUITests[.]TaskWorkspaceCoordinatorTests/

# The common group is the complement of the isolated selections.
empty :=
space := $(empty) $(empty)
NAVIGATION_NATIVE_FILTER := $(subst $(space),|,$(strip $(foreach suite,$(NAVIGATION_NATIVE_SUITES),$(FILTER_$(suite)))))
ISOLATED_FILTER := $(subst $(space),|,$(strip $(foreach suite,$(ISOLATED_TEST_SUITES),$(FILTER_$(suite)))))

format:
	python3 scripts/swift-style.py

lint:
	python3 scripts/swift-style.py --check

build:
	swift build

test:
	$(if $(and $(filter 1,$(words $(TEST_SUITE))),$(filter $(TEST_SUITES),$(TEST_SUITE))),,$(error Unknown TEST_SUITE '$(TEST_SUITE)'; use make test-groups))
ifeq ($(TEST_SUITE),all)
	$(MAKE) --no-print-directory test-suites
else ifeq ($(TEST_SUITE),navigation)
	@set -e; for suite in navigation-common $(NAVIGATION_NATIVE_SUITES); do \
		$(MAKE) --no-print-directory test TEST_SUITE=$$suite; \
	done
else
	python3 Tests/run-swift-tests.py -- swift test $(TEST_FLAGS) --no-parallel $(if $(filter common,$(TEST_SUITE)),--skip '$(ISOLATED_FILTER)',$(if $(FILTER_$(TEST_SUITE)),--filter '$(FILTER_$(TEST_SUITE))')) $(if $(filter navigation-common,$(TEST_SUITE)),--skip '$(NAVIGATION_NATIVE_FILTER)')
endif

test-groups:
	@printf '%s\n' $(TEST_SUITES)

test-suites:
	@set -e; for suite in common $(ISOLATED_TEST_SUITES); do \
		$(MAKE) --no-print-directory test TEST_SUITE=$$suite; \
	done

check: lint build test

include Tests/E2E/Workflow.mk
