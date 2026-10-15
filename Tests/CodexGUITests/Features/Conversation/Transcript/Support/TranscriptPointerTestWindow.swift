import AppKit

/// Supplies fixture-owned pointer state for direct tracking callbacks.
@MainActor
final class TranscriptPointerTestWindow: NSWindow
{
	var pointerLocation = NSPoint(
		x: 92,
		y: 52
	)

	override var mouseLocationOutsideOfEventStream: NSPoint
	{
		pointerLocation
	}

	override func sendEvent(_ event: NSEvent)
	{
		// Physical pointer events must not alter this synthetic scenario across awaits.
		if [.mouseEntered, .mouseExited, .mouseMoved].contains(event.type)
		{
			return
		}
		super.sendEvent(event)
	}
}
