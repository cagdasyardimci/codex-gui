import AppKit
import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct PinnedSummaryPresentationTests
{
	private func snapshot(
		thread: String? = "chat",
		project: String? = "/sample/workspace"
	) -> ConversationSnapshot
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project
		))
		model.conversations.selectedConversation = thread.map(ConversationKey.thread) ?? .newChat
		return WorkspaceSelectors.snapshot(
			model: model,
			now: Date(timeIntervalSince1970: 0)
		)
	}

	@Test func lateUpdatesCannotCrossChatStoreOrSelectionAndRejectOldRevisions()
	{
		let snapshot = snapshot()
		let owner = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		var reconciliation = ContextSummaryReconciliation()
		reconciliation.select(owner)
		var sections = ContextSummarySections()
		sections.changes = .available(SummaryChangeTotals(
			additions: 3,
			deletions: 1
		))
		let update = ContextSummaryUpdate(
			owner: owner,
			revision: 2,
			sections: sections
		)
		let acceptedUpdate = reconciliation.accept(update)
		#expect(acceptedUpdate)
		let replayedUpdateAccepted = reconciliation.accept(update)
		#expect(!replayedUpdateAccepted)
		let olderUpdateAccepted = reconciliation.accept(ContextSummaryUpdate(
			owner: owner,
			revision: 1,
			sections: sections
		))
		#expect(!olderUpdateAccepted)
		let foreign = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "other-store"
		)
		let foreignStoreAccepted = reconciliation.accept(ContextSummaryUpdate(
			owner: foreign,
			revision: 3,
			sections: sections
		))
		#expect(!foreignStoreAccepted)
		var switched = snapshot
		switched.workspaceSelectionEpoch += 1
		let newOwner = FeaturePresentationOwner(
			switched,
			storeIdentity: "store"
		)
		reconciliation.select(newOwner)
		let obsoleteSelectionAccepted = reconciliation.accept(update)
		#expect(!obsoleteSelectionAccepted)
		#expect(reconciliation.sections.changes.value == nil)
	}

	@Test func absentWorkspaceDisablesEveryDestinationAndDiscardsForeignSections()
	{
		var sections = ContextSummarySections()
		sections.sources = .available([SummarySourceReference(
			id: "source",
			label: "Source",
			kind: .web
		)])
		sections.availableDestinations = Set(ContextPanelDestination.allCases)
		let presentation = PinnedSummaryPresentation(
			snapshot(project: nil),
			sections: sections
		)
		#expect(presentation.contextName.isEmpty)
		#expect(presentation.sourcePreviews.isEmpty)
		#expect(presentation.sections.availableDestinations.isEmpty)
	}

	@Test func changesActionStillRoutesWithTheRenderedOwner() throws
	{
		_ = NSApplication.shared
		let snapshot = snapshot()
		let controller = PinnedSummaryViewController()
		var sections = ContextSummarySections()
		sections.changes = .available(SummaryChangeTotals(
			additions: 2,
			deletions: 1
		))
		sections.availableDestinations = [.changes]
		let presentation = PinnedSummaryPresentation(
			snapshot,
			sections: sections
		)
		controller.render(presentation)
		var request: ContextPanelRequest?
		controller.onNavigate =
		{
			request = $0
		}
		let changes = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Changes"
		})
		try #require(changes.dispatchConfiguredAction())
		#expect(request?.destination == .changes)
		#expect(request?.owner == presentation.owner)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
