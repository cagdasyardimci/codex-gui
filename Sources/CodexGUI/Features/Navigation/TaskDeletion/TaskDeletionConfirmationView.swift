import AppKit

@MainActor
final class TaskDeletionConfirmationView: NSViewController
{
	private enum LayoutMetrics
	{
		static let width: CGFloat = 420
		static let height: CGFloat = 158
		static let contentInset: CGFloat = 20
		static let cornerRadius: CGFloat = 20
		static let headingHeight: CGFloat = 24
		static let headingToWarningSpacing: CGFloat = 8
		static let warningLineHeight: CGFloat = 21
		static let buttonWidth: CGFloat = 78
		static let buttonHeight: CGFloat = 32
		static let buttonSpacing: CGFloat = 12
		static let closeSize: CGFloat = 16
	}

	private static let warningColor = grayscaleColor(
		light: 147 / 255,
		dark: 153 / 255
	)
	private static let closeIconColor = grayscaleColor(
		light: 0.3,
		dark: 0.75
	)

	var onDecision: ((Bool) -> Void)?
	let headingLabel = NSTextField(labelWithString: "Delete task?")
	let warningLabel = NSTextField(
		wrappingLabelWithString:
		"This permanently deletes the task and its subagent tasks.\nThis cannot be undone."
	)
	let cancelButton = TaskDeletionConfirmationButton(
		title: "Cancel",
		target: nil,
		action: nil
	)
	let deleteButton = TaskDeletionConfirmationButton(
		title: "Delete",
		target: nil,
		action: nil
	)
	let closeButton = NSButton(
		title: "Close",
		target: nil,
		action: nil
	)

	override func loadView()
	{
		let surface = DesktopSurface(
			DesktopTheme.sidebar,
			cornerRadius: LayoutMetrics.cornerRadius,
			bordered: true,
			borderWidth: 0.5
		)
		surface.setAccessibilityLabel("Task deletion confirmation")
		configureLabels()
		configureActions()
		arrangeContent(in: surface)
		view = surface
	}

	private func configureLabels()
	{
		headingLabel.font = .systemFont(
			ofSize: 20,
			weight: .semibold
		)
		headingLabel.textColor = .labelColor

		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = LayoutMetrics.warningLineHeight
		paragraph.maximumLineHeight = LayoutMetrics.warningLineHeight
		warningLabel.attributedStringValue = NSAttributedString(
			string: warningLabel.stringValue,
			attributes: [
				.font: NSFont.systemFont(ofSize: 14),
				.foregroundColor: Self.warningColor,
				.paragraphStyle: paragraph,
			]
		)
		warningLabel.preferredMaxLayoutWidth =
			LayoutMetrics.width - LayoutMetrics.contentInset * 2
	}

	private func configureActions()
	{
		configureActionButton(
			cancelButton,
			destructive: false
		)
		configureActionButton(
			deleteButton,
			destructive: true
		)
		cancelButton.keyEquivalent = "\r"
		cancelButton.setAccessibilityLabel("Cancel task deletion")
		deleteButton.setAccessibilityLabel("Confirm task deletion")

		DesktopTheme.styleButton(
			closeButton,
			icon: .xCrossed
		)
		closeButton.imagePosition = .imageOnly
		closeButton.contentTintColor = Self.closeIconColor
		closeButton.target = self
		closeButton.action = #selector(cancelDeletion)
		closeButton.keyEquivalent = "\u{1b}"
		closeButton.setAccessibilityLabel("Close task deletion confirmation")

		cancelButton.nextKeyView = deleteButton
		deleteButton.nextKeyView = closeButton
		closeButton.nextKeyView = cancelButton
	}

	private func configureActionButton(
		_ button: TaskDeletionConfirmationButton,
		destructive: Bool
	)
	{
		button.target = self
		button.action = destructive ? #selector(confirmDeletion) : #selector(cancelDeletion)
		button.isBordered = false
		button.bezelStyle = .inline
		button.font = .systemFont(ofSize: 14)
		button.isDestructive = destructive
		button.hasDestructiveAction = destructive
		button.focusRingType = .exterior
	}

	private func arrangeContent(in surface: NSView)
	{
		for element in [headingLabel, warningLabel, closeButton, cancelButton, deleteButton]
		{
			element.translatesAutoresizingMaskIntoConstraints = false
			surface.addSubview(element)
		}
		let contentInset = LayoutMetrics.contentInset
		NSLayoutConstraint.activate([
			surface.widthAnchor.constraint(equalToConstant: LayoutMetrics.width),
			surface.heightAnchor.constraint(equalToConstant: LayoutMetrics.height),
			headingLabel.leadingAnchor.constraint(
				equalTo: surface.leadingAnchor,
				constant: contentInset
			),
			headingLabel.topAnchor.constraint(
				equalTo: surface.topAnchor,
				constant: contentInset
			),
			headingLabel.heightAnchor.constraint(equalToConstant: LayoutMetrics.headingHeight),
			closeButton.centerYAnchor.constraint(equalTo: headingLabel.centerYAnchor),
			closeButton.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -contentInset
			),
			closeButton.widthAnchor.constraint(equalToConstant: LayoutMetrics.closeSize),
			closeButton.heightAnchor.constraint(equalToConstant: LayoutMetrics.closeSize),
			warningLabel.topAnchor.constraint(
				equalTo: headingLabel.bottomAnchor,
				constant: LayoutMetrics.headingToWarningSpacing
			),
			warningLabel.leadingAnchor.constraint(equalTo: headingLabel.leadingAnchor),
			warningLabel.trailingAnchor.constraint(
				equalTo: surface.trailingAnchor,
				constant: -contentInset
			),
			warningLabel.heightAnchor.constraint(
				equalToConstant: LayoutMetrics.warningLineHeight * 2
			),
			deleteButton.trailingAnchor.constraint(equalTo: warningLabel.trailingAnchor),
			deleteButton.bottomAnchor.constraint(
				equalTo: surface.bottomAnchor,
				constant: -contentInset
			),
			cancelButton.trailingAnchor.constraint(
				equalTo: deleteButton.leadingAnchor,
				constant: -LayoutMetrics.buttonSpacing
			),
			cancelButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
		])
		for button in [cancelButton, deleteButton]
		{
			button.widthAnchor.constraint(equalToConstant: LayoutMetrics.buttonWidth)
				.isActive = true
			button.heightAnchor.constraint(equalToConstant: LayoutMetrics.buttonHeight)
				.isActive = true
		}
	}

	@objc private func cancelDeletion()
	{
		onDecision?(false)
	}

	@objc private func confirmDeletion()
	{
		onDecision?(true)
	}

	private static func grayscaleColor(
		light: CGFloat,
		dark: CGFloat
	) -> NSColor
	{
		NSColor(name: nil)
		{
			appearance in
			let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
			return NSColor(
				white: isDark ? dark : light,
				alpha: 1
			)
		}
	}
}
