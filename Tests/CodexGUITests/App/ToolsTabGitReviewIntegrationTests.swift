import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabGitReviewIntegrationTests
{
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

}
