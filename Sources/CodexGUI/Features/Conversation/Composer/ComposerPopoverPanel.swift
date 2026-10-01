import AppKit

@MainActor
final class ComposerPopoverPanel: NSObject
{
	var onPresentationChange: ((Bool) -> Void)?
	var preservesParentKeyboardFocus = false
	var matchesAnchorWidth = false
	var shouldDismissForEscape: (() -> Bool)?
	private(set) var isShown = false
	private let controller: NSViewController
	private let panel = ComposerOverlayPanel(
		contentRect: .zero,
		styleMask: [.borderless, .nonactivatingPanel],
		backing: .buffered,
		defer: true
	)
	private weak var anchor: NSView?
	private weak var parentWindow: NSWindow?
	private weak var anchorSuperview: NSView?
	private var anchorRect = NSRect.zero
	private var anchorsToBounds = false
	private var localMonitor: Any?
	private var globalMonitor: Any?
	private var attachmentObserver: ComposerAnchorObserver?
	private var menuTrackingDepth = 0

	init(contentViewController: NSViewController)
	{
		controller = contentViewController
		super.init()
		panel.contentViewController = controller
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.hasShadow = false
		panel.hidesOnDeactivate = true
		panel.isReleasedWhenClosed = false
		panel.becomesKeyOnlyIfNeeded = false
		panel.animationBehavior = .none
		panel.acceptsMouseMovedEvents = true
	}

	func show(
		relativeTo rect: NSRect,
		of anchor: NSView
	)
	{
		guard let window = anchor.window
		else
		{
			return
		}
		if isShown
		{
			dismiss(returnFocus: false)
		}
		self.anchor = anchor
		anchorSuperview = anchor.superview
		parentWindow = window
		panel.appearance = window.effectiveAppearance
		anchorRect = rect
		anchorsToBounds = rect == anchor.bounds
		isShown = true
		let observer = ComposerAnchorObserver(frame: .zero)
		observer.onWindowChange =
		{
			[weak self] in self?.reposition()
		}
		observer.setAccessibilityElement(false)
		attachmentObserver = observer
		anchor.addSubview(observer)
		installObservers(for: window)
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
		if preservesParentKeyboardFocus
		{
			panel.orderFront(nil)
		}
		else
		{
			panel.makeKeyAndOrderFront(nil)
		}
		installEventMonitors()
		onPresentationChange?(true)
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
		let shouldRestoreFocus =
			returnFocus && panel.isKeyWindow && NSApp.isActive
				&& anchor?.window === parentWindow
		let window = parentWindow
		let focusTarget = anchor
		isShown = false
		if let localMonitor
		{
			NSEvent.removeMonitor(localMonitor)
		}
		if let globalMonitor
		{
			NSEvent.removeMonitor(globalMonitor)
		}
		localMonitor = nil
		globalMonitor = nil
		NotificationCenter.default.removeObserver(self)
		attachmentObserver?.onWindowChange = nil
		attachmentObserver?.removeFromSuperview()
		attachmentObserver = nil
		window?.removeChildWindow(panel)
		panel.orderOut(nil)
		anchor = nil
		parentWindow = nil
		anchorSuperview = nil
		menuTrackingDepth = 0
		onPresentationChange?(false)
		if shouldRestoreFocus, let window, window.isVisible, let focusTarget
		{
			window.makeKey()
			window.makeFirstResponder(focusTarget)
		}
	}

	private func installObservers(for window: NSWindow)
	{
		let center = NotificationCenter.default
		for notification in [
			NSWindow.didMoveNotification,
			NSWindow.didResizeNotification,
			NSWindow.didChangeScreenNotification,
			NSWindow.didUpdateNotification,
		]
		{
			center.addObserver(
				self,
				selector: #selector(windowGeometryChanged),
				name: notification,
				object: window
			)
		}
		for notification in [
			NSWindow.willCloseNotification,
			NSWindow.didMiniaturizeNotification,
			NSWindow.didResignMainNotification,
		]
		{
			center.addObserver(
				self,
				selector: #selector(presentationEnded(_:)),
				name: notification,
				object: window
			)
		}
		center.addObserver(
			self,
			selector: #selector(presentationEnded(_:)),
			name: NSApplication.didResignActiveNotification,
			object: NSApp
		)
		center.addObserver(
			self,
			selector: #selector(menuTrackingBegan),
			name: NSMenu.didBeginTrackingNotification,
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(menuTrackingEnded),
			name: NSMenu.didEndTrackingNotification,
			object: nil
		)
		anchor?.postsFrameChangedNotifications = true
		if let anchor
		{
			center.addObserver(
				self,
				selector: #selector(windowGeometryChanged),
				name: NSView.frameDidChangeNotification,
				object: anchor
			)
		}
	}

	private func installEventMonitors()
	{
		localMonitor = NSEvent.addLocalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
		)
		{
			[weak self] event in
			let shouldForward = MainActor.assumeIsolated
			{
				self?.shouldForwardLocalEvent(event) ?? true
			}
			return shouldForward ? event : nil
		}
		globalMonitor = NSEvent.addGlobalMonitorForEvents(
			matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
		)
		{
			[weak self] _ in
			MainActor.assumeIsolated
			{
				self?.dismiss(returnFocus: false)
			}
		}
	}

	private func shouldForwardLocalEvent(_ event: NSEvent) -> Bool
	{
		guard isShown
		else
		{
			return true
		}

		// Menu tracking owns its events until the menu closes.
		guard menuTrackingDepth == 0
		else
		{
			return true
		}
		if event.type == .keyDown
		{
			let belongsToPresentation = event.window === panel || event.window === parentWindow
			let shouldHandleEscape = event.keyCode == 53 && belongsToPresentation
			if shouldHandleEscape
			{
				guard shouldDismissForEscape?() != false
				else
				{
					return true
				}
				dismiss(returnFocus: true)
				return false
			}
			return true
		}
		guard event.window != nil
		else
		{
			return true
		}
		if let eventWindow = event.window,
			eventWindow.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
		{
			return true
		}
		if panel.frame.contains(NSEvent.mouseLocation)
		{
			return true
		}
		if let anchor, event.window === parentWindow
		{
			let point = anchor.convert(
				event.locationInWindow,
				from: nil
			)
			let rect = anchorsToBounds ? anchor.bounds : anchorRect
			if rect.contains(point)
			{
				return true
			}
		}
		dismiss(returnFocus: false)
		return true
	}

	@objc private func windowGeometryChanged()
	{
		reposition()
	}

	@objc private func presentationEnded(_ notification: Notification)
	{
		if notification.name == NSWindow.didResignMainNotification, menuTrackingDepth > 0
		{
			return
		}
		dismiss(returnFocus: false)
	}

	@objc private func menuTrackingBegan()
	{
		menuTrackingDepth += 1
	}

	@objc private func menuTrackingEnded()
	{
		menuTrackingDepth = max(
			0,
			menuTrackingDepth - 1
		)
	}

	func reposition()
	{
		guard isShown, let anchor, let window = parentWindow,
				anchor.window === window, anchor.superview === anchorSuperview,
				!anchor.isHiddenOrHasHiddenAncestor
		else
		{
			dismiss(returnFocus: false)
			return
		}
		let rect = anchorsToBounds ? anchor.bounds : anchorRect
		let anchorRectInWindow = anchor.convert(
			rect,
			to: nil
		)
		let screenRect = window.convertToScreen(anchorRectInWindow)
		let screen = NSScreen.screens.first
		{
			$0.frame.intersects(screenRect)
		} ?? window.screen
		guard let visibleFrame = screen?.visibleFrame
		else
		{
			return
		}
		panel.appearance = window.effectiveAppearance
		let screenEdgeInset: CGFloat = 8
		let anchorToPanelSpacing: CGFloat = 8
		let requestedSize = controller.preferredContentSize
		let requestedWidth = matchesAnchorWidth ? screenRect.width : requestedSize.width
		let availableWidth = max(
			1,
			visibleFrame.width - 2 * screenEdgeInset
		)
		let availableHeight = max(
			1,
			visibleFrame.height - 2 * screenEdgeInset
		)
		let width = min(
			max(
				1,
				requestedWidth
			),
			availableWidth
		)
		// Borderless AppKit panels also consult their controller's preferred width during layout.
		if matchesAnchorWidth, controller.preferredContentSize.width != width
		{
			controller.preferredContentSize.width = width
		}

		let height = min(
			max(
				1,
				requestedSize.height
			),
			availableHeight
		)
		let x = min(
			max(
				screenRect.midX - width / 2,
				visibleFrame.minX + screenEdgeInset
			),
			visibleFrame.maxX - width - screenEdgeInset
		)
		let y = min(
			max(
				screenRect.maxY + anchorToPanelSpacing,
				visibleFrame.minY + screenEdgeInset
			),
			visibleFrame.maxY - height - screenEdgeInset
		)
		let frame = NSRect(
			x: x,
			y: y,
			width: width,
			height: height
		)
		if panel.frame != frame
		{
			panel.setFrame(
				frame,
				display: true
			)
		}
	}
}

@MainActor
private final class ComposerOverlayPanel: NSPanel
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
private final class ComposerAnchorObserver: NSView
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
