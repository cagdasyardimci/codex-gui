import Foundation

extension ConversationContentReducer
{
	static func reconcileReportedGitTurn(
		content: inout ConversationProjection,
		trustLoadedOrder: Bool = false
	)
	{
		guard let candidate = ConversationReportedGitTurn.latest(in: content.loadedTurns)
		else
		{
			return
		}
		admitReportedGitTurn(
			candidate,
			content: &content,
			trustLoadedOrder: trustLoadedOrder,
			allowUnorderedAdvance: false
		)
	}

	static func recordReportedGitTurn(
		_ turnID: String,
		content: inout ConversationProjection,
		allowUnorderedAdvance: Bool
	)
	{
		let timing = content.content.turnTimings[turnID]
		admitReportedGitTurn(
			ConversationReportedGitTurn(
				id: turnID,
				startedAt: timing?.startedAt,
				completedAt: timing?.completedAt
			),
			content: &content,
			trustLoadedOrder: false,
			allowUnorderedAdvance: allowUnorderedAdvance
		)
	}

	private static func admitReportedGitTurn(
		_ candidate: ConversationReportedGitTurn,
		content: inout ConversationProjection,
		trustLoadedOrder: Bool,
		allowUnorderedAdvance: Bool
	)
	{
		content.didReconcileReportedGitTurn = true
		content.content.hasResolvedReportedGitTurn = true
		content.content.latestReportedGitTurn = content.content.latestReportedGitTurn?.admitting(
			candidate,
			references: content.turnReferences,
			loadedTurns: content.loadedTurns,
			trustLoadedOrder: trustLoadedOrder,
			allowUnorderedAdvance: allowUnorderedAdvance
		) ?? candidate
	}
}
