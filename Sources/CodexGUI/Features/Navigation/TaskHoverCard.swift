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
		let visibleFrame = parent.screen?.visibleFrame ?? parent.frame
		let content = makeCardContent(availableSize: visibleFrame.size)
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

	private func makeCardContent(availableSize: NSSize) -> (surface: NSView, size: NSSize)
	{
		let titleLabel = NSTextField(wrappingLabelWithString: title)
		titleLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.title)
		titleLabel.textColor = AppKitColorTokens.primaryText
		constrainLabel(
			titleLabel,
			toLines: 3,
			role: TypographyTokens.TaskHover.title
		)
		titleLabel.setContentCompressionResistancePriority(
			.defaultLow,
			for: .horizontal
		)
		let timeLabel = NSTextField(labelWithString: relativeTime())
		timeLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.metadata)
		timeLabel.textColor = AppKitColorTokens.secondaryText
		applyLineHeight(
			to: timeLabel,
			role: TypographyTokens.TaskHover.metadata
		)
		let computer = NSImageView(image: NSImage(
			systemSymbolName: "laptopcomputer",
			accessibilityDescription: "This computer"
		) ?? NSImage())
		computer.contentTintColor = .secondaryLabelColor
		let metadata = AppKitLayout.horizontalStack(
			[computer, timeLabel],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)
		let header = AppKitLayout.horizontalStack(
			[titleLabel, NSView(), metadata],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)
		header.alignment = .top
		let folder = NSImageView(image: NSImage(
			systemSymbolName: "folder",
			accessibilityDescription: "Project"
		) ?? NSImage())
		folder.contentTintColor = .secondaryLabelColor
		let projectLabel = NSTextField(wrappingLabelWithString: projectName)
		projectLabel.font = AppKitFontResolver.font(TypographyTokens.TaskHover.project)
		projectLabel.textColor = AppKitColorTokens.primaryText
		constrainLabel(
			projectLabel,
			toLines: 2,
			role: TypographyTokens.TaskHover.project
		)
		let project = AppKitLayout.horizontalStack(
			[folder, projectLabel],
			spacing: LayoutTokens.TaskHover.projectSpacing
		)
		let stack = AppKitLayout.verticalStack(
			[header, project],
			spacing: LayoutTokens.TaskHover.rowSpacing
		)
		let surface = DesktopSurface(
			AppKitColorTokens.summaryCard,
			cornerRadius: ShapeTokens.TaskHover.cornerRadius,
			bordered: true,
			borderWidth: 0.5,
			borderColor: AppKitColorTokens.popoverEdge
		)
		surface.wantsLayer = true
		surface.layer?.cornerRadius = ShapeTokens.TaskHover.cornerRadius
		AppKitLayout.pin(
			stack,
			to: surface,
			inset: LayoutTokens.TaskHover.contentInset
		)
		let cardWidth = min(
			LayoutTokens.TaskHover.width,
			availableSize.width
		)
		surface.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
		header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		project.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
		for icon in [computer, folder]
		{
			icon.widthAnchor.constraint(equalToConstant: LayoutTokens.TaskHover.iconSize)
				.isActive = true
			icon.heightAnchor.constraint(equalToConstant: LayoutTokens.TaskHover.iconSize)
				.isActive = true
		}
		timeLabel.setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		surface.layoutSubtreeIfNeeded()
		let size = NSSize(
			width: cardWidth,
			height: min(
				availableSize.height,
				max(
					LayoutTokens.TaskHover.minimumHeight,
					surface.fittingSize.height
				)
			)
		)
		return (surface, size)
	}

	private func constrainLabel(
		_ label: NSTextField,
		toLines lines: Int,
		role: TypographyTokens.Role
	)
	{
		label.maximumNumberOfLines = lines
		label.lineBreakMode = .byWordWrapping
		label.cell?.truncatesLastVisibleLine = true
		applyLineHeight(
			to: label,
			role: role
		)
		// A natural line-height policy must not turn the multiline cap into two points.
		if let lineHeight = role.lineHeight
		{
			// fittingSize can measure every explicit newline despite the line limit.
			label.heightAnchor
				.constraint(lessThanOrEqualToConstant: lineHeight * CGFloat(lines) + 2)
				.isActive = true
		}
	}

	private func applyLineHeight(
		to label: NSTextField,
		role: TypographyTokens.Role
	)
	{
		let paragraph = NSMutableParagraphStyle()
		paragraph.minimumLineHeight = role.lineHeight ?? 0
		paragraph.maximumLineHeight = role.lineHeight ?? 0
		paragraph.lineBreakMode = label.lineBreakMode
		label.attributedStringValue = NSAttributedString(
			string: label.stringValue,
			attributes: AppKitFontResolver.textAttributes(
				role,
				font: label.font
			).merging(
				[
					.foregroundColor: label.textColor ?? AppKitColorTokens.primaryText,
					.paragraphStyle: paragraph,
				],
				uniquingKeysWith:
				{
					_, replacement in replacement
				}
			)
		)
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
		let cardOriginX = max(
			visibleScreenFrame.minX,
			min(
				rowScreenRect.maxX + 8,
				visibleScreenFrame.maxX - size.width
			)
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
