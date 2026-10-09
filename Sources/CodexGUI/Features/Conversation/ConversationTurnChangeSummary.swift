import AppKit

/// A running turn's completed file-change reports, scoped to the selected conversation.
struct ConversationTurnChangeSummary: Equatable
{
	let fileCount: Int
	let additions: Int
	let deletions: Int

	init?(comparison: GitComparisonSnapshot)
	{
		guard !comparison.files.isEmpty
		else
		{
			return nil
		}
		fileCount = comparison.files.count
		additions = comparison.additions
		deletions = comparison.deletions
	}

	init?(_ snapshot: ConversationSnapshot)
	{
		guard snapshot.executionState.isBusy,
				let activeThreadID = snapshot.activeThreadID,
				let turnID = snapshot.activeTurnID,
				activeThreadID == snapshot.selectedThreadID
		else
		{
			return nil
		}
		if let diff = snapshot.activeTurnDiff
		{
			let paths = GitDiffParser.filePaths(in: diff)
			if diff.isEmpty
			{
				return nil
			}
			if !paths.isEmpty
			{
				let counts = GitDiffParser.hunks(in: diff.components(separatedBy: "\n"))
				fileCount = paths.count
				additions = counts.additions
				deletions = counts.deletions
				return
			}
		}
		var paths: Set<String> = []
		var additions = 0
		var deletions = 0
		for entry in snapshot.entries
		{
			guard ConversationEntryIdentity.turnIDWithFallback(entry.id) == turnID,
					case .fileChanges(
					let changes,
					let status
					) = entry.activity,
					status == "completed"
			else
			{
				continue
			}
			for change in changes
			{
				paths.insert(change.movePath ?? change.path)
				let counts = Self.lineCounts(change)
				additions += counts.additions
				deletions += counts.deletions
			}
		}
		guard !paths.isEmpty
		else
		{
			return nil
		}
		fileCount = paths.count
		self.additions = additions
		self.deletions = deletions
	}

	private static func lineCounts(_ change: FileChange) -> (
		additions: Int,
		deletions: Int
	)
	{
		if (change.kind == "add" || change.kind == "delete"),
			!change.diff.hasPrefix("@@ "), !change.diff.contains("\n@@ ")
		{
			let lines = change.diff.isEmpty ? 0 : change.diff
				.split(
					separator: "\n",
					omittingEmptySubsequences: false
				).count
				- (change.diff.hasSuffix("\n") ? 1 : 0)
			return change.kind == "add" ? (lines, 0) : (0, lines)
		}
		let parsed = GitDiffParser.hunks(in: change.diff.components(separatedBy: "\n"))
		return (parsed.additions, parsed.deletions)
	}
}

@MainActor
final class TurnChangeSummaryButton: NSButton
{
	private var summary: ConversationTurnChangeSummary?

	init()
	{
		super.init(frame: .zero)
		bezelStyle = .inline
		isBordered = false
		wantsLayer = true
		layer?.cornerRadius = 17
		layer?.borderWidth = 1
		updateColors()
		setAccessibilityLabel("Turn file changes")
	}

	required init?(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: NSSize
	{
		let measured = super.intrinsicContentSize
		return NSSize(
			width: measured.width + 24,
			height: 34
		)
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		updateColors()
	}

	func render(_ summary: ConversationTurnChangeSummary?)
	{
		self.summary = summary
		guard let summary
		else
		{
			isHidden = true
			return
		}
		let fileText = "\(summary.fileCount) \(summary.fileCount == 1 ? "file" : "files") changed"
		updateColors()
		setAccessibilityLabel(
			"\(fileText), \(summary.additions) additions, "
				+ "\(summary.deletions) deletions. View changes"
		)
		toolTip = "View changes"
		invalidateIntrinsicContentSize()
		isHidden = false
	}

	private func updateColors()
	{
		layer?.backgroundColor = DesktopTheme.resolvedCGColor(
			DesktopTheme.canvas,
			for: self
		)
		layer?.borderColor = DesktopTheme.resolvedCGColor(
			DesktopTheme.border,
			for: self
		)
		guard let summary
		else
		{
			return
		}
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let fileText = "\(summary.fileCount) "
				+ "\(summary.fileCount == 1 ? "file" : "files") changed"
			let title = NSMutableAttributedString(
				string: fileText,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13),
					.foregroundColor: NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB)
						?? NSColor.secondaryLabelColor,
				]
			)
			for (text, color) in [
				(" +\(summary.additions)", NSColor.systemGreen),
				(" -\(summary.deletions)", NSColor.systemRed),
			]
			{
				title.append(NSAttributedString(
					string: text,
					attributes: [
						.font: NSFont.systemFont(ofSize: 13),
						.foregroundColor: color.usingColorSpace(.deviceRGB) ?? color,
					]
				))
			}
			attributedTitle = title
		}
		needsDisplay = true
	}
}
