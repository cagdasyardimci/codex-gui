import AppKit

/// Complete search-result action host with shared content and AppKit-native attachment variants.
@MainActor
final class DesktopSearchResultButton: DesktopLayerButton
{
	enum Presentation
	{
		case content(DesktopSearchResultContentView.Presentation)
		case nativeAttachment(path: String)
	}

	private let content: DesktopSearchResultContentView?

	convenience init(
		title: String,
		context: String,
		shortcut: String = "",
		inlineContext: Bool = false,
		target: AnyObject?,
		action: Selector?
	)
	{
		self.init(
			presentation: .content(inlineContext
				? .inlineFile(
					title: title,
					directory: context,
					shortcut: shortcut
				)
				: .chat(
					title: title,
					context: context,
					shortcut: shortcut
				)),
			target: target,
			action: action
		)
	}

	init(
		presentation: Presentation,
		target: AnyObject?,
		action: Selector?
	)
	{
		if case .content(let contentPresentation) = presentation
		{
			content = DesktopSearchResultContentView(presentation: contentPresentation)
		}
		else
		{
			content = nil
		}
		super.init(frame: .zero)
		self.target = target
		self.action = action
		switch presentation
		{
		case .content:
			guard let content
			else
			{
				return
			}
			title = ""
			isBordered = false
			wantsLayer = true
			layer?.cornerRadius = 12
			AppKitLayout.pin(
				content,
				to: self,
				inset: 0
			)
			setAccessibilityLabel(content.accessibilityLabel())
			toolTip = content.toolTip
		case .nativeAttachment(let path):
			// Preserve AppKit's inline renderer, text metrics, truncation and natural control size.
			let native = NSButton(
				title: path,
				target: target,
				action: action
			)
			native.bezelStyle = .inline
			native.alignment = .left
			cell = native.cell?.copy() as? NSCell
			// NSButtonCell title layout also reads its control view's initial bounds.
			setFrameSize(native.frame.size)
			focusRingType = native.focusRingType
			identifier = NSUserInterfaceItemIdentifier(path)
			setAccessibilityLabel("Attach project file \(path)")
		}
	}

	static func attachment(
		path: String,
		target: AnyObject?,
		action: Selector?
	) -> DesktopSearchResultButton
	{
		DesktopSearchResultButton(
			presentation: .nativeAttachment(path: path),
			target: target,
			action: action
		)
	}

	func setSelected(_ selected: Bool)
	{
		guard let content
		else
		{
			return
		}
		layerBackgroundAlpha = nil
		layerBackgroundColor = selected ? AppKitColorTokens.searchResultSelection : .clear
		content.setSelected(selected)
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		bounds.contains(convert(
			point,
			from: superview
		)) ? self : nil
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
