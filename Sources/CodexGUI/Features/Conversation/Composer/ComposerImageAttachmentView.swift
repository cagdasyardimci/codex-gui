import AppKit

@MainActor
final class ComposerImageAttachmentView: NSView
{
	private let removeButton: NSButton
	private var pointerTrackingArea: NSTrackingArea?

	init(
		image: NSImage?,
		previewButton: NSButton,
		removeButton: NSButton
	)
	{
		self.removeButton = removeButton
		super.init(frame: .zero)

		let imageView = NSImageView()
		imageView.image = image ?? DesktopIcons.image(.infoCircle)
		imageView.imageScaling = .scaleProportionallyUpOrDown
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
			widthAnchor.constraint(equalToConstant: 120),
			heightAnchor.constraint(equalToConstant: 120),
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
		isHovered = false
		updateRemovalVisibility()
	}

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		if let pointerTrackingArea
		{
			removeTrackingArea(pointerTrackingArea)
		}
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		addTrackingArea(area)
		pointerTrackingArea = area
	}

	private var isHovered = false

	override func mouseEntered(with event: NSEvent)
	{
		isHovered = true
		updateRemovalVisibility()
	}

	override func mouseExited(with event: NSEvent)
	{
		isHovered = false
		updateRemovalVisibility()
	}

	@objc private func focusDidChange()
	{
		updateRemovalVisibility()
	}

	private func updateRemovalVisibility()
	{
		let focusedView = window?.firstResponder as? NSView
		let hasKeyboardFocus = focusedView?.isDescendant(of: self) == true
		removeButton.alphaValue = isHovered || hasKeyboardFocus ? 1 : 0
	}
}
