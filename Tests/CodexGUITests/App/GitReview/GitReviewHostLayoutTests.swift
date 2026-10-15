import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitReviewHostLayoutTests
{
	@Test func focusedReviewRestoresPaneChoicesAndSavesOrdinaryGeometry() throws
	{
		_ = NSApplication.shared
		let suite = "GitReviewHostLayout.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let store = WindowLayoutStore(defaults: defaults)
		let navigation = NavigationViewController()
		let conversation = ConversationViewController()
		let inspector = InspectorViewController()
		let panes = WindowPaneController(
			navigation: navigation,
			conversation: conversation,
			inspector: inspector,
			layoutStore: store
		)
		let chrome = WindowChromeViewController(
			split: panes.split,
			accountButton: NSButton()
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1200,
				height: 760
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = chrome
		panes.restoreLayout(in: window)
		panes.didPresentWindow()
		defer
		{
			window.close()
		}
		for sidebarCollapsed in [false, true]
		{
			panes.setSidebarCollapsed(sidebarCollapsed)
			panes.setReviewCollapsed(true)
			window.layoutIfNeeded()
			panes.saveLayout()
			let ordinary = try #require(store.layout)
			panes.setGitReviewFocused(true)
			chrome.setGitReviewFocused(true)
			window.layoutIfNeeded()
			#expect(panes.isGitReviewFocused)
			#expect(panes.split.splitViewItems[0].isCollapsed)
			#expect(panes.split.splitViewItems[1].isCollapsed)
			#expect(!panes.isReviewCollapsed)
			#expect(abs(inspector.view.frame.width - chrome.view.bounds.width) < 2)
			panes.saveLayout()
			let focusedSave = try #require(store.layout)
			#expect(focusedSave.navigationCollapsed == ordinary.navigationCollapsed)
			#expect(focusedSave.reviewVisibility == ordinary.reviewVisibility)
			#expect(focusedSave.navigationWidth == ordinary.navigationWidth)
			#expect(focusedSave.reviewWidth == ordinary.reviewWidth)
			panes.setGitReviewFocused(false)
			chrome.setGitReviewFocused(false)
			window.layoutIfNeeded()
			#expect(panes.split.splitViewItems[0].isCollapsed == sidebarCollapsed)
			#expect(!panes.split.splitViewItems[1].isCollapsed)
			#expect(panes.isReviewCollapsed)
		}
	}

	@Test func changesOpensBesideChatAndOnlyExplicitExpansionHidesToolbar() throws
	{
		_ = NSApplication.shared
		let suite = "GitReviewOpening.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let state = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
		let controller = MainWindowController(
			store: state.store,
			onOpenProject:
			{
			},
			onInsertPath:
			{
			}
		)
		let window = try #require(controller.window)
		defer
		{
			window.close()
		}
		let panes = controller.paneController
		panes.didPresentWindow()
		panes.setSidebarCollapsed(false)
		window.toolbar?.isVisible = true
		let original = state.currentSnapshot
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture"
		))
		model.conversations.selectedConversation = .thread("chat")
		let presentation = PinnedSummaryPresentation(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			ownerIdentity: "fixture",
			sections: ContextSummarySections()
		)
		controller.inspector.renderSummary(
			presentation,
			visible: true
		)
		#expect(controller.inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		)))
		panes.setReviewCollapsed(false)
		window.layoutIfNeeded()
		#expect(!controller.inspector.isGitReviewFocused)
		#expect(!panes.isGitReviewFocused)
		#expect(!panes.split.splitViewItems[0].isCollapsed)
		#expect(!panes.split.splitViewItems[1].isCollapsed)
		#expect(!panes.isReviewCollapsed)
		#expect(window.toolbar?.isVisible == true)
		let detailFrame = controller.inspector.panels.view.convert(
			controller.inspector.panels.view.bounds,
			to: controller.inspector.view
		)
		#expect(abs(detailFrame.minX) < 2)
		#expect(abs(detailFrame.minY) < 2)
		#expect(abs(detailFrame.width - controller.inspector.view.bounds.width) < 2)
		#expect(abs(detailFrame.height - controller.inspector.view.bounds.height) < 2)
		controller.inspector.gitChanges.onToggleExpanded?()
		window.layoutIfNeeded()
		#expect(panes.isGitReviewFocused)
		#expect(panes.split.splitViewItems[1].isCollapsed)
		#expect(window.toolbar?.isVisible == false)
		controller.inspector.gitChanges.onTogglePanel?()
		window.layoutIfNeeded()
		#expect(!panes.isGitReviewFocused)
		#expect(!panes.split.splitViewItems[0].isCollapsed)
		#expect(!panes.split.splitViewItems[1].isCollapsed)
		#expect(!panes.isReviewCollapsed)
		#expect(window.toolbar?.isVisible == true)
		#expect(controller.inspector.isShowingDetails)
		controller.inspector.gitChanges.onToggleExpanded?()
		controller.inspector.showSummary()
		window.layoutIfNeeded()
		#expect(!panes.isGitReviewFocused)
		#expect(!panes.split.splitViewItems[1].isCollapsed)
		#expect(window.toolbar?.isVisible == true)
		#expect(state.currentSnapshot.selectedThreadID == original.selectedThreadID)
		#expect(state.currentSnapshot.draft == original.draft)
		#expect(panes.split.splitViewItems[1].viewController.children.first === controller
			.conversation)
	}

	@Test func inspectorRestoresFocusOnBackOtherDetailAndOwnerChange() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture"
		))
		model.conversations.selectedConversation = .thread("chat")
		func presentation() -> PinnedSummaryPresentation
		{
			PinnedSummaryPresentation(
				WorkspaceSelectors.snapshot(
					model: model,
					now: .distantPast
				),
				ownerIdentity: "fixture",
				sections: ContextSummarySections()
			)
		}
		let first = presentation()
		inspector.renderSummary(
			first,
			visible: true
		)
		let changes = ContextPanelRequest(
			owner: first.owner,
			destination: .changes
		)
		#expect(inspector.open(changes))
		#expect(!inspector.isGitReviewFocused)
		#expect(!inspector.gitChanges.isExpanded)
		inspector.setGitReviewFocused(true)
		#expect(inspector.isGitReviewFocused)
		inspector.setGitReviewFocused(false)
		#expect(inspector.isShowingDetails)
		#expect(inspector.panels.destination == .changes)
		inspector.setGitReviewFocused(true)
		inspector.showSummary()
		#expect(!inspector.isGitReviewFocused)
		#expect(!inspector.isShowingDetails)
		#expect(inspector.open(changes))
		#expect(!inspector.isGitReviewFocused)
		inspector.setGitReviewFocused(true)
		#expect(inspector.open(ContextPanelRequest(
			owner: first.owner,
			destination: .reportedChanges
		)))
		#expect(!inspector.isGitReviewFocused)
		#expect(inspector.open(changes))
		#expect(!inspector.isGitReviewFocused)
		inspector.setGitReviewFocused(true)
		model.conversations.selectedConversation = .thread("different-chat")
		inspector.renderSummary(
			presentation(),
			visible: true
		)
		#expect(!inspector.isGitReviewFocused)
		#expect(!inspector.isShowingDetails)
		#expect(!inspector.open(changes))
	}
}
