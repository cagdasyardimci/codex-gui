import AppKit

/// Arrowless search panels have an explicit viewport independent of their contents' fitting size.
@MainActor
final class DesktopSearchPanel: NSObject
{
	enum Placement
	{
		case centered, belowAnchor
	}

	var onKeyDown: ((NSEvent) -> Bool)?
	private let controller: NSViewController
	private let placement: Placement
	private let requestedSize: NSSize
	private let panel = SearchPanelWindow(
		contentRect: .zero,
		styleMask: [.borderless, .nonactivatingPanel],
		backing: .buffered,
		defer: true
	)
	private weak var anchor: NSView?
	private weak var parentWindow: NSWindow?
	private weak var anchorSuperview: NSView?
	private var attachmentObserver: SearchPanelAnchorObserver?
	private weak var previousResponder: NSResponder?
	private var appearanceBinding: DesktopPanelAppearanceBinding?
	private var eventMonitor: Any?
	private var dimmer: NSView?
	private(set) var isShown = false

	init(
		controller: NSViewController,
		placement: Placement,
		size: NSSize
	)
	{
		self.controller = controller
		self.placement = placement
		requestedSize = size
		super.init()
		panel.isReleasedWhenClosed = false
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = true
		panel.animationBehavior = .none
		panel.contentViewController = controller
		controller.view.wantsLayer = true
		controller.view.layer?.cornerRadius = 18
		controller.view.layer?.masksToBounds = true
	}

	func show(
		relativeTo rect: NSRect,
		of anchor: NSView
	)
	{
		guard let window = anchor.window, let content = window.contentView
		else
		{
			return
		}
		close()
		self.anchor = anchor
		anchorSuperview = anchor.superview
		parentWindow = window
		previousResponder = window.firstResponder
		appearanceBinding = DesktopPanelAppearanceBinding(
			panel: panel,
			source: anchor
		)
		if placement == .centered
		{
			let dimmer = DesktopSurface(NSColor.black.withAlphaComponent(0.14))
			dimmer.frame = content.bounds
			dimmer.autoresizingMask = [.width, .height]
			content.addSubview(dimmer)
			self.dimmer = dimmer
		}
		let observer = SearchPanelAnchorObserver(frame: .zero)
		observer.onWindowChange =
		{
			[weak self] in self?.reposition()
		}
		anchor.addSubview(observer)
		attachmentObserver = observer
		isShown = true
		reposition()
		guard isShown
		else
		{
			return
		}
		window.addChildWindow(
			panel,
			ordered: .above
		)
		panel.makeKeyAndOrderFront(nil)
		let center = NotificationCenter.default
		for name in [NSWindow.didResizeNotification,
						NSWindow.didMoveNotification,
						NSWindow.didUpdateNotification,
						NSWindow.didChangeScreenNotification]
		{
			center.addObserver(
				self,
				selector: #selector(reposition),
				name: name,
				object: window
			)
		}
		for name in [NSWindow.willCloseNotification,
						NSWindow.didMiniaturizeNotification,
						NSWindow.didResignMainNotification]
		{
			center.addObserver(
				self,
				selector: #selector(presentationEnded),
				name: name,
				object: window
			)
		}
		center.addObserver(
			self,
			selector: #selector(presentationEnded),
			name: NSApplication.didResignActiveNotification,
			object: nil
		)
		eventMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
		)
		{
			[weak self] event in
			let shouldForward = MainActor.assumeIsolated
			{
				self?.shouldForward(event) ?? true
			}
			return shouldForward ? event : nil
		}
	}

	private func shouldForward(_ event: NSEvent) -> Bool
	{
		guard isShown
		else
		{
			return true
		}
		if event.type == .keyDown
		{
			guard event.window === panel || event.window === parentWindow
			else
			{
				return true
			}
			if onKeyDown?(event) == true
			{
				return false
			}
			if event.keyCode == 53
			{
				close()
				return false
			}
		}
		else if event.window !== panel
		{
			let consume = placement == .centered && event.window === parentWindow
			dismiss(returnFocus: false)
			return !consume
		}
		return true
	}

	@objc private func presentationEnded()
	{
		dismiss(returnFocus: false)
	}

	func close()
	{
		dismiss(returnFocus: true)
	}

	private func dismiss(returnFocus: Bool)
	{
		guard isShown
		else
		{
			return
		}
		isShown = false
		let restoreFocus = returnFocus && panel.isKeyWindow && NSApp.isActive
			&& anchor?.window === parentWindow
		if let eventMonitor
		{
			NSEvent.removeMonitor(eventMonitor)
		}
		eventMonitor = nil
		NotificationCenter.default.removeObserver(self)
		appearanceBinding?.invalidate()
		appearanceBinding = nil
		attachmentObserver?.onWindowChange = nil
		attachmentObserver?.removeFromSuperview()
		attachmentObserver = nil
		anchorSuperview = nil
		dimmer?.removeFromSuperview()
		dimmer = nil
		parentWindow?.removeChildWindow(panel)
		panel.orderOut(nil)
		if restoreFocus, let window = parentWindow, window.isVisible
		{
			window.makeKey()
			window.makeFirstResponder(previousResponder)
		}
		anchor = nil
		parentWindow = nil
		previousResponder = nil
	}

	@objc private func reposition()
	{
		guard let anchor, let window = parentWindow, let content = window.contentView,
				anchor.window === window, anchor.superview === anchorSuperview,
				!anchor.isHiddenOrHasHiddenAncestor
		else
		{
			dismiss(returnFocus: false)
			return
		}
		let contentFrame = window.convertToScreen(content.convert(
			content.bounds,
			to: nil
		))
		let screen = window.screen?.visibleFrame ?? contentFrame
		let available = contentFrame.intersection(screen).insetBy(
			dx: 12,
			dy: 12
		)
		let size = NSSize(
			width: min(
				requestedSize.width,
				max(
					1,
					available.width
				)
			),
			height: min(
				requestedSize.height,
				max(
					1,
					available.height
				)
			)
		)
		let anchorFrame = window.convertToScreen(anchor.convert(
			anchor.bounds,
			to: nil
		))
		let x = placement == .centered ? available.midX - size.width / 2
			: anchorFrame.midX - size.width / 2
		let y = placement == .centered ? available.midY - size.height / 2
			: anchorFrame.minY - 8 - size.height
		// Set the controller's preference after attachment and before the final native frame.
		if controller.preferredContentSize != size
		{
			controller.preferredContentSize = size
		}
		let frame = NSRect(
			x: min(
				max(
					x,
					available.minX
				),
				available.maxX - size.width
			),
			y: min(
				max(
					y,
					available.minY
				),
				available.maxY - size.height
			),
			width: size.width,
			height: size.height
		)
		if panel.frame != frame
		{
			panel.setFrame(
				frame,
				display: true
			)
		}
		controller.view.layoutSubtreeIfNeeded()
	}
}

@MainActor
private final class SearchPanelWindow: NSPanel
{
	override var canBecomeKey: Bool
	{
		true
	}
	override var canBecomeMain: Bool
	{
		false
	}
}

@MainActor
private final class SearchPanelAnchorObserver: NSView
{
	var onWindowChange: (() -> Void)?

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		onWindowChange?()
	}

	override func hitTest(_ point: NSPoint) -> NSView?
	{
		nil
	}
}
