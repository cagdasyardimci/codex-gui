import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnSummaryPreviewLoadingTests
{
	@Test func hoveringDebouncesPreviewLoadingAndDismissalCancelsIt() async throws
	{
		let rail = TurnNavigationRail()
		let first = ConversationTurnSummary(
			turnID: "first",
			entryID: "first:reference",
			title: "Earlier turn",
			reply: "",
			isContentLoaded: false
		)
		let last = ConversationTurnSummary(
			turnID: "last",
			entryID: "last:reference",
			title: "Earlier turn",
			reply: "",
			isContentLoaded: false
		)
		var loaded: [String] = []
		rail.onLoadTurnPreview =
		{
			loaded.append($0)
		}
		rail.requestTurnPreview(first)
		try await Task.sleep(for: .milliseconds(30))
		rail.requestTurnPreview(last)
		#expect(loaded.isEmpty)
		try await Task.sleep(for: .milliseconds(120))
		#expect(loaded == ["last"])
		rail.requestTurnPreview(first)
		rail.dismissPreview()
		try await Task.sleep(for: .milliseconds(120))
		#expect(loaded == ["last"])
	}

	@Test func previewSkeletonIsReplacedByCachedContentWithoutLoadingTheTranscript()
	{
		let reference = ConversationTurnReference(
			id: "turn",
			status: "completed"
		)
		let unloaded = ConversationTurnSummary.navigation(
			references: [reference],
			loaded: []
		)
		let preview = TurnSummaryPreview(
			summary: unloaded[0],
			bookmarked: false
		)
		#expect(preview.isLoading)
		#expect(preview.cardHeight == 100)
		let cached = ConversationTurnPreview(
			turnID: "turn",
			entryID: "turn:request",
			title: "The request",
			reply: "The reply"
		)
		let summaries = ConversationTurnSummary.navigation(
			references: [reference],
			loaded: [],
			cached: [cached]
		)
		preview.render(summaries[0])
		#expect(!preview.isLoading)
		#expect(!summaries[0].isContentLoaded)
		#expect(summaries[0].isPreviewLoaded)
		#expect(summaries[0].reply == "The reply")
		#expect(summaries[0].entryID == "turn:reference")
	}

}
