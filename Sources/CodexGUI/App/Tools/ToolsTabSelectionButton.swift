import AppKit

struct ToolsTabDragPayload: Equatable
{
	let ownerID: UUID
	let tabID: UUID

	init?(string: String)
	{
		let parts = string.split(
			separator: ":",
			omittingEmptySubsequences: false
		)
		guard parts.count == 2,
				let ownerID = UUID(uuidString: String(parts[0])),
				let tabID = UUID(uuidString: String(parts[1]))
		else
		{
			return nil
		}
		self.ownerID = ownerID
		self.tabID = tabID
	}

	init(
		ownerID: UUID,
		tabID: UUID
	)
	{
		self.ownerID = ownerID
		self.tabID = tabID
	}

	var string: String
	{
		ownerID.uuidString + ":" + tabID.uuidString
	}

	func isOwned(
		by destinationID: UUID,
		source: ToolsTabDragPayload?
	) -> Bool
	{
		ownerID == destinationID && source == self
	}
}

@MainActor
final class ToolsTabSelectionButton: NSButton, NSDraggingSource
{
	var onNavigate: ((UInt16) -> Bool)?
	var onDoubleClick: (() -> Void)?
	var draggedID: UUID?
	var dragOwner: UUID?
	private static let dragThreshold: CGFloat = 4

	override func mouseDown(with event: NSEvent)
	{
		guard draggedID != nil, dragOwner != nil, let window
		else
		{
			super.mouseDown(with: event)
			return
		}
		window.makeFirstResponder(self)
		highlight(true)
		defer
		{
			highlight(false)
		}
		let start = event.locationInWindow
		while let next = window.nextEvent(
			matching: [.leftMouseDragged, .leftMouseUp],
			until: .distantFuture,
			inMode: .eventTracking,
			dequeue: true
		)
		{
			if next.type == .leftMouseUp
			{
				guard bounds.contains(convert(
					next.locationInWindow,
					from: nil
				)), isEnabled,
				let action
				else
				{
					return
				}
				_ = NSApp.sendAction(
					action,
					to: target,
					from: self
				)
				if event.clickCount == 2
				{
					onDoubleClick?()
				}
				return
			}
			let distance = hypot(
				next.locationInWindow.x - start.x,
				next.locationInWindow.y - start.y
			)
			if distance >= Self.dragThreshold
			{
				beginTabDrag(with: next)
				return
			}
		}
	}

	private func beginTabDrag(with event: NSEvent)
	{
		guard let draggedID, let dragOwner, let surface = superview as? ToolsTabSurface
		else
		{
			return
		}
		let payload = ToolsTabDragPayload(
			ownerID: dragOwner,
			tabID: draggedID
		)
		let pasteboard = NSPasteboardItem()
		pasteboard.setString(
			payload.string,
			forType: ToolsTabSurface.dragType
		)
		let item = NSDraggingItem(pasteboardWriter: pasteboard)
		guard let bitmap = surface.bitmapImageRepForCachingDisplay(in: surface.bounds)
		else
		{
			return
		}
		let image = NSImage(size: surface.bounds.size)
		surface.cacheDisplay(
			in: surface.bounds,
			to: bitmap
		)
		image.addRepresentation(bitmap)
		item.setDraggingFrame(
			convert(
				surface.bounds,
				from: surface
			),
			contents: image
		)
		beginDraggingSession(
			with: [item],
			event: event,
			source: self
		)
	}

	func draggingSession(
		_ session: NSDraggingSession,
		sourceOperationMaskFor context: NSDraggingContext
	) -> NSDragOperation
	{
		.move
	}

	override func keyDown(with event: NSEvent)
	{
		if onNavigate?(event.keyCode) == true
		{
			return
		}
		super.keyDown(with: event)
	}
}
