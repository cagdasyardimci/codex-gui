import AppKit

/// File and hunk selection share the review controller's current presentation identity.
extension ChangesViewController
{
	func updateSelectedFile(preserveHunk: Bool)
	{
		let path = displayedPath(at: filesTable.selectedRow)
		if selectedFilePath != path || !preserveHunk
		{
			selectedHunkID = nil
		}
		selectedFilePath = path
		sectionButton.removeAllItems()
		sectionButton.addItem(withTitle: "Whole file")
		sectionButton.item(at: 0)?.representedObject = ""
		if let file = selectedFile
		{
			for (index, hunk) in file.hunks.enumerated()
			{
				sectionButton.addItem(withTitle: "Section \(index + 1) · \(hunk.header)")
				sectionButton.lastItem?.representedObject = hunk.id
				sectionButton.lastItem?.toolTip = hunk.header
			}
			let index = file.hunks.firstIndex(where:
				{
					$0.id == selectedHunkID
				})
				.map
				{
					$0 + 1
				} ?? 0
			sectionButton.selectItem(at: index)
			sectionButton.isEnabled = !file.hunks.isEmpty
		}
		else
		{
			sectionButton.isEnabled = false
			selectedHunkID = nil
		}
		updateDiff()
		updateReviewActions()
	}

	func updateDiff()
	{
		let selection = EditorSelection(
			projectPath: projectPath,
			owner: presentationOwner,
			threadID: selectedReview?.threadID ?? renderedKey?.selectedThreadID,
			turnID: selectedReview?.turnID,
			filePath: selectedFilePath,
			hunkID: selectedHunkID,
			contentIdentity: selectedFile?.fingerprint ?? legacyDiff
		)
		if editorSelection != selection
		{
			editorSelection = selection
			editorSelectionGeneration += 1
			pendingEditorRequest = nil
		}
		let displayText = selectedDiffText()

		let hasTextDiff =
			selectedFile.map
				{
					!$0.diff.isEmpty
				} ?? (reviewTurns.isEmpty && !legacyDiff.isEmpty)
		if hasTextDiff
		{
			diffTextView.textStorage?.setAttributedString(Self.coloredDiff(displayText))
		}
		else
		{
			let paragraphStyle = NSMutableParagraphStyle()
			paragraphStyle.lineBreakMode = .byWordWrapping
			paragraphStyle.lineSpacing = 3
			diffTextView.textStorage?.setAttributedString(
				NSAttributedString(
					string: displayText,
					attributes: [
						.font: NSFont.systemFont(ofSize: 12),
						.foregroundColor: NSColor.secondaryLabelColor,
						.paragraphStyle: paragraphStyle,
					]
				)
			)
		}

		diffTextView.sizeToFit()
		openButton.isEnabled = canOpenSelectedFile && pendingEditorRequest == nil
	}

	private func selectedDiffText() -> String
	{
		if let file = selectedFile
		{
			let section = selectedHunk?.text ?? file.diff
			if let explanation = file.explanation
			{
				return section.isEmpty ? explanation : "\(explanation)\n\n\(section)"
			}
			else
			{
				return section.isEmpty ? "No text diff reported for this file." : section
			}
		}
		else if reviewTurns.isEmpty, let path = selectedFilePath
		{
			let section = GitDiffParser.selectedDiff(
				for: path,
				in: legacyDiff
			)
			return section.isEmpty ? "No diff reported for this turn." : section
		}
		else if !reviewTurns.isEmpty
		{
			return
				selectedReview == nil
					? "Select a reported turn to review changes."
					: "No file changes reported for this turn."
		}
		else
		{
			return legacyDiff.isEmpty ? "No change reported for this turn." : legacyDiff
		}
	}

	private static func coloredDiff(_ text: String) -> NSAttributedString
	{
		let paragraphStyle = NSMutableParagraphStyle()
		paragraphStyle.lineBreakMode = .byCharWrapping
		let attributed = NSMutableAttributedString(
			string: text,
			attributes: [
				.font: NSFont.monospacedSystemFont(
					ofSize: 11,
					weight: .regular
				),
				.foregroundColor: NSColor.labelColor,
				.paragraphStyle: paragraphStyle,
			]
		)
		for line in GitDiffPresentation.patchLines(in: text)
		{
			let color: NSColor?
			switch line.kind
			{
			case .source(.addition): color = .systemGreen
			case .source(.deletion): color = .systemRed
			case .hunkHeader: color = .systemBlue
			default: color = nil
			}
			if let color, line.range.length > 0
			{
				attributed.addAttribute(
					.foregroundColor,
					value: color,
					range: line.range
				)
			}
		}
		return attributed
	}

}
