import AppKit

/// One text tooltip presentation for desktop controls, including wrapping and screen placement.
@MainActor
final class DesktopTooltip
{
	enum Style
	{
		case standard, capsule, control

		var isCapsule: Bool
		{
			self != .standard
		}
		var typography: TypographyTokens.Role
		{
			self == .capsule ? TypographyTokens.Tooltip.capsule : TypographyTokens.Tooltip.control
		}
	}
	enum Placement
	{
		case above, below, right
	}
	var style: Style
	var placement: Placement = .above
	var anchorGap: CGFloat?
	var shortcut: String?
	private let lifetime = DesktopPanelLifetime()

	init(style: Style = .standard)
	{
		self.style = style
	}

	private static weak var activeCapsule: DesktopTooltip?
	static let delay: Duration = .milliseconds(350)
	private let presentation = DesktopDelayedPresentation()

	var task: Task<Void, Never>?
	{
		presentation.task
	}

	var panel: NSPanel?
	{
		presentation.panel
	}

	var isVisible: Bool
	{
		panel?.isVisible == true
	}

	func show(
		_ text: String,
		relativeTo anchor: NSView,
		immediately: Bool = false,
		when eligible: @escaping @MainActor () -> Bool =
		{
			true
		}
	)
	{
		dismiss()
		if style.isCapsule
		{
			Self.activeCapsule?.dismiss()
			Self.activeCapsule = self
		}
		presentation.schedule(after: immediately ? .zero : Self.delay)
		{
			[weak self, weak anchor] in
			guard let self, let anchor, let parent = anchor.window,
					!anchor.isHiddenOrHasHiddenAncestor, eligible(), !text.isEmpty
			else
			{
				return
			}
			let surface = DesktopTooltipView(
				text: text,
				style: self.style,
				shortcut: self.shortcut
			)
			let anchorRect = parent.convertToScreen(anchor.convert(
				anchor.bounds,
				to: nil
			))
			let screen = parent.screen?.visibleFrame ?? parent.frame
			let size = surface.measuredSize(maximumWidth: min(
				self.style.isCapsule ? LayoutTokens.Tooltip.Capsule.maximumWidth : 280,
				max(
					40,
					screen.width - 16
				)
			))
			let gap = self
				.anchorGap ?? (self.style.isCapsule ? LayoutTokens.Tooltip.Capsule.anchorGap : 6)
			let origin = Self.origin(
				for: size,
				anchor: anchorRect,
				screen: screen,
				placement: self.placement,
				gap: gap
			)
			let shadowOutset: CGFloat = self.style.isCapsule ? LayoutTokens.Tooltip.Capsule
				.shadowOutset : 0
			let panel = NSPanel(
				contentRect: NSRect(
					origin: origin,
					size: size
				).insetBy(
					dx: -shadowOutset,
					dy: -shadowOutset
				),
				styleMask: [.borderless, .nonactivatingPanel],
				backing: .buffered,
				defer: false
			)
			panel.isOpaque = false
			panel.backgroundColor = .clear
			panel.hasShadow = self.style == .standard
			panel.ignoresMouseEvents = true
			panel.isReleasedWhenClosed = false
			panel.animationBehavior = .none
			if shadowOutset > 0
			{
				let root = NSView(frame: NSRect(
					origin: .zero,
					size: panel.frame.size
				))
				surface.frame.origin = NSPoint(
					x: shadowOutset,
					y: shadowOutset
				)
				root.addSubview(surface)
				panel.contentView = root
			}
			else
			{
				panel.contentView = surface
			}
			// Ordering a child of an unshown window can select the parent's initial responder.
			// A passive tooltip follows its owner's visibility.
			for name in [
				NSWindow.didResignKeyNotification,
				NSWindow.willCloseNotification,
				NSWindow.didMiniaturizeNotification
			]
			{
				self.lifetime.addObserver(
					forName: name,
					object: parent,
					queue: .main
				)
				{
					[weak self] _ in
					MainActor.assumeIsolated
					{
						self?.dismiss()
					}
				}
			}
			self.lifetime.monitorLocalEvents(matching: [
				.keyDown,
				.leftMouseDown,
				.rightMouseDown,
				.scrollWheel
			])
			{
				[weak self, weak parent] event in
				if event.window === parent
				{
					let dismissesWithEscape = event.type == .keyDown && event.keyCode == 53
					self?.dismiss()
					if dismissesWithEscape
					{
						return nil
					}
				}
				return event
			}
			self.presentation.attach(
				panel,
				to: parent,
				appearanceSource: anchor,
				orderFront: parent.isVisible
			)
		}
	}

	static func origin(
		for size: NSSize,
		anchor: NSRect,
		screen: NSRect,
		placement: Placement,
		gap: CGFloat
	) -> NSPoint
	{
		let safe = screen.insetBy(
			dx: 8,
			dy: 8
		)
		var point: NSPoint
		switch placement
		{
		case .above, .below:
			let fitsAbove = anchor.maxY + gap + size.height <= safe.maxY
			let fitsBelow = anchor.minY - gap - size.height >= safe.minY
			let above = placement == .above ? fitsAbove || !fitsBelow : !fitsBelow && fitsAbove
			point = NSPoint(
				x: anchor.midX - size.width / 2,
				y: above ? anchor.maxY + gap : anchor.minY - gap - size.height
			)
		case .right:
			point = NSPoint(
				x: anchor.maxX + gap + size.width <= safe.maxX ? anchor.maxX + gap : anchor
					.minX - gap - size.width,
				y: anchor.midY - size.height / 2
			)
		}
		return NSPoint(
			x: max(
				safe.minX,
				min(
					point.x,
					safe.maxX - size.width
				)
			),
			y: max(
				safe.minY,
				min(
					point.y,
					safe.maxY - size.height
				)
			)
		)
	}

	func dismiss()
	{
		lifetime.invalidate()
		presentation.dismiss()
	}
}

@MainActor
final class DesktopTooltipView: DesktopSurface
{
	let label: NSTextField
	private let style: DesktopTooltip.Style
	let shortcutBadge: DesktopSurface?
	private let shortcutLabel: NSTextField?

	init(
		text: String,
		style: DesktopTooltip.Style = .standard,
		shortcut: String? = nil
	)
	{
		self.style = style
		if style.isCapsule, let shortcut, !shortcut.isEmpty
		{
			shortcutBadge = DesktopSurface(
				.white.withAlphaComponent(0.25),
				cornerRadius: 12.5
			)
			shortcutLabel = DesktopTextField(labelWithString: shortcut)
		}
		else
		{
			shortcutBadge = nil
			shortcutLabel = nil
		}
		label = style.isCapsule ? DesktopTextField(wrappingLabelWithString: text) :
			NSTextField(wrappingLabelWithString: text)
		super.init(
			style.isCapsule ? AppKitColorTokens.tooltipCapsule : AppKitColorTokens.inspector,
			cornerRadius: style.isCapsule ? ShapeTokens.Tooltip.capsuleRadius : 12,
			cornerCurve: style.isCapsule ? .superellipse(1.5) : .circular,
			bordered: true,
			borderColor: style.isCapsule ? NSColor.white.withAlphaComponent(0.05) : nil,
			shadows: style.isCapsule ? [ShadowTokens.tooltipCapsule] : []
		)
		label.font = style.isCapsule ? AppKitFontResolver
			.font(style.typography) : .systemFont(ofSize: 12)
		label.textColor = style.isCapsule ? .white : .labelColor
		if style.isCapsule
		{
			let typography = style.typography
			var attributes = AppKitFontResolver.textAttributes(
				typography,
				font: label.font
			)
			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = .center
			paragraph.minimumLineHeight = typography.lineHeight!
			paragraph.maximumLineHeight = typography.lineHeight!
			attributes[.paragraphStyle] = paragraph
			attributes[.foregroundColor] = NSColor.white
			label.attributedStringValue = NSAttributedString(
				string: text,
				attributes: attributes
			)
		}
		label.isSelectable = false
		label.maximumNumberOfLines = 0
		label.lineBreakMode = .byWordWrapping
		addSubview(label)
		if let shortcutBadge, let shortcutLabel
		{
			shortcutLabel.font = label.font
			shortcutLabel.textColor = .white
			shortcutLabel.attributedStringValue = NSAttributedString(
				string: shortcutLabel.stringValue,
				attributes: AppKitFontResolver.textAttributes(
					style.typography,
					font: label.font
				)
				.merging([.foregroundColor: NSColor.white])
				{
					_, new in new
				}
			)
			shortcutBadge.addSubview(shortcutLabel)
			addSubview(shortcutBadge)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func measuredSize(maximumWidth: CGFloat) -> NSSize
	{
		if style.isCapsule
		{
			let horizontalInset = LayoutTokens.Tooltip.Capsule.horizontalInset
			let verticalInset = LayoutTokens.Tooltip.Capsule.verticalInset
			let natural = Self.alignmentSize(of: label).width
			let badgeWidth = shortcutLabel.map
			{
				Self.alignmentSize(of: $0).width + 12
			} ?? 0
			let badgeSpace: CGFloat = shortcutBadge == nil ? 0 : badgeWidth + 8 - 7
			let textWidth = min(
				natural,
				max(
					16,
					maximumWidth - 2 * horizontalInset - badgeSpace
				)
			)
			let textHeight = max(
				style.typography.lineHeight!,
				Self.alignmentSize(
					of: label,
					maximumWidth: textWidth
				).height
			)
			let size = NSSize(
				width: textWidth + badgeSpace + 2 * horizontalInset,
				height: textHeight + 2 * verticalInset
			)
			frame = NSRect(
				origin: .zero,
				size: size
			)
			label.frame = label.frame(forAlignmentRect: NSRect(
				x: horizontalInset,
				y: verticalInset,
				width: textWidth,
				height: textHeight
			))
			if let shortcutBadge, let shortcutLabel
			{
				shortcutBadge.frame = NSRect(
					x: horizontalInset + textWidth + 8,
					y: size.height / 2 - 9,
					width: badgeWidth,
					height: 18
				)
				shortcutLabel.frame = shortcutLabel.frame(forAlignmentRect: NSRect(
					x: 6,
					y: 0,
					width: badgeWidth - 12,
					height: 18
				))
			}
			return size
		}
		let textWidth = max(
			16,
			min(
				Self.alignmentSize(of: label).width,
				maximumWidth - 24
			)
		)
		let textHeight = Self.alignmentSize(
			of: label,
			maximumWidth: textWidth
		).height
		let size = NSSize(
			width: ceil(textWidth) + 24,
			height: max(
				28,
				textHeight + 14
			)
		)
		frame = NSRect(
			origin: .zero,
			size: size
		)
		label.frame = label.frame(forAlignmentRect: NSRect(
			x: 12,
			y: (size.height - textHeight) / 2,
			width: textWidth,
			height: textHeight
		))
		return size
	}

	private static func alignmentSize(
		of label: NSTextField,
		maximumWidth: CGFloat = .greatestFiniteMagnitude
	) -> NSSize
	{
		let insets = label.alignmentRectInsets
		let cellWidth = maximumWidth == .greatestFiniteMagnitude ? maximumWidth :
			maximumWidth + insets.left + insets.right
		// Measure the same cell that draws the text, including its internal wrapping space.
		let size = label.cell!.cellSize(forBounds: NSRect(
			x: 0,
			y: 0,
			width: cellWidth,
			height: .greatestFiniteMagnitude
		))
		return NSSize(
			width: ceil(size.width) - insets.left - insets.right,
			height: ceil(size.height) - insets.top - insets.bottom
		)
	}
}
