import AppKit

/// Keeps semantic title colors while refreshing retained button cells for their own appearance.
@MainActor
class DesktopAttributedTitleButton: NSButton
{
	private var semanticTitle: NSAttributedString?
	private var semanticAlternateTitle: NSAttributedString?
	private var installingTitle = false

	override var attributedTitle: NSAttributedString
	{
		get
		{
			super.attributedTitle
		}
		set
		{
			guard !installingTitle
			else
			{
				super.attributedTitle = newValue
				return
			}
			semanticTitle = NSAttributedString(attributedString: newValue)
			refreshTitleColors()
		}
	}

	override var attributedAlternateTitle: NSAttributedString
	{
		get
		{
			super.attributedAlternateTitle
		}
		set
		{
			guard !installingTitle
			else
			{
				super.attributedAlternateTitle = newValue
				return
			}
			semanticAlternateTitle = NSAttributedString(attributedString: newValue)
			refreshTitleColors()
		}
	}

	override var title: String
	{
		get
		{
			super.title
		}
		set
		{
			if !installingTitle
			{
				semanticTitle = nil
			}
			super.title = newValue
		}
	}

	override var alternateTitle: String
	{
		get
		{
			super.alternateTitle
		}
		set
		{
			if !installingTitle
			{
				semanticAlternateTitle = nil
			}
			super.alternateTitle = newValue
		}
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshTitleColors()
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		refreshTitleColors()
	}

	private func refreshTitleColors()
	{
		guard !installingTitle
		else
		{
			return
		}
		installingTitle = true
		defer
		{
			installingTitle = false
		}
		let originalImagePosition = imagePosition
		if let semanticTitle
		{
			super.attributedTitle = resolvedTitle(semanticTitle)
		}
		if let semanticAlternateTitle
		{
			super.attributedAlternateTitle = resolvedTitle(semanticAlternateTitle)
		}
		if imagePosition != originalImagePosition
		{
			imagePosition = originalImagePosition
		}
		needsDisplay = true
	}

	private func resolvedTitle(_ title: NSAttributedString) -> NSAttributedString
	{
		let resolved = NSMutableAttributedString(attributedString: title)
		title.enumerateAttribute(
			.foregroundColor,
			in: NSRange(
				location: 0,
				length: title.length
			)
		)
		{
			value, range, _ in
			guard let color = value as? NSColor
			else
			{
				return
			}
			let cgColor = DesktopTheme.resolvedCGColor(
				color,
				for: self
			)
			if let resolvedColor = NSColor(cgColor: cgColor)
			{
				resolved.addAttribute(
					.foregroundColor,
					value: resolvedColor,
					range: range
				)
			}
		}
		return resolved
	}
}
