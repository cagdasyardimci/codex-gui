import AppKit

@MainActor
enum ScrollableTextPreview
{
	static func make(
		text: String,
		size: NSSize,
		font: NSFont,
		accessibilityLabel: String
	) -> (scrollView: NSScrollView, textView: NSTextView)
	{
		let scrollView = NSScrollView(frame: NSRect(
			origin: .zero,
			size: size
		))
		scrollView.hasVerticalScroller = true

		let textView = NSTextView(frame: NSRect(
			origin: .zero,
			size: scrollView.contentSize
		))
		textView.isEditable = false
		textView.isSelectable = true
		textView.isHorizontallyResizable = false
		textView.isVerticallyResizable = true
		textView.autoresizingMask = [.width]
		textView.minSize = .zero
		textView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.textContainer?.containerSize = NSSize(
			width: scrollView.contentSize.width,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.textContainer?.widthTracksTextView = true
		textView.textContainerInset = NSSize(
			width: 8,
			height: 8
		)
		textView.font = font
		textView.string = text
		textView.setAccessibilityLabel(accessibilityLabel)

		scrollView.documentView = textView
		textView.sizeToFit()
		return (scrollView, textView)
	}
}
