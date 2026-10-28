import AppKit

@MainActor
extension ConversationViewController
{
	func updateComposerCompletion()
	{
		guard !composer.hasMarkedText()
		else
		{
			dismissSlashCommands()
			if fileSearchWasCompletion
			{
				fileSearchPopover?.close()
				mentionPopover?.close()
				completionRange = nil
			}
			return
		}
		if let query = SlashCommandParser.completionQuery(
			in: composer.draftText,
			selectedRange: composer.draftRange(for: composer.selectedRange())
		)
		{
			if fileSearchWasCompletion
			{
				fileSearchPopover?.close()
				mentionPopover?.close()
				completionRange = nil
			}
			slashCommandController.render(prefix: query.prefix)
			let hasResults = !slashCommandController.commands.isEmpty
				|| !slashCommandController.matchingSkills.isEmpty
			if !hasResults
			{
				slashCommandPopover?.close()
			}
			slashCompletionRange = composer.displayRange(for: query.tokenRange)
			slashCompletionGeneration = selectionGeneration
			slashCompletionText = composer.string
			guard hasResults
			else
			{
				return
			}
			configureSlashCommandPopoverIfNeeded()

			// A restored or asynchronously updated draft in a hidden window must not reveal
			// a detached command panel. The list can still prepare its selection offscreen.
			if slashCommandPopover?.isShown != true, composer.window?.isVisible == true
			{
				slashCommandPopover?.show(
					relativeTo: composerSurface.bounds,
					of: composerSurface
				)
			}
			return
		}
		dismissSlashCommands()
		showAtFileCompletionIfNeeded()
	}

	private func configureSlashCommandPopoverIfNeeded()
	{
		guard slashCommandPopover == nil
		else
		{
			return
		}
		let popover = ComposerPopoverPanel(contentViewController: slashCommandController)
		popover.preservesParentKeyboardFocus = true
		popover.matchesAnchorWidth = true
		popover.shouldDismissForEscape =
		{
			[weak self] in
			self?.composer.hasMarkedText() != true
		}
		popover.onPresentationChange =
		{
			[weak self] shown in
			if !shown
			{
				self?.slashCompletionRange = nil
				self?.slashCompletionText = nil
			}
		}
		slashCommandController.onChoose =
		{
			[weak self] command in
			self?.chooseSlashCommand(
				command,
				execute: true
			)
		}
		slashCommandController.onChooseSkill =
		{
			[weak self] skill in self?.chooseSlashSkill(skill)
		}
		slashCommandPopover = popover
	}

	func dismissSlashCommands()
	{
		slashCommandPopover?.close()
		slashCompletionRange = nil
		slashCompletionText = nil
	}

	func handleSlashCommandKey(_ selector: Selector) -> Bool
	{
		guard slashCompletionRange != nil, !composer.hasMarkedText()
		else
		{
			return false
		}
		if selector == #selector(NSResponder.cancelOperation(_:))
		{
			dismissSlashCommands()
			return true
		}
		if selector == #selector(NSResponder.moveDown(_:)) || selector ==
			#selector(NSResponder.moveUp(_:))
		{
			slashCommandController
				.moveSelection(by: selector == #selector(NSResponder.moveDown(_:)) ? 1 : -1)
			return true
		}
		if selector == #selector(NSResponder.insertTab(_:)) || selector ==
			#selector(NSResponder.insertNewline(_:))
		{
			if let command = slashCommandController.selectedCommand
			{
				chooseSlashCommand(
					command,
					execute: selector == #selector(NSResponder.insertNewline(_:))
				)
			}
			else if let skill = slashCommandController.selectedSkill
			{
				chooseSlashSkill(skill)
			}
			else if selector == #selector(NSResponder.insertNewline(_:))
			{
				dismissSlashCommands()
				if imageImportTasks.isEmpty
				{
					onSend?()
				}
			}
			return true
		}
		return false
	}

	func chooseSlashCommand(
		_ command: SlashCommandDescriptor,
		execute: Bool
	)
	{
		guard slashCompletionGeneration == selectionGeneration,
				let range = slashCompletionRange,
				slashCompletionText == composer.string,
				NSMaxRange(range) <= (composer.string as NSString).length,
				!composer.hasMarkedText()
		else
		{
			dismissSlashCommands()
			return
		}
		let generation = selectionGeneration
		let performCommand = onSlashCommand
		let sendCommand = onSend
		let updateDraft = onDraftChange
		let shouldExecute = execute
		let text = composer.string as NSString
		let hasFollowingText = NSMaxRange(range) < text.length
		let needsArgumentSeparator =
			!shouldExecute && command.acceptsArguments && !hasFollowingText
		let suffix = needsArgumentSeparator ? " " : ""
		let replacement = "/" + command.name + suffix
		dismissSlashCommands()
		composer.insertText(
			replacement,
			replacementRange: range
		)
		updateDraft?(composer.draftText)
		updateComposerHeight()
		view.window?.makeFirstResponder(composer)
		dismissSlashCommands()
		if shouldExecute, selectionGeneration == generation, imageImportTasks.isEmpty
		{
			switch SlashCommandParser.parse(composer.draftText)
			{
			case .command(let invocation): performCommand?(invocation)
			case .error: sendCommand?()
			case .text: break
			}
		}
	}

	func chooseSlashSkill(_ skill: AvailableSkill)
	{
		guard slashCompletionGeneration == selectionGeneration,
				let range = slashCompletionRange, slashCompletionText == composer.string,
				NSMaxRange(range) <= (composer.string as NSString).length,
				!composer.hasMarkedText(),
				slashCommandController.availableSkills
				.contains(where:
				{
					$0.path == skill.path && $0.enabled
				})
		else
		{
			dismissSlashCommands()
			return
		}
		let generation = selectionGeneration
		let selectSkill = onSelectSkill
		let updateDraft = onDraftChange
		dismissSlashCommands()
		composer.insertText(
			"",
			replacementRange: range
		)
		updateDraft?(composer.draftText)
		guard selectionGeneration == generation
		else
		{
			return
		}
		selectSkill?(skill)
		updateComposerHeight()
		view.window?.makeFirstResponder(composer)
	}

	func textViewDidChangeSelection(_ notification: Notification)
	{
		guard !composer.isUpdatingSkillMention, notification.object as? NSTextView === composer
		else
		{
			return
		}
		updateComposerCompletion()
	}
}
