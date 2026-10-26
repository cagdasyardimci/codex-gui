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
		let fileText = "\(summary.fileCount) \(summary.fileCount == 1 ? "file" : "files") changed"
		updateTitle()
		let description: String
		if summary.isLoading
		{
			description = "Loading turn changes"
		}
		else
		{
			description = "\(fileText), \(summary.additions) additions, "
				+ "\(summary.deletions) deletions."
		}
		let previousNote = summary.usesPreviousTurn
			? "Previous editing turn; this active turn has no available edit reports yet. " : ""
		let fallbackNote = previousNote + (summary.usesReportedEditFallback
			? GitReportedTurnComparison.fallbackMessage + " " : "")
		setAccessibilityLabel(description + " " + fallbackNote + "View changes")
		toolTip = fallbackNote + GitReportedTurnComparison.coverageMessage
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
				fileText = "\(summary.fileCount) "
					+ "\(summary.fileCount == 1 ? "file" : "files") changed"
			}
			let title = NSMutableAttributedString(
				string: fileText,
				attributes: [
					.font: NSFont.systemFont(ofSize: 13),
					.foregroundColor: NSColor.secondaryLabelColor,
				]
			)
			if !summary.isLoading
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
}
