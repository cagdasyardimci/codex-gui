import Foundation

/// Editing-turn identity outlives transcript residency without retaining another patch copy.
struct ConversationReportedGitTurn: Equatable, Sendable
{
	let id: String
	var startedAt: Date? = nil
	var completedAt: Date? = nil

	static func latest(in turns: [CodexTurn]) -> Self?
	{
		guard let turn = turns.last(where:
			{
				$0.items.contains
				{
					$0.type == "fileChange" && $0.status == "completed"
				}
			})
		else
		{
			return nil
		}
		return Self(
			id: turn.id,
			startedAt: turn.startedAt,
			completedAt: turn.completedAt
		)
	}

	func admitting(
		_ candidate: Self,
		references: [ConversationTurnReference],
		loadedTurns: [CodexTurn],
		trustLoadedOrder: Bool,
		allowUnorderedAdvance: Bool
	) -> Self
	{
		if candidate.id == id
		{
			return Self(
				id: id,
				startedAt: candidate.startedAt ?? startedAt,
				completedAt: candidate.completedAt ?? completedAt
			)
		}
		// Reference and canonical history order are authoritative; opaque IDs carry no order.
		if let currentIndex = references.firstIndex(where:
			{
				$0.id == id
			}),
			let candidateIndex = references.firstIndex(where:
				{
					$0.id == candidate.id
				})
		{
			return candidateIndex > currentIndex ? candidate : self
		}
		if trustLoadedOrder,
			let currentIndex = loadedTurns.firstIndex(where:
			{
				$0.id == id
			}),
			let candidateIndex = loadedTurns.firstIndex(where:
			{
				$0.id == candidate.id
			})
		{
			return candidateIndex > currentIndex ? candidate : self
		}
		if let startedAt, let candidateStart = candidate.startedAt, candidateStart != startedAt
		{
			return candidateStart > startedAt ? candidate : self
		}
		if self.startedAt == nil, candidate.startedAt == nil,
			let completedAt, let candidateCompletion = candidate.completedAt,
			candidateCompletion != completedAt
		{
			return candidateCompletion > completedAt ? candidate : self
		}
		// An accepted live start can advance an undated turn. An older history read cannot.
		return allowUnorderedAdvance ? candidate : self
	}
}
