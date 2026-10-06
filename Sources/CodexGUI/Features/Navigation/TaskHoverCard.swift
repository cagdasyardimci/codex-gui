import AppKit

/// A passive child window keeps the card beside the row without taking focus.
@MainActor
final class TaskHoverCard
{
	let title: String
	let projectName: String
	let updatedAt: Date?
	private(set) var panel: NSPanel?
	private var appearanceBinding: DesktopPanelAppearanceBinding?

	init(
		title: String,
		projectName: String,
		updatedAt: Date?
	)
	{
		self.title = title
		self.projectName = projectName
		self.updatedAt = updatedAt
	}

	func show(beside view: NSView)
	{
		guard panel == nil, let parent = view.window
		else
		{
			return
		}
		let content = makeCardContent()
		let card = makePanel(
			content: content.surface,
			size: content.size
		)
		positionCard(
			card,
			beside: view,
			in: parent,
			size: content.size
		)
		parent.addChildWindow(
			card,
			ordered: .above
		)
		appearanceBinding = DesktopPanelAppearanceBinding(
			panel: card,
			source: view
		)
		card.orderFront(nil)
		panel = card
	}

	private func makeCardContent() -> (surface: NSView, size: NSSize)
	{
		let titleLabel = NSTextField(wrappingLabelWithString: title)
		titleLabel.font = .systemFont(ofSize: 14)
		let timeLabel = NSTextField(labelWithString: relativeTime())
		timeLabel.font = .systemFont(ofSize: 12)
		timeLabel.textColor = .secondaryLabelColor
		let computer = NSImageView(image: NSImage(
			systemSymbolName: "laptopcomputer",
			accessibilityDescription: "This computer"
		) ?? NSImage())
		computer.contentTintColor = .secondaryLabelColor
		let header = AppKitLayout.horizontalStack(
			[titleLabel, computer, NSView(), timeLabel],
			spacing: 8
		)
		let folder = NSImageView(image: NSImage(
			systemSymbolName: "folder",
			accessibilityDescription: "Project"
		) ?? NSImage())
		folder.contentTintColor = .secondaryLabelColor
		let projectLabel = NSTextField(wrappingLabelWithString: projectName)
		projectLabel.font = .systemFont(ofSize: 13)
		let project = AppKitLayout.horizontalStack(
			[folder, projectLabel],
			spacing: 7
		)
		let stack = AppKitLayout.verticalStack(
			[header, project],
			spacing: 8
		)
		let surface = DesktopSurface(
			.controlBackgroundColor,
			cornerRadius: 12,
			bordered: true,
			borderColor: .separatorColor
		)
		surface.wantsLayer = true
		surface.layer?.cornerRadius = 12
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: 10
		)
		let cardWidth = min(
			480,
			max(
				300,
				titleLabel.intrinsicContentSize.width + 100
			)
		)
		surface.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for icon in [computer, folder]
		{
			icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
			icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
		}
		timeLabel.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		surface.layoutSubtreeIfNeeded()
		let size = NSSize(
			width: cardWidth,
			height: max(
				60,
				surface.fittingSize.height
			)
		)
		return (surface, size)
	}

	private func makePanel(
		content: NSView,
		size: NSSize
	) -> NSPanel
	{
		let card = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		card.isOpaque = false
		card.backgroundColor = .clear
		card.hasShadow = true
		card.ignoresMouseEvents = true
		card.isReleasedWhenClosed = false
		card.animationBehavior = .none
		card.contentView = content
		return card
	}

	private func positionCard(
		_ card: NSPanel,
		beside view: NSView,
		in parent: NSWindow,
		size: NSSize
	)
	{
		let rowScreenRect = parent.convertToScreen(view.convert(
			view.bounds,
			to: nil
		))
		let visibleScreenFrame = parent.screen?.visibleFrame ?? rowScreenRect
		let cardOriginX = min(
			rowScreenRect.maxX + 8,
			visibleScreenFrame.maxX - size.width
		)
		let cardOriginY = max(
			visibleScreenFrame.minY,
			min(
				rowScreenRect.maxY - size.height,
				visibleScreenFrame.maxY - size.height
			)
		)
		card.setFrameOrigin(NSPoint(
			x: cardOriginX,
			y: cardOriginY
		))
	}

	func dismiss()
	{
		guard let panel
		else
		{
			return
		}
		appearanceBinding?.invalidate()
		appearanceBinding = nil
		panel.parent?.removeChildWindow(panel)
		panel.orderOut(nil)
		self.panel = nil
	}

	private func relativeTime() -> String
	{
		guard let updatedAt
		else
		{
			return ""
		}
		let seconds = max(
			0,
			Int(Date().timeIntervalSince(updatedAt))
		)
		if seconds < 60
		{
			return "now"
		}
		if seconds < 3600
		{
			return "\(seconds / 60)m"
		}
		if seconds < 86400
		{
			return "\(seconds / 3600)h"
		}
		return "\(seconds / 86400)d"
	}
}
