import AppKit

/// Content-only controllers whose native menu surface is supplied by the popover host.
@MainActor
protocol DesktopPopoverMaterialContent: AnyObject
{
}

/// Inline search-suggestion content receives its opaque surface and padding from the host.
@MainActor
protocol DesktopPopoverSearchSuggestionsContent: AnyObject
{
}

/// Owns the complete arrowless popover window, surfaces, placement and presentation lifetime.
/// Content controllers supply menu selection and actions; the host owns native presentation policy.
@MainActor
final class DesktopPopoverHost
{
	enum Presentation
	{
		case account
		case choice(
			width: CGFloat,
			contentHeight: CGFloat
		)
		case sidebar(group: Int)
		case composer(ComposerPlacement)
		case search(
			placement: SearchPlacement,
			size: NSSize
		)

	}

	enum SearchPlacement
	{
		case centered, belowAnchor
	}

	struct ComposerPlacement
	{
		enum Alignment
		{
			case centered, leading, trailing
		}
		enum Width
		{
			case content, anchor
		}
		enum Height
		{
			case screen, aboveAnchor
		}
		enum Focus
		{
			case panel, parent
		}

		var alignment = Alignment.centered
		var width = Width.content
		var height = Height.screen
		var focus = Focus.panel
		var horizontalOffset: CGFloat = 0
		var anchorSpacing: CGFloat = 8
		var opensBelowAnchor = false
	}

	var onKeyDown: ((NSEvent) -> Bool)?
	var typeaheadRows: (() -> [NSButton])?
	var onTypeaheadSelection: ((NSButton) -> Void)?

	var shouldDismissForEscape: (() -> Bool)?
	var onPresentationChange: ((Bool) -> Void)?
	weak var focusAfterDismissal: NSView?
	private(set) var isShown = false
	let panel: NSPanel = DesktopPopoverWindow(
		contentRect: .zero,
		styleMask: [.borderless, .nonactivatingPanel],
		backing: .buffered,
		defer: true
	)
	let root = DesktopPopoverRootView()
	private(set) var primarySurface: DesktopPopoverSurface?
	private(set) var submenuSurface: DesktopPopoverSurface?
	private var searchSuggestionsSurface: DesktopSurface?
	private let controller: NSViewController?
	private let shadowOutset: CGFloat
	private let lifetime = DesktopPanelLifetime()
	private weak var anchor: NSView?
	private weak var anchorSuperview: NSView?
	private weak var parent: NSWindow?
	private weak var previousResponder: NSResponder?
	private var anchorRect = NSRect.zero
	private var anchorsToBounds = true
	private var miniaturizationPending = false
	private var menuTrackingDepth = 0
	private var attachmentObserver: DesktopPopoverAnchorObserver?
	private var presentation: Presentation
	private var dimmer: NSView?
	private var typeaheadPrefix = ""
	private var lastTypeaheadTime: TimeInterval?

	init(
		presentation: Presentation,
		content: NSView,
		controller: NSViewController? = nil,
		nativeShadow: Bool = false,
		shadowOutset: CGFloat = 0
	)
	{
		self.presentation = presentation
		self.controller = controller
		switch presentation
		{
		case .account: self.shadowOutset = LayoutTokens.AccountMenu.shadowOutset
		case .choice: self.shadowOutset = 24
		case .sidebar: self.shadowOutset = LayoutTokens.SidebarMenu.shadowOutset
		case .composer: self.shadowOutset = shadowOutset
		case .search: self.shadowOutset = 0
		}
		panel.isReleasedWhenClosed = false
		panel.backgroundColor = .clear
		panel.isOpaque = false
		panel.animationBehavior = .none
		panel.hasShadow = nativeShadow
		panel.contentView = root
		root.onOutsideClick =
		{
			[weak self] in self?.close()
		}
		switch presentation
		{
		case .account, .choice, .sidebar:
			let surface = DesktopPopoverSurface()
			primarySurface = surface
			root.addSubview(surface)
			if case .sidebar = presentation
			{
				let submenu = DesktopPopoverSurface()
				submenuSurface = submenu
				root.addSubview(submenu)
				submenu.isHidden = true
			}
			else
			{
				AppKitLayout.pin(
					content,
					to: surface,
					inset: 4
				)
			}
		case .composer, .search:
			if isComposer
			{
				panel.hidesOnDeactivate = true
				panel.becomesKeyOnlyIfNeeded = false
				panel.acceptsMouseMovedEvents = true
			}
			if isSearch
			{
				content.wantsLayer = true
				content.layer?.cornerRadius = 18
				content.layer?.masksToBounds = true
			}
			if let controller
			{
				let usesMenuSurface = isComposer && controller is DesktopPopoverMaterialContent
				let usesSearchSurface = isComposer
					&& controller is DesktopPopoverSearchSuggestionsContent
				if shadowOutset > 0 || usesMenuSurface || usesSearchSurface
				{
					let wrapper = NSViewController()
					wrapper.view = root
					wrapper.addChild(controller)
					if usesMenuSurface
					{
						let surface = DesktopPopoverSurface()
						primarySurface = surface
						root.addSubview(surface)
						AppKitLayout.pin(
							content,
							to: surface,
							inset: 0
						)
					}
					else if usesSearchSurface
					{
						let surface = DesktopSurface(
							AppKitColorTokens.slashMenu,
							cornerRadius: ShapeTokens.SearchSuggestions.cornerRadius,
							bordered: true
						)
						searchSuggestionsSurface = surface
						root.addSubview(surface)
						AppKitLayout.pin(
							content,
							to: surface,
							inset: LayoutTokens.SearchSuggestions.contentInset
						)
					}
					else
					{
						AppKitLayout.pin(
							content,
							to: root,
							inset: shadowOutset
						)
					}
					wrapper.preferredContentSize = NSSize(
						width: controller.preferredContentSize.width + 2 * shadowOutset,
						height: controller.preferredContentSize.height + 2 * shadowOutset
					)
					panel.contentViewController = wrapper
				}
				else
				{
					panel.contentViewController = controller
				}
			}
		}
	}

	func layoutMenuRows(
		main: [NSView],
		submenu: [NSView]
	)
	{
		for (surface, rows) in [(primarySurface, main), (submenuSurface, submenu)]
		{
			guard let surface
			else
			{
				continue
			}
			for (index, row) in rows.enumerated()
			{
				row.frame = NSRect(
					x: LayoutTokens.SidebarMenu.gutter,
					y: surface.bounds.height - LayoutTokens.SidebarMenu.gutter
						- CGFloat(index + 1) * LayoutTokens.MenuRow.height,
					width: surface.bounds.width - 2 * LayoutTokens.SidebarMenu.gutter,
					height: LayoutTokens.MenuRow.height
				)
			}
		}
	}

	func update(_ presentation: Presentation)
	{
		self.presentation = presentation
		if isShown
		{
			reposition()
		}
	}

	func show(
		from anchor: NSView,
		relativeTo rect: NSRect? = nil
	)
	{
		guard let parent = anchor.window, !isSearch || parent.contentView != nil
		else
		{
			return
		}
		if isShown
		{
			dismiss(restoreFocus: !isComposer)
		}
		self.anchor = anchor
		self.parent = parent
		anchorSuperview = anchor.superview
		previousResponder = parent.firstResponder
		anchorRect = rect ?? anchor.bounds
		anchorsToBounds = anchorRect == anchor.bounds
		miniaturizationPending = false
		menuTrackingDepth = 0
		typeaheadPrefix = ""
		lastTypeaheadTime = nil
		lifetime.bindAppearance(
			panel: panel,
			source: anchor
		)
		let observer = DesktopPopoverAnchorObserver(frame: .zero)
		observer.setAccessibilityElement(false)
		observer.onWindowChange =
		{
			[weak self] in self?.reposition()
		}
		attachmentObserver = observer
		anchor.addSubview(observer)
		if case .search(
			let placement,
			_
		) = presentation, placement == .centered,
			let contentView = parent.contentView
		{
			let dimmer = DesktopSurface(NSColor.black.withAlphaComponent(0.14))
			dimmer.frame = contentView.bounds
			dimmer.autoresizingMask = [.width, .height]
			contentView.addSubview(dimmer)
			self.dimmer = dimmer
		}
		isShown = true
		reposition()
		guard isShown
		else
		{
			return
		}
		parent.addChildWindow(
			panel,
			ordered: .above
		)
		if case .composer(let placement) = presentation, placement.focus == .parent
		{
			panel.orderFront(nil)
		}
		else
		{
			panel.makeKeyAndOrderFront(nil)
		}
		installObservers(parent)
		installEventMonitors()
		onPresentationChange?(true)
		if case .composer(let placement) = presentation, placement.alignment == .leading
		{
			reposition()
		}
	}

	func close()
	{
		dismiss(restoreFocus: true)
	}

	func dismiss(restoreFocus: Bool)
	{
		guard isShown
		else
		{
			return
		}
		let wasKey = panel.isKeyWindow
		let target: NSResponder?
		switch presentation
		{
		case .account, .choice: target = anchor
		case .sidebar, .search: target = previousResponder
		case .composer: target = focusAfterDismissal ?? anchor
		}
		let shouldRestore = restoreFocus && NSApp.isActive
			&& (isChoice || wasKey) && anchor?.window === parent
		let parent = parent
		let anchor = anchor
		isShown = false
		lifetime.invalidate()
		attachmentObserver?.onWindowChange = nil
		attachmentObserver?.removeFromSuperview()
		attachmentObserver = nil
		dimmer?.removeFromSuperview()
		dimmer = nil
		parent?.removeChildWindow(panel)
		panel.orderOut(nil)
		self.anchor = nil
		self.parent = nil
		anchorSuperview = nil
		previousResponder = nil
		miniaturizationPending = false
		menuTrackingDepth = 0
		if isComposer
		{
			onPresentationChange?(false)
		}
		if shouldRestore, let parent, parent.isVisible
		{
			parent.makeKey()
			parent.makeFirstResponder(target)
		}
		if isChoice
		{
			anchor?.needsDisplay = true
		}
		if !isComposer
		{
			onPresentationChange?(false)
		}
	}

	func shouldForward(_ event: NSEvent) -> Bool
	{
		guard isShown
		else
		{
			return true
		}
		if isComposer, menuTrackingDepth > 0
		{
			return true
		}
		if event.type == .keyDown
		{
			guard event.window === panel || event.window === parent
			else
			{
				return true
			}
			if onKeyDown?(event) == true
			{
				return false
			}
			if handleTypeahead(event)
			{
				return false
			}
			if (isSearch || isComposer), event.keyCode == 53, shouldDismissForEscape?() != false
			{
				close()
				return false
			}
			return true
		}
		if isComposer
		{
			guard let eventWindow = event.window
			else
			{
				return true
			}
			if eventWindow === panel || eventWindow.level.rawValue >= NSWindow.Level.popUpMenu
				.rawValue
			{
				return true
			}
			if panel.frame.insetBy(
				dx: shadowOutset,
				dy: shadowOutset
			)
			.contains(NSEvent.mouseLocation)
			{
				return true
			}
		}
		if isSearch
		{
			if event.window !== panel
			{
				let consume: Bool
				if case .search(
					.centered,
					_
				) = presentation
				{
					consume = event.window === parent
				}
				else
				{
					consume = false
				}
				dismiss(restoreFocus: false)
				return !consume
			}
			return true
		}
		if event.window === parent, let anchor
		{
			let point = anchor.convert(
				event.locationInWindow,
				from: nil
			)
			let rect = anchorsToBounds ? anchor.bounds : anchorRect
			if rect.contains(point)
			{
				if isChoice
				{
					dismiss(restoreFocus: false); return false
				}
				return true
			}
		}
		if isComposer
		{
			dismiss(restoreFocus: false)
			return true
		}
		if event.window !== panel
		{
			dismiss(restoreFocus: false)
		}
		else if isChoice, let surface = primarySurface,
				!surface.bounds.contains(surface.convert(
					event.locationInWindow,
					from: nil
				))
		{
			dismiss(restoreFocus: false)
			return false
		}
		return true
	}

	private func handleTypeahead(_ event: NSEvent) -> Bool
	{
		guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
				let characters = event.charactersIgnoringModifiers?.lowercased(),
				!characters.isEmpty,
				characters.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains),
				let rows = typeaheadRows?(), !rows.isEmpty
		else
		{
			return false
		}
		let previous = typeaheadPrefix
		let beginsNewSearch = lastTypeaheadTime == nil
			|| event.timestamp - (lastTypeaheadTime ?? 0) > 1
			|| event.timestamp < (lastTypeaheadTime ?? 0)
		if beginsNewSearch || previous == characters
		{
			typeaheadPrefix = characters
		}
		else
		{
			typeaheadPrefix += characters
		}
		lastTypeaheadTime = event.timestamp
		let focused = rows.firstIndex
		{
			$0 === panel.firstResponder
		}
		func find(
			_ prefix: String,
			includeCurrent: Bool
		) -> NSButton?
		{
			let start = focused ?? -1
			let initial = includeCurrent && focused != nil ? 0 : 1
			for distance in initial ..< initial + rows.count
			{
				let row = rows[(start + distance + rows.count) % rows.count]
				if row.isEnabled, row.title.folding(
					options: [.caseInsensitive, .diacriticInsensitive],
					locale: .current
				)
				.hasPrefix(prefix.folding(
					options: [.caseInsensitive, .diacriticInsensitive],
					locale: .current
				))
				{
					return row
				}
			}
			return nil
		}
		var match = find(
			typeaheadPrefix,
			includeCurrent: typeaheadPrefix.count > characters.count
		)
		if match == nil, typeaheadPrefix != characters
		{
			typeaheadPrefix = characters
			match = find(
				characters,
				includeCurrent: false
			)
		}
		guard let match
		else
		{
			return false
		}
		panel.makeFirstResponder(match)
		match.scrollToVisible(match.bounds)
		onTypeaheadSelection?(match)
		return true
	}

	func reposition()
	{
		if isComposer, miniaturizationPending
		{
			return
		}
		guard isShown, let anchor, let parent, anchor.window === parent,
				!anchor.isHiddenOrHasHiddenAncestor,
				!(isComposer || isSearch) || anchor.superview === anchorSuperview
		else
		{
			dismiss(restoreFocus: false)
			return
		}
		let rect = parent.convertToScreen(anchor.convert(
			anchorsToBounds ? anchor.bounds : anchorRect,
			to: nil
		))
		let screen = parent.screen?.visibleFrame ?? parent.frame
		let frame: NSRect
		switch presentation
		{
		case .account:
			let size = NSSize(
				width: LayoutTokens.AccountMenu.width,
				height: LayoutTokens.AccountMenu.height
			)
			frame = NSRect(
				x: min(
					max(
						rect.maxX + 4,
						screen.minX + 8
					),
					screen.maxX - size.width - 8
				),
				y: min(
					max(
						rect.minY,
						screen.minY + 8
					),
					screen.maxY - size.height - 8
				),
				width: size.width,
				height: size.height
			)
		case .choice(
			let width,
			let contentHeight
		):
			let available = screen.insetBy(
				dx: 8,
				dy: 8
			)
			let height = min(
				contentHeight,
				350,
				max(
					8,
					available.height - 8
				)
			)
			let below = rect.minY - 4 - height
			frame = NSRect(
				x: min(
					max(
						rect.maxX - width,
						available.minX
					),
					available.maxX - width
				),
				y: below >= available.minY ? below : min(
					rect.maxY + 4,
					available.maxY - height
				),
				width: width,
				height: height
			)
		case .sidebar:
			let width = LayoutTokens.SidebarMenu.mainWidth + LayoutTokens.SidebarMenu.submenuGap
				+ LayoutTokens.SidebarMenu.submenuWidth
			let height = LayoutTokens.SidebarMenu.height + LayoutTokens.SidebarMenu.rowHeight
			frame = NSRect(
				x: min(
					max(
						rect.minX,
						screen.minX + 8
					),
					screen.maxX - width - 8
				),
				y: max(
					min(
						rect.minY - 1,
						screen.maxY - 8
					) - height,
					screen.minY + 8
				),
				width: width,
				height: height
			)
		case .search(
			let placement,
			let size
		):
			guard let searchFrame = searchFrame(
				anchorRect: rect,
				parent: parent,
				placement: placement,
				size: size
			)
			else
			{
				return
			}
			frame = searchFrame
		case .composer(let placement):
			guard let composerFrame = composerFrame(
				anchorRect: rect,
				parent: parent,
				placement: placement
			)
			else
			{
				return
			}
			frame = composerFrame
		}
		let padded = frame.insetBy(
			dx: -shadowOutset,
			dy: -shadowOutset
		)
		if isComposer, panel.contentViewController !== controller
		{
			panel.contentViewController?.preferredContentSize = padded.size
		}
		if panel.frame != padded
		{
			panel.setFrame(
				padded,
				display: true
			)
			if case .composer(let placement) = presentation, placement.opensBelowAnchor
			{
				panel.setFrameTopLeftPoint(NSPoint(
					x: padded.minX.rounded(),
					y: padded.maxY.rounded()
				))
			}
			else if case .composer(let placement) = presentation, placement.alignment != .centered
			{
				panel.setFrameOrigin(NSPoint(
					x: padded.minX.rounded(),
					y: padded.minY.rounded()
				))
			}
		}
		if case .sidebar(let group) = presentation
		{
			// Columns remain anchored to the top of the shared, unflipped window root.
			let columnBottom = shadowOutset + frame.height - LayoutTokens.SidebarMenu.height
			primarySurface?.frame = NSRect(
				x: shadowOutset,
				y: columnBottom,
				width: LayoutTokens.SidebarMenu.mainWidth,
				height: LayoutTokens.SidebarMenu.height
			)
			submenuSurface?.frame = NSRect(
				x: shadowOutset + LayoutTokens.SidebarMenu.mainWidth + LayoutTokens.SidebarMenu
					.submenuGap,
				y: columnBottom - CGFloat(group) * LayoutTokens.SidebarMenu.rowHeight,
				width: LayoutTokens.SidebarMenu.submenuWidth,
				height: LayoutTokens.SidebarMenu.height
			)
		}
		else
		{
			primarySurface?.frame = NSRect(
				origin: NSPoint(
					x: shadowOutset,
					y: shadowOutset
				),
				size: frame.size
			)
		}
		panel.contentView?.layoutSubtreeIfNeeded()
		if case .composer(let placement) = presentation, placement.opensBelowAnchor,
			let surface = primarySurface
		{
			// Keep the visible body anchored to the top after AppKit rounds the panel's size.
			surface.setFrameOrigin(NSPoint(
				x: shadowOutset,
				y: root.bounds.height - shadowOutset - frame.height
			))
		}
		searchSuggestionsSurface?.frame = NSRect(
			origin: NSPoint(
				x: shadowOutset,
				y: shadowOutset
			),
			size: frame.size
		)
		panel.contentView?.layoutSubtreeIfNeeded()
	}

	private func searchFrame(
		anchorRect: NSRect,
		parent: NSWindow,
		placement: SearchPlacement,
		size requestedSize: NSSize
	) -> NSRect?
	{
		guard let content = parent.contentView
		else
		{
			return nil
		}
		let contentFrame = parent.convertToScreen(content.convert(
			content.bounds,
			to: nil
		))
		let available = contentFrame.intersection(parent.screen?.visibleFrame ?? contentFrame)
			.insetBy(
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
		if controller?.preferredContentSize != size
		{
			controller?.preferredContentSize = size
		}
		let x = placement == .centered ? available.midX - size.width / 2
			: anchorRect.midX - size.width / 2
		let y = placement == .centered ? available.midY - size.height / 2
			: anchorRect.minY - 8 - size.height
		return NSRect(
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
	}

	private func composerFrame(
		anchorRect rect: NSRect,
		parent: NSWindow,
		placement: ComposerPlacement
	) -> NSRect?
	{
		let screen = NSScreen.screens.first
		{
			$0.frame.intersects(rect)
		} ?? parent.screen
		guard let visible = screen?.visibleFrame, let controller
		else
		{
			return nil
		}
		let requested = controller.preferredContentSize
		let requestedWidth = placement.width == .anchor ? rect.width : requested.width
		let availableWidth = max(
			1,
			visible.width - 16
		)
		let screenHeight = max(
			1,
			visible.height - 2 * max(
				8,
				shadowOutset
			)
		)
		let availableHeight = placement.height == .aboveAnchor
			? min(
				screenHeight,
				max(
					1,
					visible.maxY - rect.maxY - placement.anchorSpacing
						- max(
							8,
							shadowOutset
						)
				)
			) : screenHeight
		let width = min(
			max(
				1,
				requestedWidth
			),
			availableWidth
		)
		if placement.width == .anchor, controller.preferredContentSize.width != width
		{
			controller.preferredContentSize.width = width
		}
		let height = min(
			max(
				1,
				requested.height
			),
			availableHeight
		)
		let alignedX: CGFloat
		switch placement.alignment
		{
		case .leading: alignedX = rect.minX
		case .trailing: alignedX = rect.maxX - width
		case .centered: alignedX = rect.midX - width / 2
		}
		let requestedX = alignedX + placement.horizontalOffset
		let requestedY = placement.opensBelowAnchor ? rect.minY - placement
			.anchorSpacing - height : rect.maxY + placement.anchorSpacing
		return NSRect(
			x: min(
				max(
					requestedX,
					visible.minX + 8
				),
				visible.maxX - width - 8
			),
			y: min(
				max(
					requestedY,
					visible.minY + 8
				),
				visible.maxY - height - 8
			),
			width: width,
			height: height
		)
	}

	private func installObservers(_ parent: NSWindow)
	{
		let geometry: [Notification.Name] = isComposer || isSearch
			? [NSWindow.didMoveNotification,
				NSWindow.didResizeNotification,
				NSWindow.didChangeScreenNotification,
				NSWindow.didUpdateNotification]
			: isChoice || isSidebar
			? [
				NSWindow.didMoveNotification,
				NSWindow.didResizeNotification,
				NSWindow.didUpdateNotification
			]
			: [NSWindow.didMoveNotification, NSWindow.didResizeNotification]
		for name in geometry
		{
			observe(
				name,
				object: parent
			)
			{
				[weak self] in self?.reposition()
			}
		}
		observe(
			NSWindow.willCloseNotification,
			object: parent
		)
		{
			[weak self] in self?.dismiss(restoreFocus: false)
		}
		if isSidebar || isSearch
		{
			observe(
				NSWindow.didMiniaturizeNotification,
				object: parent
			)
			{
				[weak self] in self?.dismiss(restoreFocus: false)
			}
		}
		else
		{
			observe(
				NSWindow.willMiniaturizeNotification,
				object: parent
			)
			{
				[weak self] in self?.miniaturizationPending = true
			}
			observe(
				NSWindow.didDeminiaturizeNotification,
				object: parent
			)
			{
				[weak self] in self?.restoreAfterMiniaturize()
			}
		}
		if !isChoice
		{
			observe(
				NSWindow.didResignMainNotification,
				object: parent
			)
			{
				[weak self] in self?.presentationEnded(NSWindow.didResignMainNotification)
			}
		}
		observe(
			NSApplication.didResignActiveNotification,
			object: isChoice ? nil : NSApp
		)
		{
			[weak self] in self?.presentationEnded(NSApplication.didResignActiveNotification)
		}
		if isComposer
		{
			observe(
				NSMenu.didBeginTrackingNotification,
				object: nil
			)
			{
				[weak self] in self?.menuTrackingDepth += 1
			}
			observe(
				NSMenu.didEndTrackingNotification,
				object: nil
			)
			{
				[weak self] in self?.menuTrackingDepth = max(
					0,
					(self?.menuTrackingDepth ?? 0) - 1
				)
			}
			anchor?.postsFrameChangedNotifications = true
			observe(
				NSView.frameDidChangeNotification,
				object: anchor
			)
			{
				[weak self] in self?.reposition()
			}
		}
	}

	private func observe(
		_ name: Notification.Name,
		object: Any?,
		handler: @escaping @MainActor () -> Void
	)
	{
		lifetime.addObserver(
			forName: name,
			object: object,
			queue: .main
		)
		{
			_ in MainActor.assumeIsolated
			{
				handler()
			}
		}
	}

	private func installEventMonitors()
	{
		let mask: NSEvent.EventTypeMask = isComposer || isChoice || isSearch
			? [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
			: [.leftMouseDown, .rightMouseDown, .keyDown]
		lifetime.monitorLocalEvents(matching: mask)
		{
			[weak self] event in
			let shouldForward = MainActor.assumeIsolated
			{
				self?.shouldForward(event) ?? true
			}
			return shouldForward ? event : nil
		}
		if !isChoice && !isSearch
		{
			let globalMask: NSEvent.EventTypeMask = isComposer
				? [.leftMouseDown, .rightMouseDown, .otherMouseDown] : [
					.leftMouseDown,
					.rightMouseDown
				]
			lifetime.monitorGlobalEvents(matching: globalMask)
			{
				[weak self] _ in MainActor.assumeIsolated
				{
					self?.dismiss(restoreFocus: false)
				}
			}
		}
	}

	private func presentationEnded(_ name: Notification.Name)
	{
		if !isSidebar && !isSearch, miniaturizationPending || parent?.isMiniaturized == true
		{
			return
		}
		if isComposer, name == NSWindow.didResignMainNotification, menuTrackingDepth > 0
		{
			return
		}
		dismiss(restoreFocus: false)
	}

	private func restoreAfterMiniaturize()
	{
		miniaturizationPending = false
		guard isShown
		else
		{
			return
		}
		reposition()
		guard isShown
		else
		{
			return
		}
		if isChoice
		{
			if let parent, parent.childWindows?.contains(panel) != true
			{
				parent.addChildWindow(
					panel,
					ordered: .above
				)
			}
			if NSApp.isActive
			{
				panel.makeKeyAndOrderFront(nil)
			}
			else
			{
				panel.orderFront(nil)
			}
		}
		else if !isComposer, parent?.isVisible == true, !panel.isVisible
		{
			panel.orderFront(nil)
		}
	}

	private var isSearch: Bool
	{
		if case .search = presentation
		{
			true
		}
		else
		{
			false
		}
	}

	private var isChoice: Bool
	{
		if case .choice = presentation
		{
			true
		}
		else
		{
			false
		}
	}
	private var isSidebar: Bool
	{
		if case .sidebar = presentation
		{
			true
		}
		else
		{
			false
		}
	}
	private var isComposer: Bool
	{
		if case .composer = presentation
		{
			true
		}
		else
		{
			false
		}
	}
}

@MainActor
final class DesktopPopoverRootView: NSView
{
	var onOutsideClick: (() -> Void)?
	override func mouseDown(with event: NSEvent)
	{
		onOutsideClick?()
	}
}

@MainActor
private final class DesktopPopoverWindow: NSPanel
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
private final class DesktopPopoverAnchorObserver: NSView
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
