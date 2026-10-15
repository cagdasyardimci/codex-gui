import AppKit

@MainActor
enum AppKitLayout
{
	static func verticalStack(
		_ views: [NSView],
		spacing: CGFloat = LayoutTokens.LayoutDefaults.verticalSpacing
	) -> NSStackView
	{
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = spacing
		return stack
	}

	static func horizontalStack(
		_ views: [NSView],
		spacing: CGFloat = LayoutTokens.LayoutDefaults.horizontalSpacing
	) -> NSStackView
	{
		let stack = NSStackView(views: views)
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = spacing
		return stack
	}

	static func pin(
		_ view: NSView,
		to container: NSView,
		inset: CGFloat = LayoutTokens.LayoutDefaults.contentInset
	)
	{
		container.addSubview(view)
		view.translatesAutoresizingMaskIntoConstraints = false

		NSLayoutConstraint.activate([
			view.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: inset
			),
			view.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -inset
			),
			view.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: inset
			),
			view.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -inset
			),
		])
	}

	static func title(_ text: String) -> NSTextField
	{
		let label = NSTextField(labelWithString: text)
		label.font = AppKitFontResolver.font(TypographyTokens.Controls.title)
		return label
	}

	static func compressHorizontally(_ control: NSControl)
	{
		control.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		control.cell?.lineBreakMode = .byTruncatingMiddle
	}

	static func scrollableContent(
		_ content: NSView,
		inset: CGFloat = LayoutTokens.LayoutDefaults.contentInset
	) -> NSScrollView
	{
		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.autohidesScrollers = true
		let document = FlippedLayoutDocument()
		pin(
			content,
			to: document,
			inset: inset
		)
		document.translatesAutoresizingMaskIntoConstraints = false
		scrollView.documentView = document
		NSLayoutConstraint.activate([
			document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
			document.heightAnchor
				.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
		])
		return scrollView
	}
}

private final class FlippedLayoutDocument: NSView
{
	override var isFlipped: Bool
	{
		true
	}
}
