import AppKit

/// A wrapping report whose document grows independently of the sheet's viewport.
@MainActor
final class BackendDetailsView: NSScrollView
{
	init(report: String)
	{
		super.init(frame: NSRect(
			x: 0,
			y: 0,
			width: 500,
			height: 240
		))
		hasVerticalScroller = true
		hasHorizontalScroller = false
		autohidesScrollers = true

		let textView = makeReportTextView()
		documentView = textView
		textView.string = report
		textView.sizeToFit()
	}

	private func makeReportTextView() -> NSTextView
	{
		let textView = NSTextView(frame: NSRect(
			origin: .zero,
			size: contentSize
		))
		textView.isEditable = false
		textView.isSelectable = true
		textView.isRichText = false
		textView.isVerticallyResizable = true
		textView.isHorizontallyResizable = false
		textView.autoresizingMask = [.width]
		textView.minSize = NSSize(
			width: 0,
			height: contentSize.height
		)
		textView.maxSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.textContainer?.containerSize = NSSize(
			width: contentSize.width,
			height: CGFloat.greatestFiniteMagnitude
		)
		textView.textContainer?.widthTracksTextView = true
		textView.font = .monospacedSystemFont(
			ofSize: 12,
			weight: .regular
		)
		textView.setAccessibilityLabel("Codex backend diagnostic details")
		return textView
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
