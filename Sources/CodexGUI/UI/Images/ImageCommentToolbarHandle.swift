import AppKit

/// Routes pointer and keyboard movement; presentation remains with the shared button.
@MainActor
final class ImageCommentToolbarHandle: DesktopActionButton
{
	var onMove: ((NSSize) -> Void)?
	var onReset: (() -> Void)?
	private var previousPoint: NSPoint?

	init()
	{
		super.init(
			title: "",
			presentation: .imageCommentHandle
		)
		image = DesktopIcons.imageCommentGrip()
		keyboardFocusPolicy = .dialog
		setAccessibilityLabel("Move toolbar")
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func mouseDown(with event: NSEvent)
	{
		window?.makeFirstResponder(self)
		previousPoint = event.locationInWindow
	}

	override func mouseDragged(with event: NSEvent)
	{
		guard let previousPoint
		else
		{
			return
		}
		let point = event.locationInWindow
		self.previousPoint = point
		onMove?(NSSize(
			width: point.x - previousPoint.x,
			height: point.y - previousPoint.y
		))
	}

	override func mouseUp(with event: NSEvent)
	{
		previousPoint = nil
	}

	override func keyDown(with event: NSEvent)
	{
		switch event.keyCode
		{
		case 123: onMove?(NSSize(
				width: -10,
				height: 0
			))
		case 124: onMove?(NSSize(
				width: 10,
				height: 0
			))
		case 125: onMove?(NSSize(
				width: 0,
				height: -10
			))
		case 126: onMove?(NSSize(
				width: 0,
				height: 10
			))
		case 115: onReset?()
		default: super.keyDown(with: event)
		}
	}
}
