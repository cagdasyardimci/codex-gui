import AppKit

/// One text tooltip presentation for desktop controls, including wrapping and screen placement.
@MainActor
final class DesktopTooltip
{
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
		when eligible: @escaping @MainActor () -> Bool =
		{
			true
		}
	)
	{
		dismiss()
		presentation.schedule(after: Self.delay)
		{
			[weak self, weak anchor] in
			guard let self, let anchor, let parent = anchor.window,
					!anchor.isHiddenOrHasHiddenAncestor, eligible(), !text.isEmpty
			else
			{
				return
			}
			let surface = DesktopTooltipView(text: text)
			let anchorRect = parent.convertToScreen(anchor.convert(
				anchor.bounds,
				to: nil
			))
			let screen = parent.screen?.visibleFrame ?? parent.frame
			let size = surface.measuredSize(maximumWidth: min(
				280,
				max(
					40,
					screen.width - 16
				)
			))
			let above = anchorRect.maxY + 6
			let origin = NSPoint(
				x: max(
					screen.minX + 8,
					min(
						anchorRect.midX - size.width / 2,
						screen.maxX - size.width - 8
					)
				),
				y: max(
					screen.minY + 8,
					above + size.height <= screen.maxY - 8
						? above : anchorRect.minY - size.height - 6
				)
			)
			let panel = NSPanel(
				contentRect: NSRect(
					origin: origin,
					size: size
				),
				styleMask: [.borderless, .nonactivatingPanel],
				backing: .buffered,
				defer: false
			)
			panel.isOpaque = false
			panel.backgroundColor = .clear
			panel.hasShadow = true
			panel.ignoresMouseEvents = true
			panel.isReleasedWhenClosed = false
			panel.animationBehavior = .none
			panel.contentView = surface
			// Ordering a child of an unshown window can select the parent's initial responder.
			// A passive tooltip follows its owner's visibility.
			self.presentation.attach(
				panel,
				to: parent,
				appearanceSource: anchor,
				orderFront: parent.isVisible
			)
		}
	}

	func dismiss()
	{
		presentation.dismiss()
	}
}

@MainActor
final class DesktopTooltipView: DesktopSurface
{
	let label: NSTextField

	init(text: String)
	{
		label = NSTextField(wrappingLabelWithString: text)
		super.init(
			AppKitColorTokens.inspector,
			cornerRadius: 12,
			bordered: true
		)
		label.font = .systemFont(ofSize: 12)
		label.textColor = .labelColor
		label.isSelectable = false
		label.maximumNumberOfLines = 0
		label.lineBreakMode = .byWordWrapping
		addSubview(label)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func measuredSize(maximumWidth: CGFloat) -> NSSize
	{
		let font = label.font ?? .systemFont(ofSize: 12)
		let natural = (label.stringValue as NSString).size(withAttributes: [.font: font]).width
		let textWidth = max(
			16,
			min(
				natural,
				maximumWidth - 24
			)
		)
		let textHeight = ceil((label.stringValue as NSString).boundingRect(
			with: NSSize(
				width: textWidth,
				height: .greatestFiniteMagnitude
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading],
			attributes: [.font: font]
		).height)
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
		label.frame = NSRect(
			x: 12,
			y: (size.height - textHeight) / 2,
			width: textWidth,
			height: textHeight
		)
		return size
	}
}
