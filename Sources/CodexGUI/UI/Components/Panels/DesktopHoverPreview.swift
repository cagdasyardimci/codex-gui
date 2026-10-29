import AppKit

/// A rich preview's shared surface and content slot; feature views supply only their content.
@MainActor
class DesktopHoverPreviewSurface: DesktopSurface
{
	static let preferredWidth: CGFloat = 320
	static let contentInset: CGFloat = 10
	static let minimumHeight: CGFloat = 60

	init(frame: NSRect = .zero)
	{
		super.init(
			AppKitColorTokens.summaryCard,
			cornerRadius: 12,
			bordered: true,
			borderWidth: 0.5,
			borderColor: AppKitColorTokens.popoverEdge
		)
		self.frame = frame
		wantsLayer = true
		layer?.cornerRadius = 12
		refreshSurfaceColor()
	}

	convenience init(content: NSView)
	{
		self.init()
		installContent(content)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshSurfaceColor()
	}

	private func refreshSurfaceColor()
	{
		layer?.backgroundColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.summaryCard,
			for: self
		)
	}

	func installContent(_ content: NSView)
	{
		AppKitLayout.pin(
			content,
			to: self,
			inset: Self.contentInset
		)
	}
}

/// Places and retires passive or interactive rich previews using one screen-bounded shell.
@MainActor
final class DesktopHoverPreview
{
	enum Placement
	{
		case below, besideTop, besideCentered
	}

	enum Interaction
	{
		case passive, interactive
	}

	private let presentation = DesktopDelayedPresentation()
	private weak var anchor: NSView?
	private var placement: Placement = .below
	private(set) var pendingDismissal: Task<Void, Never>?

	var panel: NSPanel?
	{
		presentation.panel
	}

	func present(
		content: NSView,
		relativeTo anchor: NSView,
		placement: Placement
	)
	{
		present(
			DesktopHoverPreviewSurface(content: content),
			relativeTo: anchor,
			placement: placement
		)
	}

	func present(
		_ surface: DesktopHoverPreviewSurface,
		relativeTo anchor: NSView,
		placement: Placement,
		interaction: Interaction = .passive,
		height: CGFloat? = nil
	)
	{
		guard let parent = anchor.window
		else
		{
			return
		}
		dismiss()
		self.anchor = anchor
		self.placement = placement
		let screen = parent.screen?.visibleFrame ?? parent.frame
		let width = min(
			DesktopHoverPreviewSurface.preferredWidth,
			max(
				40,
				screen.width - 16
			)
		)
		surface.frame.size.width = width
		let widthConstraint = surface.widthAnchor.constraint(equalToConstant: width)
		widthConstraint.isActive = true
		surface.layoutSubtreeIfNeeded()
		let size = NSSize(
			width: width,
			height: min(
				screen.height - 16,
				max(
					DesktopHoverPreviewSurface.minimumHeight,
					height ?? ceil(surface.fittingSize.height)
				)
			)
		)
		let panel = NSPanel(
			contentRect: NSRect(
				origin: .zero,
				size: size
			),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.ignoresMouseEvents = interaction == .passive
		panel.isReleasedWhenClosed = false
		panel.animationBehavior = .none
		panel.hidesOnDeactivate = true
		panel.contentView = surface
		position(
			panel,
			size: size
		)
		presentation.attach(
			panel,
			to: parent,
			appearanceSource: anchor
		)
	}

	func resize(height: CGFloat)
	{
		guard let panel
		else
		{
			return
		}
		position(
			panel,
			size: NSSize(
				width: panel.frame.width,
				height: height
			)
		)
	}

	private func position(
		_ panel: NSPanel,
		size requestedSize: NSSize
	)
	{
		guard let anchor, let parent = anchor.window
		else
		{
			return
		}
		let screen = parent.screen?.visibleFrame ?? parent.frame
		let rect = parent.convertToScreen(anchor.convert(
			anchor.bounds,
			to: nil
		))
		let size = NSSize(
			width: min(
				requestedSize.width,
				screen.width - 16
			),
			height: min(
				requestedSize.height,
				screen.height - 16
			)
		)
		let requestedOrigin: NSPoint
		switch placement
		{
		case .below:
			requestedOrigin = NSPoint(
				x: rect.minX,
				y: rect.minY - size.height - 6
			)
		case .besideTop:
			requestedOrigin = NSPoint(
				x: rect.maxX + 6,
				y: rect.maxY - size.height
			)
		case .besideCentered:
			requestedOrigin = NSPoint(
				x: rect.maxX + 6,
				y: rect.midY - size.height / 2
			)
		}
		let origin = NSPoint(
			x: max(
				screen.minX + 8,
				min(
					requestedOrigin.x,
					screen.maxX - size.width - 8
				)
			),
			y: max(
				screen.minY + 8,
				min(
					requestedOrigin.y,
					screen.maxY - size.height - 8
				)
			)
		)
		panel.setFrame(
			NSRect(
				origin: origin,
				size: size
			),
			display: true
		)
	}

	func scheduleDismissal(
		after delay: Duration = .milliseconds(200),
		shouldDismiss: @escaping @MainActor () -> Bool =
		{
			true
		},
		onDismiss: @escaping @MainActor () -> Void
	)
	{
		cancelScheduledDismissal()
		pendingDismissal = Task
		{
			[weak self] in
			do
			{
				try await Task.sleep(for: delay)
			}
			catch
			{
				return
			}
			guard !Task.isCancelled, let self
			else
			{
				return
			}
			self.pendingDismissal = nil
			guard shouldDismiss()
			else
			{
				return
			}
			self.dismiss()
			onDismiss()
		}
	}

	func cancelScheduledDismissal()
	{
		pendingDismissal?.cancel()
		pendingDismissal = nil
	}

	func dismiss()
	{
		cancelScheduledDismissal()
		presentation.dismiss()
		anchor = nil
	}
}
