import Foundation

extension AppServer
{
	func models() async throws -> [ModelOption]
	{
		var modelOptions: [ModelOption] = []
		var cursorTracker = PaginationCursorTracker(
			repeatedCursorMessage: "Codex repeated the model list cursor."
		)
		var cursor: String?
		repeat
		{
			var parameters: [String: Any] = ["limit": 100]
			if let cursor
			{
				parameters["cursor"] = cursor
			}
			let result = try await request(
				"model/list",
				params: parameters
			)
			modelOptions += (result["data"] as? [[String: Any]] ?? [])
				.compactMap(ModelOption.init(json:))
			cursor = try cursorTracker.advance(to: result["nextCursor"] as? String)
		}
		while cursor != nil
		return modelOptions
	}

	func skills(for directory: URL) async throws -> SkillCatalog
	{
		let cwd = directory.standardizedFileURL.path
		let result = try await request(
			"skills/list",
			params: ["cwds": [cwd]]
		)
		guard let entries = result["data"] as? [[String: Any]],
				let entry = entries.first(where:
				{
					$0["cwd"] as? String == cwd
				}),
				let rawSkills = entry["skills"] as? [[String: Any]],
				let rawErrors = entry["errors"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Codex did not return skills for this project.")
		}
		let skills = rawSkills.compactMap(AvailableSkill.init(json:))
		let errors = rawErrors.compactMap(SkillDiscoveryError.init(json:))
		guard skills.count == rawSkills.count, errors.count == rawErrors.count
		else
		{
			throw AppServerError.protocolError("Codex returned invalid skill metadata.")
		}
		return SkillCatalog(
			skills: skills,
			errors: errors
		)
	}
}
