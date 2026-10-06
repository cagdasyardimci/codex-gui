import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabGitReviewIntegrationTests
{
	@Test func repeatedSummaryGeometryKeepsExpandedToolsSizing()
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: ConversationViewController(),
			inspector: inspector,
			layoutStore: nil
		)
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
			ownerIdentity: "fixture"
		)
		inspector.onDetailGeometryChange =
		{
			wide in panes.setWorkspaceFilesExpanded(wide)
		}
		inspector.renderSummary(
			presentation,
			visible: true
		)
		panes.openToolsPane()
		let reviewPane = panes.split.splitViewItems[2]
		#expect(inspector.isShowingTools)
		#expect(reviewPane.maximumThickness == NSSplitViewItem.unspecifiedDimension)
		reviewPane.isCollapsed = false
		panes.toggleToolsExpanded()
		#expect(panes.isToolsExpanded)

		for _ in 0 ..< 2
		{
			inspector.renderSummary(
				presentation,
				visible: true
			)
			#expect(reviewPane.maximumThickness == NSSplitViewItem.unspecifiedDimension)
			#expect(panes.isToolsExpanded)
			#expect(inspector.isShowingTools)
		}
	}

	@Test func openingPaneSelectsToolContentBeforeStartingTransition()
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: ConversationViewController(),
			inspector: inspector,
			layoutStore: nil
		)
		let review = NSViewController()
		review.view = NSView()
		var configured = false
		panes.openToolsPane
		{
			#expect(inspector.isShowingTools)
			#expect(inspector.toolsTabs.selectedTabID != nil)
			inspector.toolsTabs.showChanges(review)
			configured = true
		}
		#expect(configured)
		#expect(inspector.toolsTabs.isChangesSelected)
		#expect(review.parent === inspector.toolsTabs)
	}

	@Test func changesTileKeepsReviewAcrossBlankAndConversationTabs() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		_ = tabs.view
		tabs.openNewTab()
		var openCount = 0
		tabs.onOpenChanges =
		{
			openCount += 1
		}
		let tile = try #require(button(
			"Changes",
			in: tabs.view
		))
		#expect(tile.isEnabled)
		tile.performClick(nil)
		#expect(openCount == 1)

		let review = NSViewController()
		review.view = NSView()
		tabs.showChanges(review)
		let changesID = try #require(tabs.changesTabID)
		#expect(tabs.isChangesSelected)
		#expect(review.parent === tabs)
		#expect(!review.view.isHidden)
		#expect(button(
			"Changes 1",
			in: tabs.tabBarView
		)?.title == "Changes")

		tabs.openNewTab()
		#expect(!tabs.isChangesSelected)
		#expect(tabs.changesTabID == changesID)
		#expect(review.parent === tabs)
		#expect(review.view.isHidden)
		try #require(button(
			"Changes 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isChangesSelected)
		#expect(!review.view.isHidden)

		tabs.setExpanded(true)
		try #require(button(
			"Chat: New chat",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(tabs.isConversationSelected)
		#expect(tabs.changesTabID == changesID)
		#expect(review.view.isHidden)
		try #require(button(
			"Changes 1",
			in: tabs.tabBarView
		)).performClick(nil)
		#expect(!tabs.isConversationSelected)
		#expect(!review.view.isHidden)
	}

	@Test func reviewMovesBetweenToolTabAndDetailThenClosesWithTab() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
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
		inspector.renderSummary(
			presentation,
			visible: true
		)
		inspector.showToolsPane()
		inspector.showGitChangesInSelectedToolTab(
			owner: presentation.owner,
			lastTurnID: nil,
			baselineRevision: 0,
			baselineFailure: nil
		)
		defer
		{
			inspector.gitChanges.close()
		}
		#expect(inspector.gitChanges.parent === inspector.toolsTabs)
		#expect(inspector.gitChanges.runtime.state.isOpen)
		#expect(!inspector.gitChanges.showsInternalChangesTab)

		inspector.toolsTabs.openNewTab()
		#expect(inspector.gitChanges.runtime.state.isOpen)
		#expect(inspector.gitChanges.parent === inspector.toolsTabs)
		try #require(button(
			"Changes 1",
			in: inspector.toolsTabs.tabBarView
		))
		.performClick(nil)
		#expect(inspector.gitChanges.runtime.state.isOpen)
		#expect(!inspector.gitChanges.view.isHidden)

		#expect(inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		)))
		#expect(inspector.gitChanges.parent === inspector.panels)
		#expect(inspector.gitChanges.showsInternalChangesTab)
		#expect(!inspector.gitChanges.view.isHidden)
		inspector.showToolsPane()
		#expect(inspector.gitChanges.parent === inspector.toolsTabs)
		#expect(!inspector.gitChanges.showsInternalChangesTab)
		#expect(inspector.gitChanges.runtime.state.isOpen)
		let changesTabID = try #require(inspector.toolsTabs.changesTabID)
		inspector.closeToolsPane()
		#expect(!inspector.isShowingDetails)
		#expect(!inspector.summary.view.isHidden)
		#expect(inspector.panels.view.isHidden)
		#expect(inspector.gitChanges.parent === inspector.toolsTabs)
		#expect(inspector.gitChanges.runtime.state.isOpen)
		#expect(inspector.toolsTabs.changesTabID == changesTabID)
		inspector.showToolsPane()
		#expect(inspector.toolsTabs.isChangesSelected)
		#expect(inspector.gitChanges.parent === inspector.toolsTabs)
		#expect(inspector.gitChanges.runtime.state.isOpen)

		try #require(button(
			"Close tab 1",
			in: inspector.toolsTabs.tabBarView
		))
		.performClick(nil)
		#expect(!inspector.gitChanges.runtime.state.isOpen)
		#expect(inspector.toolsTabs.changesTabID == nil)
		#expect(inspector.gitChanges.parent == nil)
		inspector.showGitChangesInSelectedToolTab(
			owner: presentation.owner,
			lastTurnID: nil,
			baselineRevision: 0,
			baselineFailure: nil
		)
		#expect(inspector.gitChanges.runtime.state.isOpen)
		#expect(inspector.toolsTabs.isChangesSelected)
	}

	@Test func summaryCardCapsAtThreeHundredPointsWhileReviewFillsPane() throws
	{
		_ = NSApplication.shared
		let inspector = InspectorViewController()
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
			ownerIdentity: "fixture"
		)
		inspector.view.frame = NSRect(
			x: 0,
			y: 0,
			width: 400,
			height: 700
		)
		inspector.renderSummary(
			presentation,
			visible: true
		)
		inspector.view.layoutSubtreeIfNeeded()
		let card = try #require(inspector.view.subviews.first)
		#expect(abs(card.frame.width - 300) < 1)
		#expect(abs(card.frame.maxX - (inspector.view.bounds.maxX - 8)) < 1)
		#expect(inspector.open(ContextPanelRequest(
			owner: presentation.owner,
			destination: .changes
		)))
		inspector.view.layoutSubtreeIfNeeded()
		#expect(abs(card.frame.width - 400) < 1)
		inspector.showToolsPane()
		inspector.view.layoutSubtreeIfNeeded()
		#expect(abs(inspector.toolsTabs.view.frame.width - 400) < 1)
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		for child in view.subviews
		{
			if let match = button(
				label,
				in: child
			)
			{
				return match
			}
		}
		return nil
	}

	private func textField(
		_ value: String,
		in view: NSView
	) -> NSTextField?
	{
		if let field = view as? NSTextField, field.stringValue == value
		{
			return field
		}
		for child in view.subviews
		{
			if let match = textField(
				value,
				in: child
			)
			{
				return match
			}
		}
		return nil
	}
}
