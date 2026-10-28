import AppKit

@MainActor
extension ConversationViewController
{
	func presentMentionMenu(query: String)
	{
		guard composer.window?.firstResponder === composer
		else
		{
			mentionPopover?.close()
			return
		}
		mentionGeneration = selectionGeneration
		mentionText = composer.string
		if mentionPopover == nil
		{
			let panel = ComposerPopoverPanel(contentViewController: mentionMenu)
			panel.preservesParentKeyboardFocus = true
			panel.matchesAnchorWidth = true
			panel.limitsHeightToSpaceAboveAnchor = true
			panel.shouldDismissForEscape =
			{
				[weak self] in self?.composer.hasMarkedText() != true
			}
			panel.onPresentationChange =
			{
				[weak self] shown in
				if !shown
				{
					self?.mentionText = nil
				}
			}
			mentionMenu.onChoose =
			{
				[weak self] choice in self?.chooseMention(choice)
			}
			mentionPopover = panel
		}
		renderMentionMenu(query: query)
		if mentionPopover?.isShown == true
		{
			mentionPopover?.reposition()
		}
		else if composer.window?.isVisible == true
		{
			mentionPopover?.show(
				relativeTo: composerSurface.bounds,
				of: composerSurface
			)
		}
	}

	func renderMentionMenu(query: String)
	{
		mentionMenu.render(
			query: query,
			skills: slashCommandController.availableSkills,
			paths: fileIndexRuntime.index?.search(query) ?? [],
			hasProject: projectPath != nil,
			planMode: !planModeButton.isHidden,
			allowsPlanMode: onSlashCommand != nil && slashCommandController
				.unavailableReason?(.plan) == nil,
			allowsProjectSelection: onChooseProject != nil,
			allowsPluginManagement: onManagePlugins != nil
		)
	}

	func handleMentionMenuKey(_ selector: Selector) -> Bool
	{
		guard mentionPopover?.isShown == true, !composer.hasMarkedText()
		else
		{
			return false
		}
		switch selector
		{
		case #selector(NSResponder.moveDown(_:)):
			mentionMenu.moveSelection(by: 1)
		case #selector(NSResponder.moveUp(_:)):
			mentionMenu.moveSelection(by: -1)
		case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
			mentionMenu.chooseSelected()
		case #selector(NSResponder.cancelOperation(_:)):
			mentionPopover?.close()
		default: return false
		}
		return true
	}

	private func chooseMention(_ choice: ComposerMentionMenu.Choice)
	{
		guard mentionGeneration == selectionGeneration, mentionText == composer.string,
				let range = completionRange,
				NSMaxRange(range) <= (composer.string as NSString).length,
				!composer.hasMarkedText()
		else
		{
			mentionPopover?.close()
			return
		}
		if case .file(let path) = choice
		{
			let button = NSButton()
			button.identifier = NSUserInterfaceItemIdentifier(path)
			mentionPopover?.close()
			chooseFileResult(button)
			return
		}
		if case .plan = choice,
			onSlashCommand == nil || slashCommandController.unavailableReason?(.plan) != nil
		{
			mentionPopover?.close()
			return
		}
		let generation = selectionGeneration
		composer.insertText(
			"",
			replacementRange: range
		)
		onDraftChange?(composer.draftText)
		completionRange = nil
		mentionPopover?.close()
		view.window?.makeFirstResponder(composer)
		updateComposerHeight()
		guard generation == selectionGeneration
		else
		{
			return
		}
		switch choice
		{
		case .project: onChooseProject?()
		case .plugins: onManagePlugins?()
		case .files: choosePath()
		case .search: openFileSearch()
		case .image: chooseImage()
		case .code: chooseCodeRange()
		case .plan:
			if case .command(let invocation) = SlashCommandParser.parse("/plan")
			{
				onSlashCommand?(invocation)
			}
		case .skill(let skill):
			if slashCommandController.availableSkills
				.contains(where:
					{
						$0.path == skill.path && $0.enabled
					})
			{
				onSelectSkill?(skill)
			}
		case .file, .goal: break
		}
	}
}
