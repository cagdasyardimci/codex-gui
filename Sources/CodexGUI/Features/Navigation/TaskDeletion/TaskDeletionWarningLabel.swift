import AppKit

/// Resolves attributed foregrounds under the label's appearance without replacing its text style.
@MainActor
final class TaskDeletionWarningLabel: NSTextField
{
	private var foregroundColor: NSColor?

	func setForegroundColor(_ color: NSColor)
	{
		foregroundColor = color
		refreshForegroundColor()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		refreshForegroundColor()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshForegroundColor()
	}

	private func refreshForegroundColor()
	{
		guard let foregroundColor, attributedStringValue.length > 0
		else
		{
			return
		}
		let text = NSMutableAttributedString(attributedString: attributedStringValue)
		let resolvedColor = NSColor(cgColor: AppKitColorResolution.resolvedCGColor(
			foregroundColor,
			for: self
		))
		text.addAttribute(
			.foregroundColor,
			value: resolvedColor ?? foregroundColor,
			range: NSRange(
				location: 0,
				length: text.length
			)
		)
		attributedStringValue = text
		needsDisplay = true
	}
}
