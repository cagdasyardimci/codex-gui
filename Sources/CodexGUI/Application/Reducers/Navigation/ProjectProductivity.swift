import Foundation

/// Pure project-local request and navigation transformations.
enum ProjectProductivity
{
	/// Inserts inspected prompt instructions into the editable draft. Selection alone sends
	/// nothing.
	static func insertSavedPrompt(
		context: ProjectContext,
		id: String,
		into draft: String
	) -> String?
	{
		guard let prompt = context.savedPrompts.first(where:
			{
				$0.id == id
			})
		else
		{
			return nil
		}
		if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			return prompt.instructions
		}
		return draft + "\n\n" + prompt.instructions
	}

	static func toggledBookmark(
		context: ProjectContext,
		bookmark: ConversationBookmark
	) -> ProjectContext
	{
		var updated = context
		if let index = updated.bookmarks.firstIndex(where:
			{
				let matchesIdentity = $0.id == bookmark.id
				let matchesLocation = $0.threadID == bookmark.threadID
					&& $0.turnID == bookmark.turnID
					&& $0.itemID == bookmark.itemID
					&& $0.filePath == bookmark.filePath
				return matchesIdentity || matchesLocation
			})
		{
			updated.bookmarks.remove(at: index)
		}
		else
		{
			updated.bookmarks.append(bookmark)
		}
		return updated
	}

	static func navigationTargets(threads: [SearchableThread]) -> [ConversationJumpTarget]
	{
		threads.flatMap(ConversationNavigation.targets(in:))
	}

	/// Builds request text from the draft and only context items the user marked for inclusion.
	static func requestText(
		context: ProjectContext,
		draft: String
	) -> String
	{
		let selectedContext = context.includedContextText
		guard !selectedContext.isEmpty
		else
		{
			return draft
		}
		return "\(draft)\n\nProject context selected for this request:\n\(selectedContext)"
	}

	static func resolvedSkill(
		context: ProjectContext,
		in catalog: SkillCatalog?
	) -> SkillReference?
	{
		guard let selected = context.selectedSkill, let catalog
		else
		{
			return nil
		}
		let matching = catalog.skills.filter
		{
			$0.name == selected.name && $0.enabled
		}
		let skill =
			matching.first
				{
					$0.path == selected.path
				}
				?? (matching.count == 1 ? matching[0] : nil)
		guard let skill
		else
		{
			return nil
		}
		return SkillReference(
			name: skill.name,
			path: skill.path
		)
	}

	static func skillWarning(
		context: ProjectContext,
		in catalog: SkillCatalog?
	) -> String?
	{
		guard let selected = context.selectedSkill
		else
		{
			return nil
		}
		guard let catalog
		else
		{
			return "Selected skill \(selected.name) could not be checked against the current skill "
				+ "list."
		}
		guard resolvedSkill(
			context: context,
			in: catalog
		) != nil
		else
		{
			if !catalog.errors.isEmpty
			{
				return "Could not confirm selected skill \(selected.name): skill discovery was "
					+ "incomplete."
			}
			return "Selected skill \(selected.name) is unavailable or disabled for this project."
		}
		return nil
	}
}
