import AppKit

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

	private func updateColors()
	{
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.canvas,
			for: self
		)
		layer?.borderColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.border,
			for: self
		)
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
					.foregroundColor: NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB)
						?? NSColor.secondaryLabelColor,
				]
			)
			let counts = !summary.isLoading
				? [(" +\(summary.additions)", NSColor.systemGreen),
					(" -\(summary.deletions)", NSColor.systemRed)] : []
			for (text, color) in counts
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
