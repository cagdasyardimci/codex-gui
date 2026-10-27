import Foundation
import Testing

@testable import CodexGUI

struct SlashCommandMenuCatalogTests
{
	@Test func bothSkillPickersMatchNamesAndDescriptions() throws
	{
		let skill = try skill(
			name: "internal-audit",
			displayName: "Workspace Review",
			description: "Check repository conventions",
			shortDescription: "Inspect project guidelines"
		)
		let paletteCommand = PaletteCommand(
			title: skill.displayName ?? skill.name,
			detail: skill.shortDescription ?? skill.description,
			destination: .action("0"),
			searchText: skill.searchText
		)
		var catalog = SlashCommandMenuCatalog()
		for (query, expected) in [
			("", true),
			("AUDIT", true),
			("review", true),
			("conventions", true),
			("guidelines", true),
			("missing", false),
		]
		{
			let matches = catalog.matching(
				prefix: query,
				availableSkills: [skill],
				localeIdentifier: Locale.current.identifier
			)
			#expect((matches.skills == [skill]) == expected)
			#expect(paletteCommand.matches(query) == expected)
		}
	}

	@Test func canonicalChangesInEachSkillFieldInvalidateCachedValues() throws
	{
		let interface = [
			"displayName": "café",
			"shortDescription": "café",
			"defaultPrompt": "café",
		]
		let originalJSON: [String: Any] = [
			"name": "café",
			"description": "café",
			"path": "café",
			"scope": "café",
			"enabled": true,
			"interface": interface,
		]
		let original = try #require(AvailableSkill(json: originalJSON))
		for field in [
			"name",
			"description",
			"path",
			"scope",
			"displayName",
			"shortDescription",
			"defaultPrompt",
		]
		{
			var changed = originalJSON
			if interface[field] != nil
			{
				var changedInterface = interface
				changedInterface[field] = "cafe\u{0301}"
				changed["interface"] = changedInterface
			}
			else
			{
				changed[field] = "cafe\u{0301}"
			}
			let replacement = try #require(AvailableSkill(json: changed))
			#expect(original == replacement)
			var catalog = SlashCommandMenuCatalog()
			_ = catalog.matching(
				prefix: "",
				availableSkills: [original],
				localeIdentifier: Locale.current.identifier
			)
			let matches = catalog.matching(
				prefix: "",
				availableSkills: [replacement],
				localeIdentifier: Locale.current.identifier
			)
			#expect(catalog.preparationCount == 2)
			#expect(SlashCommandMenuCatalog.sameSkills(
				matches.skills,
				[replacement]
			))
			#expect(!SlashCommandMenuCatalog.sameSkills(
				matches.skills,
				[original]
			))
		}
		var disabledJSON = originalJSON
		disabledJSON["enabled"] = false
		let disabled = try #require(AvailableSkill(json: disabledJSON))
		var catalog = SlashCommandMenuCatalog()
		_ = catalog.matching(
			prefix: "",
			availableSkills: [original],
			localeIdentifier: Locale.current.identifier
		)
		#expect(catalog.matching(
			prefix: "",
			availableSkills: [disabled],
			localeIdentifier: Locale.current.identifier
		).skills.isEmpty)
	}

	private func previousMatches(
		_ skills: [AvailableSkill],
		prefix: String
	) -> [AvailableSkill]
	{
		skills.filter
		{
			let matchesName = $0.name.lowercased().hasPrefix(prefix.lowercased())
			let matchesDisplayName = $0.displayName?.lowercased()
				.hasPrefix(prefix.lowercased()) ?? false
			return $0.enabled && (prefix.isEmpty || matchesName || matchesDisplayName)
		}.sorted
		{
			($0.displayName ?? $0.name).localizedStandardCompare($1.displayName ?? $1.name)
				== .orderedAscending
		}
	}

	private func skill(
		name: String,
		displayName: String? = nil,
		path: String = "/skills/example",
		description: String = "Skill description",
		scope: String = "user",
		enabled: Bool = true,
		shortDescription: String? = nil,
		defaultPrompt: String? = nil
	) throws -> AvailableSkill
	{
		var interface: [String: Any] = [:]
		interface["displayName"] = displayName
		interface["shortDescription"] = shortDescription
		interface["defaultPrompt"] = defaultPrompt
		return try #require(AvailableSkill(json: [
			"name": name,
			"description": description,
			"path": path,
			"scope": scope,
			"enabled": enabled,
			"interface": interface,
		]))
	}
}
