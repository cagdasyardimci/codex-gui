import Foundation

/// Prepares skill search and localized ordering until the exact catalog or locale changes.
struct SlashCommandMenuCatalog
{
	private struct SearchableSkill
	{
		let skill: AvailableSkill
		let normalizedName: String
		let normalizedDisplayName: String?
		let sourceIndex: Int
	}

	private var sourceSkills: [AvailableSkill] = []
	private var localeIdentifier: String?
	private var searchableSkills: [SearchableSkill] = []
	private var commandPrefix: String?
	private var skillPrefix: String?
	private var commands: [SlashCommandDescriptor] = []
	private var skills: [AvailableSkill] = []
	private(set) var preparationCount = 0
	private(set) var skillSearchCount = 0

	mutating func invalidateLocale()
	{
		localeIdentifier = nil
	}

	mutating func matching(
		prefix: String,
		availableSkills: [AvailableSkill],
		localeIdentifier: String
	) -> (commands: [SlashCommandDescriptor], skills: [AvailableSkill])
	{
		let catalogNeedsPreparation = !Self.sameText(
			self.localeIdentifier,
			localeIdentifier
		)
			|| !Self.sameSkills(
				sourceSkills,
				availableSkills
			)
		if catalogNeedsPreparation
		{
			prepare(
				availableSkills,
				localeIdentifier: localeIdentifier
			)
		}

		let normalizedPrefix = prefix.lowercased()
		if !Self.sameText(
			commandPrefix,
			normalizedPrefix
		)
		{
			commandPrefix = normalizedPrefix
			commands = SlashCommandRegistry.matching(prefix: normalizedPrefix)
		}
		if !Self.sameText(
			skillPrefix,
			normalizedPrefix
		)
		{
			skillPrefix = normalizedPrefix
			skills = searchableSkills.compactMap
			{
				entry in
				guard normalizedPrefix.isEmpty || entry.normalizedName.hasPrefix(normalizedPrefix)
					|| (entry.normalizedDisplayName?.hasPrefix(normalizedPrefix) ?? false)
				else
				{
					return nil
				}
				return entry.skill
			}
			skillSearchCount += 1
		}
		return (commands, skills)
	}

	private mutating func prepare(
		_ skills: [AvailableSkill],
		localeIdentifier: String
	)
	{
		sourceSkills = skills
		self.localeIdentifier = localeIdentifier
		skillPrefix = nil

		searchableSkills = skills.enumerated().compactMap
		{
			index, skill -> SearchableSkill? in
			guard skill.enabled
			else
			{
				return nil
			}
			return SearchableSkill(
				skill: skill,
				normalizedName: skill.name.lowercased(),
				normalizedDisplayName: skill.displayName?.lowercased(),
				sourceIndex: index
			)
		}
		searchableSkills.sort
		{
			left, right in
			let leftDisplayName = left.skill.displayName ?? left.skill.name
			let rightDisplayName = right.skill.displayName ?? right.skill.name
			let order = leftDisplayName.localizedStandardCompare(rightDisplayName)
			return order == .orderedSame
				? left.sourceIndex < right.sourceIndex : order == .orderedAscending
		}
		preparationCount += 1
	}

	static func sameSkills(
		_ left: [AvailableSkill],
		_ right: [AvailableSkill]
	) -> Bool
	{
		left.count == right.count && zip(
			left,
			right
		).allSatisfy
		{
			left, right in
			left.enabled == right.enabled
				&& sameText(
					left.name,
					right.name
				)
				&& sameText(
					left.description,
					right.description
				)
				&& sameText(
					left.path,
					right.path
				)
				&& sameText(
					left.scope,
					right.scope
				)
				&& sameText(
					left.displayName,
					right.displayName
				)
				&& sameText(
					left.shortDescription,
					right.shortDescription
				)
				&& sameText(
					left.defaultPrompt,
					right.defaultPrompt
				)
		}
	}

	static func sameText(
		_ left: String?,
		_ right: String?
	) -> Bool
	{
		switch (left, right)
		{
		case (nil, nil): true
		case (.some(let left), .some(let right)): left.utf8.elementsEqual(right.utf8)
		default: false
		}
	}
}
