import AppKit

/// Common readable status body; callers retain loading, retry and recovery decisions.
@MainActor
class ViewerStatusView: DesktopSurface
{
	let messageLabel = NSTextField(wrappingLabelWithString: "")

	init(
		icon: NSImage? = nil,
		title: String? = nil,
		message: String
	)
	{
		super.init(AppKitColorTokens.canvas)
		var views: [NSView] = []
		if let icon
		{
			let image = NSImageView(image: icon)
			image.contentTintColor = AppKitColorTokens.secondaryText
			image.setAccessibilityElement(false)
			image.widthAnchor.constraint(equalToConstant: 32).isActive = true
			image.heightAnchor.constraint(equalToConstant: 32).isActive = true
			views.append(image)
		}
		if let title
		{
			let label = NSTextField(labelWithString: title)
			label.font = .systemFont(
				ofSize: 16,
				weight: .medium
			)
			label.alignment = .center
			views.append(label)
		}
		messageLabel.stringValue = message
		messageLabel.font = .systemFont(ofSize: 13)
		messageLabel.textColor = AppKitColorTokens.secondaryText
		messageLabel.alignment = .center
		messageLabel.isSelectable = true
		views.append(messageLabel)
		let stack = NSStackView(views: views)
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 12
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)
		// Insets yield while the containing pane is collapsed or not yet sized.
		let leadingInset = stack.leadingAnchor.constraint(
			greaterThanOrEqualTo: leadingAnchor,
			constant: 16
		)
		let trailingInset = stack.trailingAnchor.constraint(
			lessThanOrEqualTo: trailingAnchor,
			constant: -16
		)
		leadingInset.priority = NSLayoutConstraint.Priority(999)
		trailingInset.priority = NSLayoutConstraint.Priority(999)
		NSLayoutConstraint.activate([
			stack.centerXAnchor.constraint(equalTo: centerXAnchor),
			stack.centerYAnchor.constraint(equalTo: centerYAnchor),
			leadingInset,
			trailingInset,
			messageLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
		])
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setMessage(_ message: String)
	{
		messageLabel.stringValue = message
	}
}
