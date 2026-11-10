import AppKit

/// The image viewer exposes only the supported annotation action.
@MainActor
final class ImageCommentToolbar: DesktopSurface
{
	let commentButton = DesktopActionButton(
		title: "Comment",
		presentation: .imageCommentAction(primary: false),
		size: .regular
	)
	let saveButton = DesktopActionButton(
		title: "Save",
		presentation: .imageCommentAction(primary: true)
	)
	let cancelButton = DesktopActionButton(
		title: "",
		presentation: .imageCommentAction(primary: false)
	)
	let moveHandle = ImageCommentToolbarHandle()
	var onPlacementChange: (() -> Void)?
	private let stack = NSStackView()
	private var placementOffset = NSSize.zero

	init()
	{
		super.init(
			AppKitColorTokens.imageAnnotationSurface,
			cornerRadius: 15,
			cornerCurve: .superellipse(1.5),
			shadows: ShadowTokens.popover
		)
		frame = NSRect(
			x: 0,
			y: 0,
			width: 140,
			height: 40
		)
		cancelButton.symbol = .xCrossed
		cancelButton.setAccessibilityLabel("Cancel image comments")
		commentButton.image = DesktopIcons.imageCommentAnnotation()
		setAccessibilityElement(false)
		setAccessibilityIdentifier("image-comment-toolbar")
		stack.orientation = .horizontal
		stack.alignment = .centerY
		stack.spacing = 0
		for item in [moveHandle, commentButton, saveButton, cancelButton]
		{
			stack.addArrangedSubview(item)
		}
		moveHandle.onMove =
		{
			[weak self] delta in self?.move(by: delta)
		}
		moveHandle.onReset =
		{
			[weak self] in
			self?.placementOffset = .zero
			self?.onPlacementChange?()
		}
		AppKitLayout.pin(
			stack,
			to: self,
			inset: 2
		)
		for button in [commentButton, saveButton, cancelButton]
		{
			button.keyboardFocusPolicy = .dialog
		}
		render(commenting: false)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func move(by delta: NSSize)
	{
		placementOffset.width += delta.width
		placementOffset.height += delta.height
		onPlacementChange?()
	}

	func place(
		below image: NSRect,
		in viewport: NSRect
	)
	{
		guard viewport.width > 0, viewport.height > 0
		else
		{
			return
		}
		let size = NSSize(
			width: stack.fittingSize.width + 4,
			height: 40
		)
		let base = NSPoint(
			x: viewport.midX - size.width / 2,
			y: max(
				viewport.minY + 8,
				image.minY - 16 - size.height
			)
		)
		let origin = NSPoint(
			x: min(
				max(
					viewport.minX + 8,
					base.x + placementOffset.width
				),
				max(
					viewport.minX + 8,
					viewport.maxX - size.width - 8
				)
			),
			y: min(
				max(
					viewport.minY + 8,
					base.y + placementOffset.height
				),
				max(
					viewport.minY + 8,
					viewport.maxY - size.height - 56
				)
			)
		)
		placementOffset = NSSize(
			width: origin.x - base.x,
			height: origin.y - base.y
		)
		frame = NSRect(
			origin: origin,
			size: size
		)
		layoutSubtreeIfNeeded()
	}

	func render(
		commenting: Bool,
		count: Int = 0
	)
	{
		let noun = count == 1 ? "comment" : "comments"
		saveButton.title = count == 0 ? "Save" : "Save \(count) \(noun)"
		commentButton.isHidden = commenting
		saveButton.isHidden = !commenting
		cancelButton.isHidden = !commenting
	}
}
