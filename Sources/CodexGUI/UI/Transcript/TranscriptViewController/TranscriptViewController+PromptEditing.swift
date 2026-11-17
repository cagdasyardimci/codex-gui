import AppKit

extension TranscriptViewController
{
	func configurePromptEditing(
		_ item: ConversationCollectionItem,
		entry: ConversationEntry
	)
	{
		guard entry.kind == .user
		else
		{
			item.setPromptEditor(nil)
			return
		}
		let editor = editingPrompt?.entryID == entry.id ? editingPrompt?.editor : nil
		item.setPromptEditor(editor)
		editor?.refreshSend()
		let context = renderedContext
		guard let threadID = selectedThreadID, editablePrompt != nil,
				renderedPresentation?.editablePromptEntryIDs.contains(entry.id) == true
		else
		{
			item.setEditAction(nil)
			return
		}
		item.setEditAction
		{
			[weak self] in
			guard let self, self.renderedContext == context, self.requestedContext == context,
					self.selectedThreadID == threadID,
					let original = self.editablePrompt?(threadID, entry.id)
			else
			{
				return
			}
			self.beginPromptEdit(
				entryID: entry.id,
				threadID: threadID,
				text: original,
				allowsEmptyText: !entry.imageAttachments.isEmpty || !entry.sourceReferences.isEmpty
			)
		}
	}

	func refreshVisiblePromptEditing()
	{
		guard renderedContext == requestedContext
		else
		{
			return
		}
		for path in collectionView.indexPathsForVisibleItems()
		{
			guard displayedRows.indices.contains(path.item),
					case .message(let entry) = displayedRows[path.item], entry.kind == .user,
					let item = collectionView.item(at: path) as? ConversationCollectionItem
			else
			{
				continue
			}
			configurePromptEditing(
				item,
				entry: entry
			)
		}
	}

	private func beginPromptEdit(
		entryID: String,
		threadID: String,
		text: String,
		allowsEmptyText: Bool
	)
	{
		guard editingPrompt == nil
		else
		{
			return
		}
		let context = renderedContext
		let editor = TranscriptPromptEditor(
			text: text,
			allowsEmptyText: allowsEmptyText
		)
		editor.canSend =
		{
			[weak self, weak editor] in
			guard let self, let editor, self.editingPrompt?.editor === editor,
					self.renderedContext == context, self.requestedContext == context,
					self.selectedThreadID == threadID
			else
			{
				return false
			}
			return self.editablePrompt?(threadID, entryID) == text
		}
		editor.onSend =
		{
			[weak self] revision in
			self?.onRevisePrompt?(threadID, entryID, revision)
		}
		editor.onCancel =
		{
			[weak self, weak editor] in
			guard let self, let editor, self.editingPrompt?.editor === editor
			else
			{
				return
			}
			self.editingPrompt = nil
			self.updatePromptEditorRow(entryID)
		}
		editingPrompt = (entryID, editor)
		updatePromptEditorRow(entryID)
		editor.window?.makeFirstResponder(editor.textView)
	}

	private func updatePromptEditorRow(_ entryID: String)
	{
		guard let index = displayedRows.firstIndex(where:
			{
				$0.id == entryID
			})
		else
		{
			return
		}
		let anchor = readingAnchor()
		let path = IndexPath(
			item: index,
			section: 0
		)
		if let item = collectionView.item(at: path) as? ConversationCollectionItem,
			case .message(let entry) = displayedRows[index]
		{
			configurePromptEditing(
				item,
				entry: entry
			)
		}
		(collectionView.collectionViewLayout as? ConversationFlowLayout)?.invalidateContentMetrics()
		view.layoutSubtreeIfNeeded()
		collectionView.layoutSubtreeIfNeeded()
		restoreReadingPosition(
			followOutput: false,
			anchor: anchor
		)
	}
}
