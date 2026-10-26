import AppKit

@MainActor
enum AppKitLayout
{
	static func verticalStack(
		_ views: [NSView],
		spacing: CGFloat = LayoutTokens.LayoutDefaults.verticalSpacing,
		alignment: NSLayoutConstraint.Attribute = .leading
	) -> NSStackView
	{
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.alignment = alignment
		stack.spacing = spacing
		return stack
	}

	static func horizontalStack(
		_ views: [NSView],
		spacing: CGFloat = LayoutTokens.LayoutDefaults.horizontalSpacing,
		alignment: NSLayoutConstraint.Attribute = .centerY
	) -> NSStackView
	{
		let stack = NSStackView(views: views)
		stack.orientation = .horizontal
		stack.alignment = alignment
		stack.spacing = spacing
		return stack
	}

	@discardableResult
	static func pin(
		_ view: NSView,
		to container: NSView,
		inset: CGFloat = LayoutTokens.LayoutDefaults.contentInset,
		priority: NSLayoutConstraint.Priority = .required
	) -> [NSLayoutConstraint]
	{
		pin(
			view,
			to: container,
			insets: NSEdgeInsets(
				top: inset,
				left: inset,
				bottom: inset,
				right: inset
			),
			priority: priority
		)
	}

	@discardableResult
	static func pin(
		_ view: NSView,
		to container: NSView,
		insets: NSEdgeInsets,
		priority: NSLayoutConstraint.Priority = .required
	) -> [NSLayoutConstraint]
	{
		container.addSubview(view)
		view.translatesAutoresizingMaskIntoConstraints = false

		let constraints = [
			view.leadingAnchor.constraint(
				equalTo: container.leadingAnchor,
				constant: insets.left
			),
			view.trailingAnchor.constraint(
				equalTo: container.trailingAnchor,
				constant: -insets.right
			),
			view.topAnchor.constraint(
				equalTo: container.topAnchor,
				constant: insets.top
			),
			view.bottomAnchor.constraint(
				equalTo: container.bottomAnchor,
				constant: -insets.bottom
			),
		]
		for constraint in constraints
		{
			constraint.priority = priority
		}
		NSLayoutConstraint.activate(constraints)
		return constraints
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
		let document = DesktopFlippedView()
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
