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

	func configurePresentation(
		selected: Bool,
		preview: Bool = false,
		file: Bool = false
	)
	{
		let selectionCell: ToolsTabSelectionButtonCell
		if let existing = cell as? ToolsTabSelectionButtonCell
		{
			selectionCell = existing
		}
		else
		{
			let previous = cell as? NSButtonCell
			selectionCell = ToolsTabSelectionButtonCell(textCell: title)
			if let previous
			{
				selectionCell.target = previous.target
				selectionCell.action = previous.action
				selectionCell.state = previous.state
				selectionCell.image = previous.image
				selectionCell.alternateImage = previous.alternateImage
				selectionCell.alternateTitle = previous.alternateTitle
				selectionCell.keyEquivalent = previous.keyEquivalent
				selectionCell.keyEquivalentModifierMask = previous.keyEquivalentModifierMask
				selectionCell.tag = previous.tag
				selectionCell.isEnabled = previous.isEnabled
				selectionCell.isContinuous = previous.isContinuous
				selectionCell.allowsMixedState = previous.allowsMixedState
				selectionCell.highlightsBy = previous.highlightsBy
				selectionCell.showsStateBy = previous.showsStateBy
			}
			cell = selectionCell
		}
		selectionCell.documentTitleGap = file ? 5 : 0
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(
			TypographyTokens.Controls.tab,
			italic: preview
		)
		contentTintColor = selected ? AppKitColorTokens.primaryText : AppKitColorTokens
			.secondaryText
		alignment = .left
		imagePosition = .imageLeading
		cell?.lineBreakMode = .byTruncatingTail
		setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		toolTip = toolTip ?? title
		setAccessibilityValue(selected ? "Selected" : "Not selected")
	}

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

@MainActor
final class ToolsTabSelectionButtonCell: NSButtonCell
{
	var documentTitleGap: CGFloat = 0

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		let title = super.titleRect(forBounds: rect)
		return NSRect(
			x: title.minX + documentTitleGap,
			y: title.minY,
			width: max(
				0,
				title.width - documentTitleGap
			),
			height: title.height
		)
	}

	override func drawTitle(
		_ title: NSAttributedString,
		withFrame frame: NSRect,
		in controlView: NSView
	) -> NSRect
	{
		DesktopTextRendering.withFontSmoothingDisabled
		{
			super.drawTitle(
				title,
				withFrame: frame,
				in: controlView
			)
		}
	}
}

enum ToolsChangesShortcut
{
	static let key = "g"
	static let modifiers: NSEvent.ModifierFlags = [.control, .shift]
	static let label = "⌃⇧G"
}
