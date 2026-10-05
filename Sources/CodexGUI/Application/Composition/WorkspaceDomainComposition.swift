import Foundation

/// Accepted domain observations finish all value projections before effects and publication.
@MainActor
enum WorkspaceDomainComposition
{
	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		var result = ConversationReviewComposition.reduceDomainEvent(
			&model,
			event
		)
		let navigation = ContextNavigationReducer.reduceDomainEvent(
			&model,
			event
		)
		result.merge(navigation)
		let commandReduction = ComposerCommandReducer.reduceDomainEvent(
			&model,
			event
		)
		result.merge(commandReduction)

		PreferenceReducer.synchronize(&model)
		return result
	}
}
