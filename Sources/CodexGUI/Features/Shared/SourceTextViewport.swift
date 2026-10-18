import AppKit

/// Native text and ruler setup shared by source documents and diff columns.
@MainActor
enum SourceTextViewport
{
	static func configure(
		_ textView: SourceTextView,
		wrapsLines: Bool
	)
	{
		textView.configureSourceText(wrapsLines: wrapsLines)
		textView.autoresizingMask = []
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.lineBreakMode = wrapsLines ? .byCharWrapping : .byClipping
	}

	static func install(
		_ textView: SourceTextView,
		in scrollView: NSScrollView,
		ruler: NSRulerView
	)
	{
		scrollView.documentView = textView
		scrollView.autohidesScrollers = true
		scrollView.verticalRulerView = ruler
		scrollView.hasVerticalRuler = true
		scrollView.rulersVisible = true
	}

	static func setWrapping(
		_ wrapsLines: Bool,
		for textView: SourceTextView,
		in scrollView: NSScrollView
	)
	{
		textView.textContainer?.lineBreakMode = wrapsLines ? .byCharWrapping : .byClipping
		if wrapsLines
		{
			let clip = scrollView.contentView
			clip.scroll(to: NSPoint(
				x: 0,
				y: clip.bounds.minY
			))
			scrollView.reflectScrolledClipView(clip)
		}
		scrollView.hasHorizontalScroller = !wrapsLines
	}

	/// Updates the wrapping width before owners measure their different document heights.
	static func sizeWrappedText(
		_ textView: SourceTextView,
		to viewportWidth: CGFloat
	)
	{
		let width = max(
			1,
			viewportWidth
		)
		let inset = textView.textContainerInset.width
		let containerSize = NSSize(
			width: max(
				1,
				width - inset * 2
			),
			height: CGFloat.greatestFiniteMagnitude
		)
		if textView.textContainer?.containerSize != containerSize
		{
			textView.textContainer?.containerSize = containerSize
		}
		if textView.frame.width != width
		{
			textView.setFrameSize(NSSize(
				width: width,
				height: textView.frame.height
			))
		}
	}
}
