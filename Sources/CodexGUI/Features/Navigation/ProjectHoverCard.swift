import AppKit

/// Reuses the project-info content for a hover card without selecting its project.
@MainActor
final class ProjectHoverCard
{
	let content = ProjectInfoPopoverView(frame: .zero)
	private let preview = DesktopHoverPreview()
	private let lifetime = DesktopPanelLifetime()
	private weak var hoverAnchor: NSView?
	private lazy var surface = ProjectHoverSurface(content: content)
	var panel: NSPanel?
	{
		preview.panel
	}

	var pendingDismissal: Task<Void, Never>?
	{
		preview.pendingDismissal
	}

	init(
		project: URL,
		name: String,
		isPinned: Bool,
		loadedTaskCount: Int?,
		activeTaskCount: Int?,
		onTogglePin: @escaping () -> Void,
		onEditProject: @escaping () -> Void
	)
	{
		content.render(
			project: project,
			name: name,
			isPinned: isPinned,
			loadedTaskCount: loadedTaskCount,
			activeTaskCount: activeTaskCount
		)
		content.onTogglePin =
		{
			[weak self] in self?.dismiss(); onTogglePin()
		}
		content.onOpenProject =
		{
			[weak self] in self?.dismiss(); NSWorkspace.shared.open(project)
		}
		content.onEditProject =
		{
			[weak self] in self?.dismiss(); onEditProject()
		}
		surface.onEnter =
		{
			[weak self] in self?.preview.cancelScheduledDismissal()
		}
		surface.onExit =
		{
			[weak self] in self?.scheduleDismissal()
		}
	}

	func show(beside anchor: NSView)
	{
		preview.cancelScheduledDismissal()
		guard panel == nil, let parent = anchor.window
		else
		{
			return
		}
		hoverAnchor = anchor
		preview.present(
			surface,
			relativeTo: anchor,
			placement: .besideTop,
			interaction: .interactive
		)
		panel?.hasShadow = false
		for name in [NSWindow.didResignKeyNotification,
						NSWindow.willCloseNotification,
						NSWindow.willMoveNotification,
						NSWindow.didResizeNotification]
		{
			lifetime.addObserver(
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
		if let clip = anchor.enclosingScrollView?.contentView
		{
			clip.postsBoundsChangedNotifications = true
			lifetime.addObserver(
				forName: NSView.boundsDidChangeNotification,
				object: clip,
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
		lifetime.monitorLocalEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown])
		{
			[weak self] event in
			if event.type == .keyDown || event.window !== self?.panel
			{
				self?.dismiss()
			}
			return event
		}
	}

	func scheduleDismissal()
	{
		preview.scheduleDismissal(
			after: .milliseconds(350),
			shouldDismiss:
			{
				[weak self] in self?.containsPointer != true
			},
			onDismiss:
			{
				[weak self] in
				self?.hoverAnchor = nil
				self?.lifetime.invalidate()
			}
		)
	}

	private var containsPointer: Bool
	{
		let pointer = NSEvent.mouseLocation
		if let panel, panel.isVisible, panel.frame.contains(pointer)
		{
			return true
		}
		guard let hoverAnchor, !hoverAnchor.isHiddenOrHasHiddenAncestor,
				let window = hoverAnchor.window
		else
		{
			return false
		}
		let anchorRect = window.convertToScreen(hoverAnchor.convert(
			hoverAnchor.visibleRect,
			to: nil
		))
		return anchorRect.contains(pointer)
	}

	func dismiss()
	{
		hoverAnchor = nil
		lifetime.invalidate()
		preview.dismiss()
	}
}

@MainActor
private final class ProjectHoverSurface: DesktopHoverPreviewSurface
{
	var onEnter: (() -> Void)?
	var onExit: (() -> Void)?
	private var tracking: NSTrackingArea?

	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
		)
	}

	override func mouseEntered(with event: NSEvent)
	{
		onEnter?()
	}
	override func mouseExited(with event: NSEvent)
	{
		onExit?()
	}
}
