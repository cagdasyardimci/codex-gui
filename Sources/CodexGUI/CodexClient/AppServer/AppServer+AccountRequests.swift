import Foundation

extension AppServer
{
	func accountStatus() async throws -> AccountStatus
	{
		let result = try await request(
			"account/read",
			params: ["refreshToken": false]
		)
		let account = result["account"] as? [String: Any]
		return AccountStatus(
			type: account?["type"] as? String,
			email: account?["email"] as? String,
			requiresOpenAIAuth: result["requiresOpenaiAuth"] as? Bool ?? true
		)
	}

	func accountDescription() async throws -> String
	{
		try await accountStatus().description
	}

	func startBrowserLogin() async throws -> URL
	{
		let result = try await request(
			"account/login/start",
			params: ["type": "chatgpt"]
		)
		guard let urlString = result["authUrl"] as? String, let url = URL(string: urlString)
		else
		{
			throw AppServerError.protocolError("Codex did not return a browser sign-in URL.")
		}
		return url
	}

	func rateLimits() async throws -> AccountRateLimitsSnapshot
	{
		let result = try await request(
			"account/rateLimits/read",
			params: [:]
		)
		guard let snapshot = AccountRateLimitsSnapshot(json: result)
		else
		{
			throw AppServerError.protocolError("Codex did not return a rate-limit snapshot.")
		}
		return snapshot
	}
}
