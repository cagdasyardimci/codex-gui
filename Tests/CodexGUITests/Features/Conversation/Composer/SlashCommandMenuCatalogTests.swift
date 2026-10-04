import Foundation
import Testing

@testable import CodexGUI

struct SlashCommandMenuCatalogTests
{
	@Test func preparedCatalogReusesSortingAndSearchWhileMatchingThePreviousOrdering() throws
	{
		let skills = try ["Tool 10", "tool 2", "Tool 1", "Café", "Cafe\u{0301}", "🧭 Tool"].map
		{
			try skill(
				name: $0,
				displayName: $0,
				path: "/skills/\($0)"
			)
		} + [skill(
			name: "Disabled",
			enabled: false
		)]
		var catalog = SlashCommandMenuCatalog()
		for prefix in ["", "TO", "tool", "ca", "cafe\u{0301}", "🧭", "not-found", ""]
		{
			let matches = catalog.matching(
				prefix: prefix,
				availableSkills: skills,
				localeIdentifier: Locale.current.identifier
			)
			#expect(matches.commands == SlashCommandRegistry.matching(prefix: prefix))
			let expected = previousMatches(
				skills,
				prefix: prefix
			)
			#expect(SlashCommandMenuCatalog.sameSkills(
				matches.skills,
				expected
			))
			let searches = catalog.skillSearchCount
			_ = catalog.matching(
				prefix: prefix,
				availableSkills: skills,
				localeIdentifier: Locale.current.identifier
			)
			#expect(catalog.skillSearchCount == searches)
			#expect(catalog.preparationCount == 1)
		}
	}

	@Test func exactUnicodeChangesRefreshEverySkillOutputField() throws
	{
		let original = try skill(
			name: "café",
			displayName: "Café",
			path: "/skills/café",
			description: "Café description",
			scope: "café",
			shortDescription: "Café summary",
			defaultPrompt: "Café prompt"
		)
		let replacement = try skill(
			name: "cafe\u{0301}",
			displayName: "Cafe\u{0301}",
			path: "/skills/cafe\u{0301}",
			description: "Cafe\u{0301} description",
			scope: "cafe\u{0301}",
			shortDescription: "Cafe\u{0301} summary",
			defaultPrompt: "Cafe\u{0301} prompt"
		)
		#expect(original == replacement)
		#expect(!SlashCommandMenuCatalog.sameSkills(
			[original],
			[replacement]
		))
		var catalog = SlashCommandMenuCatalog()
		_ = catalog.matching(
			prefix: "caf",
			availableSkills: [original],
			localeIdentifier: Locale.current.identifier
		)
		let matches = catalog.matching(
			prefix: "caf",
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
		let removed = catalog.matching(
			prefix: "caf",
			availableSkills: [],
			localeIdentifier: Locale.current.identifier
		)
		#expect(removed.skills.isEmpty)
	}

	@Test func localeIdentifierAndExplicitInvalidationRebuildLocalizedOrdering() throws
	{
		let skills = try [skill(name: "Tool 10"), skill(name: "Tool 2")]
		var catalog = SlashCommandMenuCatalog()
		_ = catalog.matching(
			prefix: "",
			availableSkills: skills,
			localeIdentifier: "first"
		)
		_ = catalog.matching(
			prefix: "",
			availableSkills: skills,
			localeIdentifier: "second"
		)
		#expect(catalog.preparationCount == 2)
		catalog.invalidateLocale()
		let matches = catalog.matching(
			prefix: "",
			availableSkills: skills,
			localeIdentifier: "second"
		)
		#expect(catalog.preparationCount == 3)
		#expect(SlashCommandMenuCatalog.sameSkills(
			matches.skills,
			previousMatches(
				skills,
				prefix: ""
			)
		))
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
