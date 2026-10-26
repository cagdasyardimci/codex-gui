import AppKit

@MainActor
final class ComposerImageAttachmentView: NSView
{
	static let sideLength: CGFloat = 120

	private let removeButton: NSButton
	private var pointerTrackingArea: NSTrackingArea?
	private var revealState = DesktopActionRevealState()

	convenience init(
		image: NSImage?,
		title: String,
		identifier: String,
		onPreview: @escaping (NSButton) -> Void,
		onRemove: @escaping (NSButton) -> Void
	)
	{
		let preview = NSButton(
			title: "Expand image",
			target: nil,
			action: nil
		)
		preview.identifier = NSUserInterfaceItemIdentifier(identifier)
		preview.setAccessibilityLabel("Expand attached image \(title)")
		let remove = DesktopResourceRow.actionButton(DesktopResourceRow.Action(
			title: "Remove",
			icon: .xCircle,
			accessibilityLabel: "Remove image \(title)",
			identifier: identifier,
			perform: onRemove
		))
		self.init(
			image: image,
			previewButton: preview,
			removeButton: remove
		)
		previewAction = onPreview
		preview.target = self
		preview.action = #selector(previewImage(_:))
	}

	private var previewAction: ((NSButton) -> Void)?

	@objc private func previewImage(_ sender: NSButton)
	{
		previewAction?(sender)
	}

	init(
		image: NSImage?,
		previewButton: NSButton,
		removeButton: NSButton
	)
	{
		self.removeButton = removeButton
		super.init(frame: .zero)

		let imageView = AttachmentThumbnailImageView()
		imageView.image = image ?? DesktopIcons.image(.infoCircle)
		imageView.setAccessibilityElement(false)
		imageView.wantsLayer = true
		imageView.layer?.cornerRadius = 6
		imageView.layer?.masksToBounds = true
		AppKitLayout.pin(
			imageView,
			to: self,
			inset: 0
		)

		previewButton.title = ""
		previewButton.isBordered = false
		previewButton.isTransparent = true
		AppKitLayout.pin(
			previewButton,
			to: self,
			inset: 0
		)

		removeButton.translatesAutoresizingMaskIntoConstraints = false
		addSubview(removeButton)
		NSLayoutConstraint.activate([
			widthAnchor.constraint(equalToConstant: Self.sideLength),
			heightAnchor.constraint(equalToConstant: Self.sideLength),
			removeButton.topAnchor.constraint(
				equalTo: topAnchor,
				constant: 4
			),
			removeButton.trailingAnchor.constraint(
				equalTo: trailingAnchor,
				constant: -4
			),
			removeButton.heightAnchor.constraint(equalToConstant: 24),
		])

		// Keep removal in keyboard navigation and accessibility while hiding its resting visual.
		removeButton.alphaValue = 0
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		NotificationCenter.default.removeObserver(self)
		if let window
		{
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(focusDidChange),
				name: NSWindow.didUpdateNotification,
				object: window
			)
		}
		revealState.isHovered = false
		updateRemovalVisibility()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		pointerTrackingArea = DesktopHoverTracking.replace(
			in: self,
			previous: pointerTrackingArea
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		revealState.isHovered = true
		updateRemovalVisibility()
	}

	override func mouseExited(with event: NSEvent)
	{
		revealState.isHovered = false
		updateRemovalVisibility()
	}

	@objc private func focusDidChange()
	{
		updateRemovalVisibility()
	}

	private func updateRemovalVisibility()
	{
		let focusedView = window?.firstResponder as? NSView
		revealState.isKeyboardFocused = focusedView?.isDescendant(of: self) == true
		removeButton.alphaValue = revealState.isRevealed ? 1 : 0
	}
}
