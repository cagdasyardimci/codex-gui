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

	@Test func projectionsPreserveProviderOrderStableIdentityLimitAndDestinations()
	{
		let sources = ["b", "a", "b", "c", "d"].map
		{
			SummarySourceReference(
				id: $0,
				label: "Label",
				kind: .attachment
			)
		}
		var sections = ContextSummarySections()
		sections.sources = .available(sources)
		sections.availableDestinations.insert(.sources)
		let presentation = PinnedSummaryPresentation(
			snapshot(),
			sections: sections
		)
		#expect(presentation.sourcePreviews.map(\.id) == ["b", "a", "c"])
		#expect(presentation.request(.sources)?.owner == presentation.owner)
		#expect(presentation.request(.subagents) == nil)
		let limited = PinnedSummaryPresentation(
			snapshot(),
			sections: sections,
			sourcePreviewLimit: 1
		)
		#expect(limited.sourcePreviews.map(\.id) == ["b"])
		#expect(sections.sources.value?.count == 5)
	}

	@Test func unavailableZeroEmptyAndFailureRetainingKnownDataRemainDistinct()
	{
		let zero = SummaryChangeTotals(
			additions: 0,
			deletions: 0
		)
		let available = SummarySection.available(zero)
		let unavailable = SummarySection<SummaryChangeTotals>.unavailable("Unavailable")
		#expect(available.value == zero)
		#expect(unavailable.value == nil)
		#expect(available != unavailable)
		let failure = SummarySection.failed(
			"Refresh failed",
			previous: zero
		)
		#expect(failure.value == zero)
		#expect(failure.message == "Refresh failed")
		let empty = SummarySection<[SummarySourceReference]>.available([])
		#expect(empty.value?.isEmpty == true)
	}

	@Test func mixedPreviewsRetainAttachmentNamesPathsAndGroupedConfigurableLimit() throws
	{
		let attachment = SummarySourceReference(
			id: "image",
			label: "diagram.png",
			kind: .attachment,
			thumbnailPath: "/sample/diagram.png",
			detailRecordID: "image"
		)
		var sections = ContextSummarySections()
		sections.sources = .available([
			attachment,
			SummarySourceReference(
				id: "tool-a",
				label: "Listed artifacts once",
				kind: .tool
			),
			SummarySourceReference(
				id: "tool-b",
				label: "Listed chats once",
				kind: .tool
			),
			SummarySourceReference(
				id: "search",
				label: "Searched once",
				kind: .web
			),
			SummarySourceReference(
				id: "unknown",
				label: "Unknown image",
				kind: .attachment
			)
		])
		sections.availableDestinations.insert(.sources)
		let presentation = PinnedSummaryPresentation(
			snapshot(),
			sections: sections
		)
		#expect(presentation.sourcePreviews.map(\.label)
			== ["diagram.png", "ChatGPT App Tools", "Web search"])
		let image = try #require(presentation.sourcePreviews.first)
		#expect(image.thumbnailPath == attachment.thumbnailPath)
		#expect(presentation.sourceRequest(for: image)?.recordID == attachment.id)
		let expanded = PinnedSummaryPresentation(
			snapshot(),
			sections: sections,
			sourcePreviewLimit: 4
		)
		let unknown = try #require(expanded.sourcePreviews.last)
		#expect(expanded.sourceRequest(for: unknown) == nil)
		#expect(presentation.sourceRequest(for: unknown) == nil)
		let hidden = PinnedSummaryPresentation(
			snapshot(),
			sections: sections,
			sourcePreviewLimit: -1
		)
		#expect(hidden.sourcePreviews.isEmpty)
		#expect(hidden.sections.sources.value?.count == 5)
	}

	@Test func togglingIsChatScopedAndHiddenUpdatesSurviveReveal()
	{
		var snapshot = snapshot()
		let first = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		var visibility = PinnedSummaryVisibility()
		visibility.toggle(for: first)
		#expect(!visibility.isVisible(for: first))
		var reconciliation = ContextSummaryReconciliation()
		reconciliation.select(first)
		var sections = ContextSummarySections()
		sections.sources = .available([SummarySourceReference(
			id: "source",
			label: "Source",
			kind: .web
		)])
		let hiddenUpdateAccepted = reconciliation.accept(ContextSummaryUpdate(
			owner: first,
			revision: 1,
			sections: sections
		))
		#expect(hiddenUpdateAccepted)
		snapshot.workspaceSelectionEpoch += 1
		let revisited = FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)
		#expect(!visibility.isVisible(for: revisited))
		snapshot = self.snapshot(thread: "another-chat")
		#expect(visibility.isVisible(for: FeaturePresentationOwner(
			snapshot,
			storeIdentity: "store"
		)))
		visibility.toggle(for: first)
		#expect(visibility.isVisible(for: first))
		#expect(reconciliation.sections.sources.value?.first?.id == "source")
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
		#expect(presentation.contextName == "Workspace unavailable")
		#expect(presentation.sourcePreviews.isEmpty)
		#expect(presentation.sections.availableDestinations.isEmpty)
	}
}
