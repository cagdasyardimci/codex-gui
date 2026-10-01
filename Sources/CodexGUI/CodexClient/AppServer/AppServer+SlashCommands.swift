import Foundation

extension AppServer
{
	func forkThread(
		id: String,
		expectedDirectory: URL?
	) async throws -> ThreadDetail
	{
		let result = try await request(
			"thread/fork",
			params: [
				"threadId": id,
				"excludeTurns": true,
				"deferGoalContinuation": true,
			]
		)
		guard let thread = result["thread"] as? [String: Any],
				let summary = ThreadSummary(json: thread), summary.id != id,
				let returnedCwd = result["cwd"] as? String, returnedCwd == summary.cwd
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid forked conversation.")
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

	/// Acknowledgement is separate from the compaction turn and item lifecycle.
	func compactThread(id: String) async throws
	{
		_ = try await request(
			"thread/compact/start",
			params: ["threadId": id]
		)
	}

	func startReview(
		threadId: String,
		target: ReviewTarget,
		delivery: ReviewDelivery
	)
		async throws -> ReviewStartResult
	{
		let result = try await request(
			"review/start",
			params: [
				"threadId": threadId,
				"target": target.protocolValue,
				"delivery": delivery.rawValue,
			]
		)
		guard let reviewThreadId = result["reviewThreadId"] as? String,
				!reviewThreadId.isEmpty,
				let rawTurn = result["turn"] as? [String: Any], let turn = CodexTurn(json: rawTurn),
				delivery != .inline || reviewThreadId == threadId
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid review turn.")
		}
		return ReviewStartResult(
			reviewThreadId: reviewThreadId,
			turn: turn
		)
	}

	/// Experimental in 0.153.2; connect() explicitly negotiates experimentalApi.
	func collaborationModes() async throws -> [CollaborationModePreset]
	{
		let result = try await request(
			"collaborationMode/list",
			params: [:]
		)
		guard let rawPresets = result["data"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Codex did not return collaboration modes.")
		}
		let presets = rawPresets.compactMap(CollaborationModePreset.init(json:))
		guard presets.count == rawPresets.count
		else
		{
			throw AppServerError.protocolError("Codex returned invalid collaboration modes.")
		}
		return presets
	}

	/// Updates subsequent turns without starting a model turn or submitting a prompt.
	func updateThreadSettings(
		id: String,
		settings: ThreadSettingsUpdate
	) async throws
	{
		var parameters = settings.protocolValue
		parameters["threadId"] = id
		_ = try await request(
			"thread/settings/update",
			params: parameters
		)
	}
}
