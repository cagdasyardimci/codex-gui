import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct GitSummaryReconciliationTests
{
	private func model(chat: String = "chat") -> WorkspaceModel
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/example/checkout"
		))
		model.conversations.selectedConversation = .thread(chat)
		return model
	}

	private func owner(_ model: WorkspaceModel) -> FeaturePresentationOwner
	{
		FeaturePresentationOwner(
			WorkspaceSelectors.snapshot(
				model: model,
				now: .distantPast
			),
			storeIdentity: "store"
		)
	}

	private func projection(
		owner: FeaturePresentationOwner,
		revision: Int,
		scope: GitComparisonScope = .uncommitted,
		snapshotScope: GitComparisonScope? = .uncommitted,
		id: String? = "comparison",
		totals: SummarySection<SummaryChangeTotals>? = nil
	) -> GitReviewSummaryProjection
	{
		GitReviewSummaryProjection(
			owner: owner,
			revision: revision,
			scope: scope,
			comparisonID: id,
			snapshotScope: snapshotScope,
			totals: totals ?? .available(SummaryChangeTotals(
				additions: 2,
				deletions: 1
			))
		)
	}

	@Test func rejectsOldOwnerRevisionScopeAndComparisonProjection()
	{
		let model = model()
		let owner = owner(model)
		var sink = GitSummaryReconciliation()
		sink.select(owner)
		let current = projection(
			owner: owner,
			revision: 4
		)
		let accepted = sink.accept(
			current,
			canonical: current
		)
		#expect(accepted)
		let older = projection(
			owner: owner,
			revision: 3
		)
		let olderAccepted = sink.accept(
			older,
			canonical: older
		)
		#expect(!olderAccepted)
		let wrongScope = projection(
			owner: owner,
			revision: 5,
			scope: .staged
		)
		let scopeAccepted = sink.accept(
			wrongScope,
			canonical: wrongScope
		)
		#expect(!scopeAccepted)
		for incomplete in [
			projection(
				owner: owner,
				revision: 5,
				id: nil
			),
			projection(
				owner: owner,
				revision: 5,
				snapshotScope: nil
			)
		]
		{
			let accepted = sink.accept(
				incomplete,
				canonical: incomplete
			)
			#expect(!accepted)
			#expect(sink.projection == current)
		}
		let oldComparison = projection(
			owner: owner,
			revision: 5,
			id: "old-comparison"
		)
		let comparisonAccepted = sink.accept(
			oldComparison,
			canonical: current
		)
		#expect(!comparisonAccepted)
		var switched = model
		switched.conversations.selectedConversation = .thread("other")
		let foreign = projection(
			owner: self.owner(switched),
			revision: 6
		)
		let foreignAccepted = sink.accept(
			foreign,
			canonical: foreign
		)
		#expect(!foreignAccepted)
		#expect(sink.projection == current)
	}

	@Test func closureClearsTotalsAndSameOwnerOldLifetimeCannotRepopulate()
	{
		let owner = owner(model())
		var sink = GitSummaryReconciliation()
		sink.select(owner)
		let current = projection(
			owner: owner,
			revision: 4
		)
		let accepted = sink.accept(
			current,
			canonical: current
		)
		#expect(accepted)
		let closed = sink.accept(
			nil,
			canonical: nil
		)
		#expect(closed)
		#expect(sink.section(for: owner).value == nil)
		#expect(sink.scopeDescription == nil)
		let oldAccepted = sink.accept(
			current,
			canonical: nil
		)
		#expect(!oldAccepted)
		let repeatedAccepted = sink.accept(
			current,
			canonical: current
		)
		#expect(!repeatedAccepted)
		let newer = projection(
			owner: owner,
			revision: 6
		)
		let reopened = sink.accept(
			newer,
			canonical: newer
		)
		#expect(reopened)
		#expect(sink.section(for: owner).value == current.totals.value)
	}
}
