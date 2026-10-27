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
		guard let cwd = result["cwd"] as? String, cwd.hasPrefix("/"),
				summary.cwd.hasPrefix("/")
		else
		{
			throw AppServerError.protocolError(invalidResponseMessage)
		}
		try CheckoutIdentity.validate(
			cwd: cwd,
			expectedDirectory: URL(fileURLWithPath: summary.cwd)
		)
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
