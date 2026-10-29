import AppKit

@MainActor
final class ComposerQueueDragSession
{
	let row: ComposerQueueRow
	let placeholder: NSView
	let originalIDs: [UUID]
	let originalIndex: Int
	let firstCenter: CGFloat
	let grabOffset: CGFloat
	var settling = false

	init(
		row: ComposerQueueRow,
		placeholder: NSView,
		originalIDs: [UUID],
		originalIndex: Int,
		firstCenter: CGFloat,
		grabOffset: CGFloat
	)
	{
		self.row = row
		self.placeholder = placeholder
		self.originalIDs = originalIDs
		self.originalIndex = originalIndex
		self.firstCenter = firstCenter
		self.grabOffset = grabOffset
	}
}
