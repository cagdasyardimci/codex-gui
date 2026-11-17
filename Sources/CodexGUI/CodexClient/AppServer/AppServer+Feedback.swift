import Foundation

extension AppServer
{
	func submitResultFeedback(
		_ feedback: ResultFeedbackSubmission,
		in directory: URL
	) async throws
	{
		let generation = connectionGeneration
		var uploadStarted = false
		do
		{
			guard directory.isFileURL
			else
			{
				throw AppServerError
					.protocolError("Feedback requires a captured checkout directory.")
			}
			let exists = try await Task.detached(priority: .userInitiated)
			{
				try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
			}.value
			guard exists
			else
			{
				throw AppServerError
					.protocolError("Feedback requires an existing checkout directory.")
			}
			try Task.checkCancellation()
			guard !feedback.target.threadID.isEmpty, !feedback.target.turnID.isEmpty
			else
			{
				throw AppServerError
					.protocolError("Result feedback requires a conversation and turn.")
			}
			let configuration = try await request(
				"config/read",
				params: ["includeLayers": false, "cwd": directory.path]
			)
			guard let config = configuration["config"] as? [String: Any]
			else
			{
				throw AppServerError
					.protocolError("Codex returned an invalid feedback configuration.")
			}
			if let rawFeedback = config["feedback"], !(rawFeedback is NSNull)
			{
				guard let feedbackConfig = rawFeedback as? [String: Any]
				else
				{
					throw AppServerError
						.protocolError("Codex returned an invalid feedback configuration.")
				}
				if let rawEnabled = feedbackConfig["enabled"], !(rawEnabled is NSNull)
				{
					guard let enabled = rawEnabled as? Bool
					else
					{
						throw AppServerError
							.protocolError("Codex returned an invalid feedback configuration.")
					}
					if !enabled
					{
						throw AppServerError
							.requestRejected("Sending feedback is disabled by configuration.")
					}
				}
			}
			try Task.checkCancellation()
			guard generation == connectionGeneration
			else
			{
				throw AppServerError.disconnected
			}
			uploadStarted = true
			let response = try await request(
				"feedback/upload",
				params: [
					"classification": feedback.rating.rawValue,
					"threadId": feedback.target.threadID,
					"includeLogs": false,
					"tags": ["turn_id": feedback.target.turnID],
				]
			)
			guard let reportID = response["threadId"] as? String, !reportID.isEmpty
			else
			{
				throw AppServerError.protocolError("Codex returned an invalid feedback receipt.")
			}
		}
		catch
		{
			throw ResultFeedbackRequestFailure.classify(
				error,
				uploadStarted: uploadStarted
			)
		}
	}
}
