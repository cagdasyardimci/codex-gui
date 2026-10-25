# Command-line variables are recursive; regular expressions must remain literal data.
ifneq ($(origin FILTER),undefined)
    override FILTER := $(value FILTER)
    export FILTER
    ifeq ($(strip $(value FILTER)),)
        $(error FILTER must not be empty)
    endif
    ifneq ($(filter check test:%,$(MAKECMDGOALS)),)
        $(error FILTER is only supported with make test; omit it for named groups and checks)
    endif
endif

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

# Each named target appends its group to the help list below.
TEST_GROUPS :=

test-shell-quote = '$(subst ','"'"',$(1))'
test-filter-options = $(if $(1),--filter $(call test-shell-quote,$(1)))
PARALLEL ?= 1
ifneq ($(PARALLEL),0)
    ifneq ($(PARALLEL),1)
        $(error PARALLEL must be 0 or 1)
    endif
endif
test-command = swift test $(TEST_FLAGS) $(if $(filter 1,$(PARALLEL)),--parallel,--no-parallel)

define run-tests
	python3 Tests/run-swift-tests.py $(if $(2),--selection-file $(call test-shell-quote,$(2))) -- $(test-command) $(call test-filter-options,$(1))
endef

test: FORCE
	$(call run-tests,$(value FILTER),$(if $(value FILTER),,Tests/Selections/default.txt))

TEST_GROUPS += summary
test\:summary: FORCE
	$(call run-tests,PinnedSummary.*Tests)

TEST_GROUPS += navigation
test\:navigation: FORCE
	$(call run-tests,NavigationViewControllerTests|taskTitleScrollsOnceAndResetsAfterHover|taskHoverCardUsesOwnRowMetadataAndDismissesOnExitOrWindowResign|taskArchiveButtonRoutesToItsOwnRowWithoutChangingSelection)

TEST_GROUPS += window-layout
test\:window-layout: FORCE
	$(call run-tests,^CodexGUITests[.]WindowLayoutTests/)

TEST_GROUPS += task-window-layout
test\:task-window-layout: FORCE
	$(call run-tests,TaskWorkspaceWindowLayoutTests)

TEST_GROUPS += full-access
test\:full-access: FORCE
	$(call run-tests,FullAccessConfirmationTests)

TEST_GROUPS += desktop-layout
test\:desktop-layout: FORCE
	$(call run-tests,DesktopLayoutTests)

TEST_GROUPS += window-lifecycle
test\:window-lifecycle: FORCE
	$(call run-tests,closedWindowDetachesItsStorePublicationObserver)


TEST_GROUPS += terminal-hover
test\:terminal-hover: FORCE
	$(call run-tests,terminalCopyHoverShowsTooltipAndDismissesWithoutTakingFocus|ConversationTerminalCopyButtonTests)



TEST_GROUPS += task-archive
test\:task-archive: FORCE
	$(call run-tests,taskArchiveButtonRoutesToItsOwnRowWithoutChangingSelection)

TEST_GROUPS += turn-rail
test\:turn-rail: FORCE
	$(call run-tests,railJumpsBookmarksAndClearsOnChatSwitch)

TEST_GROUPS += search-rebinding
test\:search-rebinding: FORCE
	$(call run-tests,searchSheetKeepsConversationChangesAndDismissesItsPreviousStoreOnRebinding)


TEST_GROUPS += image-panel
test\:image-panel: FORCE
	$(call run-tests,ExpandedImagePreviewTests|localAndInlineImagesExpandInTheWindowAndReuseOrDetachDismissesThem|imageImportCreatesPreviewAndRemovalControl|imageThumbnailUsesSharedViewerAndDismissesWithItsOwner)


TEST_GROUPS += transcript-appearance
test\:transcript-appearance: FORCE
	$(call run-tests,TranscriptLayerAppearanceTests)

TEST_GROUPS += composer-appearance
test\:composer-appearance: FORCE
	$(call run-tests,Composer(CustomDrawing)?AppearanceTests|ApprovalPolicyPopoverTests)

TEST_GROUPS += sources-appearance
test\:sources-appearance: FORCE
	$(call run-tests,SourcesHoverAppearanceTests)


TEST_GROUPS += task-execution
test\:task-execution: FORCE
	$(call run-tests,^CodexGUITests[.]TaskWorkspaceCoordinatorTests/)
