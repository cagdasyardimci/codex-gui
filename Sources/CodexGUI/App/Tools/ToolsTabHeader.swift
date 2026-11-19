import AppKit

/// Tracks presses for the pane's stable header even when individual tabs are rebuilt.
@MainActor
final class ToolsTabHeader: NSView
{
	enum Target: Equatable
	{
		case select(UUID?)
		case close(UUID)

		var reorderableID: UUID?
		{
			if case .select(let id) = self
			{
				return id
			}
			return nil
		}
	}

	private struct Press
	{
		let target: Target
		let clickCount: Int
		let start: NSPoint
		let originalBounds: NSRect
		var dragLocation: NSPoint?
	}

	var onActivate: ((Target, Int) -> Void)?
	private let scrollView: ToolsTabScrollView
	private var press: Press?
	private var autoscrollTimer: Timer?
	private static let dragThreshold: CGFloat = 4

	init(scrollView: ToolsTabScrollView)
	{
		self.scrollView = scrollView
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override var mouseDownCanMoveWindow: Bool
	{
		false
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool
	{
		true
	}

	// Keep hover, menus and accessibility on the controls. Only primary presses
	// need a responder that outlives a rebuild of the individual tab views.
	override func hitTest(_ point: NSPoint) -> NSView?
	{
		let hit = super.hitTest(point)
		if NSApp.currentEvent?.type == .leftMouseDown, target(for: hit) != nil
		{
			return self
		}
		return hit
	}

	func acceptsPointerPress(_ event: NSEvent) -> Bool
	{
		event.type == .leftMouseDown && event.window === window &&
			tabControl(at: event.locationInWindow) != nil
	}

	func tabControl(at location: NSPoint) -> NSButton?
	{
		guard !isHiddenOrHasHiddenAncestor, alphaValue > 0,
				visibleRect.contains(convert(
				location,
				from: nil
				)),
				let button = super
				.hitTest(superview?.convert(
				location,
				from: nil
				) ?? location) as? NSButton,
				target(for: button) != nil
		else
		{
			return nil
		}
		return button
	}

	private func target(for view: NSView?) -> Target?
	{
		guard let button = view as? NSButton, button.isEnabled, button.alphaValue > 0,
				button.superview is ToolsTabSurface
		else
		{
			return nil
		}
		if let selection = button as? ToolsTabSelectionButton
		{
			return .select(selection.tabID)
		}
		return (button.cell?.representedObject as? UUID).map(Target.close)
	}

	override func mouseDown(with event: NSEvent)
	{
		clearPress()
		guard let window, let button = tabControl(at: event.locationInWindow),
				let target = target(for: button)
		else
		{
			super.mouseDown(with: event)
			return
		}
		let start = window.convertPoint(toScreen: event.locationInWindow)
		let buttonBounds = window.convertToScreen(button.convert(
			button.visibleRect,
			to: nil
		))
		// The tab's leading padding also belongs to its selection button.
		let originalBounds = buttonBounds.union(NSRect(
			x: start.x,
			y: start.y,
			width: 1,
			height: 1
		))
		press = Press(
			target: target,
			clickCount: event.clickCount,
			start: start,
			originalBounds: originalBounds
		)
		if button is ToolsTabSelectionButton
		{
			button.focusRingType = .none
			window.makeFirstResponder(button)
		}
	}

	override func mouseDragged(with event: NSEvent)
	{
		guard let window, let press, press.target.reorderableID != nil
		else
		{
			return
		}
		let location = window.convertPoint(toScreen: event.locationInWindow)
		guard press.dragLocation != nil || hypot(
			location.x - press.start.x,
			location.y - press.start.y
		) >= Self.dragThreshold
		else
		{
			return
		}
		self.press?.dragLocation = location
		updateDropMarker()
		if autoscrollTimer == nil
		{
			let timer = Timer(
				timeInterval: 1.0 / 60,
				repeats: true
			)
			{
				[weak self] timer in
				guard let self
				else
				{
					timer.invalidate()
					return
				}
				MainActor.assumeIsolated
				{
					self.updateDropMarker()
				}
			}
			autoscrollTimer = timer
			RunLoop.main.add(
				timer,
				forMode: .common
			)
		}
	}

	override func mouseUp(with event: NSEvent)
	{
		let completed = press
		clearPress()
		guard let completed, let window, !isHiddenOrHasHiddenAncestor
		else
		{
			return
		}
		let location = event.locationInWindow
		if completed.dragLocation != nil, let id = completed.target.reorderableID
		{
			_ = scrollView.dropTab(
				id,
				at: location
			)
		}
		else if target(for: tabControl(at: location)) == completed.target ||
			completed.originalBounds.contains(window.convertPoint(toScreen: location))
		{
			onActivate?(completed.target, completed.clickCount)
		}
	}

	override func cancelOperation(_ sender: Any?)
	{
		if press != nil
		{
			clearPress()
		}
		else
		{
			super.cancelOperation(sender)
		}
	}

	override func viewDidHide()
	{
		super.viewDidHide()
		clearPress()
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if let window
		{
			NotificationCenter.default.removeObserver(
				self,
				name: NSWindow.didResignKeyNotification,
				object: window
			)
		}
		clearPress()
		super.viewWillMove(toWindow: newWindow)
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		if let window
		{
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(clearPress),
				name: NSWindow.didResignKeyNotification,
				object: window
			)
		}
	}

	private func updateDropMarker()
	{
		if let location = press?.dragLocation, let window
		{
			scrollView.updateDropMarker(at: window.convertPoint(fromScreen: location))
		}
	}

	@objc private func clearPress()
	{
		press = nil
		autoscrollTimer?.invalidate()
		autoscrollTimer = nil
		scrollView.clearDropMarker()
	}
}
