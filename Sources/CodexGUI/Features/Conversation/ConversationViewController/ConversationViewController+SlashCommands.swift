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
				fileSearchPopover?.close(); completionRange = nil
			}
			return
		}
		if let query = SlashCommandParser.completionQuery(
			in: composer.string,
			selectedRange: composer.selectedRange()
		)
		{
			if fileSearchWasCompletion
			{
				fileSearchPopover?.close(); completionRange = nil
			}
			slashCompletionRange = query.tokenRange
			slashCompletionGeneration = selectionGeneration
			slashCompletionText = composer.string
			slashCommandController.render(prefix: query.prefix)
			if slashCommandPopover == nil
			{
				let popover = ComposerPopoverPanel(contentViewController: slashCommandController)
				popover.preservesParentKeyboardFocus = true
				popover.matchesAnchorWidth = true
				popover
					.shouldDismissForEscape =
					{
						[weak self] in
						self?.composer.hasMarkedText() != true
					}
				popover.onPresentationChange =
				{
					[weak self] shown in
					if !shown
					{
						self?.slashCompletionRange = nil; self?.slashCompletionText = nil
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
				slashCommandPopover = popover
			}
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
			else if selector == #selector(NSResponder.insertNewline(_:))
			{
				dismissSlashCommands()
				onSend?()
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
			dismissSlashCommands(); return
		}
		let generation = selectionGeneration
		let performCommand = onSlashCommand
		let sendCommand = onSend
		let updateDraft = onDraftChange
		let shouldExecute = execute
		let text = composer.string as NSString
		let hasSeparator = NSMaxRange(range) < text.length
		let suffix = !shouldExecute && command.acceptsArguments && !hasSeparator ? " " : ""
		let replacement = "/" + command.name + suffix
		dismissSlashCommands()
		composer.insertText(
			replacement,
			replacementRange: range
		)
		updateDraft?(composer.string)
		updateComposerHeight()
		view.window?.makeFirstResponder(composer)
		dismissSlashCommands()
		if shouldExecute, selectionGeneration == generation
		{
			switch SlashCommandParser.parse(composer.string)
			{
			case .command(let invocation): performCommand?(invocation)
			case .error: sendCommand?()
			case .text: break
			}
		}
	}

	func textViewDidChangeSelection(_ notification: Notification)
	{
		guard notification.object as? NSTextView === composer
		else
		{
			return
		}
		updateComposerCompletion()
	}
}
