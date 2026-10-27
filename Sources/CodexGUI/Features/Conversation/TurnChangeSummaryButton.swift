import AppKit

@MainActor
final class TurnChangeSummaryButton: DesktopLayerButton
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
		layerBackgroundColor = AppKitColorTokens.canvas
		layerBorderColor = AppKitColorTokens.border
		updateTitle()
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

	func render(_ summary: ConversationTurnChangeSummary?)
	{
		self.summary = summary
		guard let summary
		else
		{
			isHidden = true
			return
		}
		let fileText = summaryTitle(summary)
		updateTitle()
		let description: String
		if summary.isLoading
		{
			description = "Loading turn changes"
		}
		else if summary.failure != nil && summary.fileCount == 0
		{
			description = fileText
		}
		else
		{
			description = "\(fileText), \(summary.additions) additions, "
				+ "\(summary.deletions) deletions."
		}
		setAccessibilityLabel(description + " View changes")
		toolTip = "View reported changes"
		invalidateIntrinsicContentSize()
		isHidden = false
	}

	private func updateTitle()
	{
		guard let summary
		else
		{
			return
		}
		effectiveAppearance.performAsCurrentDrawingAppearance
		{
			let fileText: String
			if summary.isLoading
			{
				fileText = "Loading turn changes"
			}
			else
			{
				fileText = summaryTitle(summary)
			}
			let title = NSMutableAttributedString(
				string: fileText,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13),
					.foregroundColor: NSColor.secondaryLabelColor,
				]
			)
			if !summary.isLoading && (summary.failure == nil || summary.fileCount > 0)
			{
				title.append(DesktopDiffStats.attributedValue(
					DesktopDiffStats.Counts(
						additions: summary.additions,
						deletions: summary.deletions
					),
					presentation: .turnSummary
				))
			}
			attributedTitle = title
		}
		needsDisplay = true
	}

	private func summaryTitle(_ summary: ConversationTurnChangeSummary) -> String
	{
		if summary.failure != nil && summary.fileCount == 0
		{
			return "Changes unavailable"
		}
		let turn = summary.usesPreviousTurn ? "Previous turn" : "Reported"
		let scope = summary.usesReportedEditFallback ? "\(turn) counts" : turn
		let files = summary.fileCount == 1 ? "file" : "files"
		return "\(scope) · \(summary.fileCount) \(files)"
	}
}
