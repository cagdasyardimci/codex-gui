import AppKit

@MainActor
protocol DesktopControlCursorProviding: AnyObject
{
	var controlCursor: NSCursor
	{
		get
	}
}

/// Receives wheel input before AppKit chooses an enclosing scroll view.
@MainActor
protocol DesktopWheelInputReceiving: AnyObject
{
	func scrollWheel(with event: NSEvent)
}

@MainActor
final class DesktopWindow: NSWindow
{
	override func sendEvent(_ event: NSEvent)
	{
		if event.type == .scrollWheel, let contentView, let parent = contentView.superview
		{
			let point = parent.convert(
				event.locationInWindow,
				from: nil
			)
			var target = contentView.hitTest(point)
			while let view = target
			{
				if let receiver = view as? DesktopWheelInputReceiving
				{
					receiver.scrollWheel(with: event)
					updateControlCursor()
					return
				}
				target = view.superview
			}
		}
		super.sendEvent(event)
		switch event.type
		{
		case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate, .scrollWheel, .leftMouseUp:
			updateControlCursor()
		default:
			break
		}
	}

	private func updateControlCursor()
	{
		guard isKeyWindow, let contentView, let parent = contentView.superview
		else
		{
			return
		}
		let point = parent.convert(
			mouseLocationOutsideOfEventStream,
			from: nil
		)
		var target = contentView.hitTest(point)
		while let view = target
		{
			if let control = view as? DesktopControlCursorProviding
			{
				// TextKit can reset the cursor while the window dispatches the event.
				// Apply the actual control's cursor after that dispatch finishes.
				control.controlCursor.set()
				return
			}
			target = view.superview
		}
	}
}
