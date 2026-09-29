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
		result.effects.append(contentsOf: navigation.effects)
		result.domainEvents.append(contentsOf: navigation.domainEvents)
		result.presentationCommands.append(contentsOf: navigation.presentationCommands)
		PreferenceReducer.synchronize(&model)
		return result
	}
}
