import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct PinnedSummarySourcesTests
{
	@Test func disclosureSurvivesUpdatesAndResetsForANewOwner() throws
	{
		_ = NSApplication.shared
		let controller = PinnedSummaryViewController()
		var sections = sourceSections(count: 4)
		var snapshot = snapshot()
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
		#expect(try disclosure(controller).dispatchConfiguredAction())
		#expect(try disclosure(controller).title == "Sources · 4")
		#expect(sourceNameLabels(controller).isEmpty)
		#expect(!descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}
		.contains
		{
			$0.title == "View all"
		})
		sections = sourceSections(count: 5)
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources · 5")
		#expect(sourceNameLabels(controller).isEmpty)
		#expect(try disclosure(controller).dispatchConfiguredAction())
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
		#expect(try disclosure(controller).dispatchConfiguredAction())
		snapshot.workspaceSelectionEpoch += 1
		controller.render(PinnedSummaryPresentation(
			snapshot,
			sections: sections
		))
		#expect(try disclosure(controller).title == "Sources")
		#expect(sourceNameLabels(controller).count == 3)
	}

	@Test func addSourceControlRemainsVisibleAndDisabledInBothStates() throws
	{
		_ = NSApplication.shared
		let controller = PinnedSummaryViewController()
		controller.render(PinnedSummaryPresentation(
			snapshot(),
			sections: sourceSections(count: 1)
		))
		let expandedAdd = try addSourceControl(controller)
		#expect(!expandedAdd.isEnabled)
		#expect(!expandedAdd.isHiddenOrHasHiddenAncestor)
		#expect(try disclosure(controller).dispatchConfiguredAction())
		let collapsedAdd = try addSourceControl(controller)
		#expect(!collapsedAdd.isEnabled)
		#expect(!collapsedAdd.isHiddenOrHasHiddenAncestor)
	}

	private func snapshot() -> ConversationSnapshot
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		model.conversations.selectedConversation = .thread("sources-chat")
		return WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		)
	}

	private func sourceSections(count: Int) -> ContextSummarySections
	{
		var sections = ContextSummarySections()
		sections.sources = .available((0 ..< count).map
		{
			SummarySourceReference(
				id: "source-\($0)",
				label: "source-name-\($0).png",
				kind: .attachment
			)
		})
		sections.availableDestinations.insert(.sources)
		return sections
	}

	private func disclosure(_ controller: PinnedSummaryViewController) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityIdentifier() == "pinned-summary-sources-disclosure"
		})
	}

	private func addSourceControl(_ controller: PinnedSummaryViewController) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.accessibilityIdentifier() == "pinned-summary-add-sources"
		})
	}

	private func sourceNameLabels(_ controller: PinnedSummaryViewController) -> [NSTextField]
	{
		descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}.filter
		{
			$0.stringValue.hasPrefix("source-name-")
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
