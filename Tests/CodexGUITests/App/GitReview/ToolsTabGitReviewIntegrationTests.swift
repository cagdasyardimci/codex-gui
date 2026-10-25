import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabGitReviewIntegrationTests
{

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
