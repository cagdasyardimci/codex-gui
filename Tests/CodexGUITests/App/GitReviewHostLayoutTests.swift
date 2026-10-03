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
				sections: ContextSummarySelector.sections(
					model: model,
					chatID: "chat"
				)
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
