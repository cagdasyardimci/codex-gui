import Foundation

/// Content and review owners compose their accepted transitions before one publication.
@MainActor
enum ConversationReviewComposition
{
	static func reduceDomainEvent(
		_ model: inout WorkspaceModel,
		_ event: WorkspaceDomainEvent
	) -> WorkspaceReduction
	{
		var result = ConversationReducer.reduceDomainEvent(
			&model,
			event
		)
		let review = ReviewReducer.reduceDomainEvent(
			&model,
			event
		)
		result.effects.append(contentsOf: review.effects)
		result.domainEvents.append(contentsOf: review.domainEvents)
		result.presentationCommands.append(contentsOf: review.presentationCommands)
		return result
	}
}
