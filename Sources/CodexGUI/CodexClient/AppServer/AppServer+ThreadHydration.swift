import Foundation

extension AppServer
{
	/// Resume and fork validate checkout identity before reading the returned thread's history.
	func hydrateValidatedThread(
		_ summary: ThreadSummary,
		result: [String: Any],
		expectedDirectory: URL?,
		invalidResponseMessage: String
	) async throws -> ThreadDetail
	{
		guard result["cwd"] as? String == summary.cwd
		else
		{
			throw AppServerError.protocolError(invalidResponseMessage)
		}
		try CheckoutIdentity.validate(
			cwd: summary.cwd,
			expectedDirectory: expectedDirectory
		)
		let page = try await loadTurns(threadId: summary.id)
		return ThreadDetail(
			summary: summary,
			turns: page.turns,
			nextTurnsCursor: page.nextCursor,
			settings: ThreadSettings(json: result)
		)
	}
}
